defmodule Lather.Server.OpenAPIGeneratorTest do
  use ExUnit.Case, async: true

  alias Lather.Server.OpenAPIGenerator

  defmodule SampleService do
    use Lather.Server

    @namespace "http://example.com/sample"
    @service_name "SampleService"
    @api_version "2.3.0"

    soap_type "User" do
      description("A user record")

      element("id", :string, required: true)
      element("name", :string, required: true)
      element("age", :int)
      element("score", :double)
      element("active", :boolean)
      element("created_at", :dateTime)
      element("tags", :string, max_occurs: 10)
    end

    soap_operation "GetUser" do
      description("Fetch a user by id")

      input do
        parameter("userId", :string, required: true)
      end

      output do
        parameter("user", "User")
      end
    end

    soap_operation "SearchUsers" do
      input do
        parameter("limit", :int, default: 10)
        parameter("query", :string)
      end

      output do
        parameter("users", "User", max_occurs: 100)
        parameter("total", :integer)
      end
    end
  end

  defp spec do
    OpenAPIGenerator.generate(SampleService.__soap_service__(), "http://localhost:4000/soap/")
  end

  describe "document structure" do
    test "declares OpenAPI 3.1" do
      document = spec()
      assert document["openapi"] == "3.1.0"
      assert document["info"]["title"] == "SampleService API"
      assert document["info"]["version"] == "2.3.0"
      assert document["info"]["description"] =~ "SampleService"
    end

    test "normalizes the server URL" do
      assert spec()["servers"] == [%{"url" => "http://localhost:4000/soap"}]
    end

    test "the :version option overrides the service attribute" do
      document =
        OpenAPIGenerator.generate(
          SampleService.__soap_service__(),
          "http://localhost:4000/soap",
          version: "9.9.9"
        )

      assert document["info"]["version"] == "9.9.9"
    end

    test "services without @api_version default to 1.0.0" do
      service_info = %{name: "PlainService", operations: [], types: []}
      document = OpenAPIGenerator.generate(service_info, "http://localhost:4000/soap")
      assert document["info"]["version"] == "1.0.0"
    end

    test "every operation is a POST path item" do
      paths =
        spec()["paths"]
        |> Map.filter(fn {path, _item} ->
          String.starts_with?(path, "/api/")
        end)

      assert Map.keys(paths) == ["/api/GetUser", "/api/SearchUsers"]

      for {path, item} <- paths do
        assert is_map(item["post"]), "#{path} nests its operation under post"
        assert item["post"]["operationId"] in ["GetUser", "SearchUsers"]
        assert item["post"]["responses"]["200"]["content"]["application/json"]

        assert item["post"]["responses"]["400"]["content"]["application/json"]["schema"]["$ref"] ==
                 "#/components/schemas/Error"

        assert item["post"]["responses"]["500"]["content"]["application/json"]["schema"]["$ref"] ==
                 "#/components/schemas/Error"
      end
    end

    test "the built-in observability endpoints are documented" do
      paths = spec()["paths"]

      assert Map.has_key?(paths, "/health")
      assert Map.has_key?(paths, "/metrics")

      health = paths["/health"]["get"]
      assert health["operationId"] == "health"
      assert health["tags"] == ["Observability"]

      health_schema = health["responses"]["200"]["content"]["application/json"]["schema"]
      assert "status" in health_schema["required"]
      assert health_schema["properties"]["operations"]["type"] == "integer"

      metrics = paths["/metrics"]["get"]
      assert metrics["operationId"] == "metrics"
      assert metrics["description"] =~ "enable_metrics"

      metrics_schema = metrics["responses"]["200"]["content"]["application/json"]["schema"]
      assert metrics_schema["properties"]["average_duration_ms"]["type"] == "number"

      assert metrics_schema["properties"]["operation_counts"]["additionalProperties"]["type"] ==
               "integer"

      assert metrics["responses"]["404"]["description"] =~ "not enabled"
    end
  end

  describe "type mapping" do
    test "scalar types map to JSON schema types" do
      properties =
        spec()["components"]["schemas"]["User"]["properties"]

      assert properties["id"] == %{"type" => "string"}
      assert properties["age"] == %{"type" => "integer"}
      assert properties["score"] == %{"type" => "number"}
      assert properties["active"] == %{"type" => "boolean"}
      assert properties["created_at"] == %{"type" => "string", "format" => "date-time"}
    end

    test "repeated elements become arrays" do
      assert spec()["components"]["schemas"]["User"]["properties"]["tags"] ==
               %{"type" => "array", "items" => %{"type" => "string"}}
    end

    test "complex types become component schema refs" do
      body = spec()["paths"]["/api/GetUser"]["post"]["requestBody"]
      assert body["content"]["application/json"]["schema"]["required"] == ["userId"]

      output =
        spec()["paths"]["/api/GetUser"]["post"]["responses"]["200"]
        |> get_in(["content", "application/json", "schema", "properties", "data"])

      assert output["properties"]["user"] == %{"$ref" => "#/components/schemas/User"}
    end

    test "required and default values are preserved" do
      properties =
        spec()["paths"]["/api/SearchUsers"]["post"]["requestBody"]
        |> get_in(["content", "application/json", "schema", "properties"])

      assert properties["limit"]["default"] == 10
    end

    test "required lists come from required flags" do
      assert spec()["components"]["schemas"]["User"]["required"] == ["id", "name"]
    end
  end

  describe "component schemas" do
    test "soap types become named object schemas" do
      schemas = spec()["components"]["schemas"]
      assert Map.has_key?(schemas, "User")
      assert schemas["User"]["type"] == "object"
      assert schemas["User"]["description"] == "A user record"
    end

    test "an Error schema is provided" do
      error = spec()["components"]["schemas"]["Error"]
      assert error["required"] == ["code", "message"]
      assert error["properties"]["message"]["type"] == "string"
    end
  end
end
