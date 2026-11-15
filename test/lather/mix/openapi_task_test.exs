defmodule Mix.Tasks.Lather.OpenapiTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defmodule TaskService do
    use Lather.Server

    @service_name "TaskService"
    @api_version "3.1.4"

    soap_operation "Ping" do
      description("Echo a message")

      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    soap_operation "Add" do
      input do
        parameter("a", :int, required: true)
        parameter("b", :int, required: true)
      end

      output do
        parameter("sum", :int)
      end
    end

    def ping(%{"message" => message}), do: {:ok, %{"echo" => message}}
    def add(%{"a" => a, "b" => b}), do: {:ok, %{"sum" => a + b}}
  end

  defp tmp_path(name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "lather_openapi_task_#{System.unique_integer([:positive])}_#{name}"
      )

    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "from a service module" do
    test "writes a valid OpenAPI 3.1 spec" do
      output = tmp_path("service.json")

      capture_io(fn ->
        Mix.Tasks.Lather.Openapi.run(["--service", inspect(TaskService), "--output", output])
      end)

      document = Jason.decode!(File.read!(output))

      assert document["openapi"] == "3.1.0"
      assert document["info"]["title"] == "TaskService API"
      assert document["info"]["version"] == "3.1.4"
      assert document["paths"]["/api/Ping"]["post"]["operationId"] == "Ping"

      assert document["paths"]["/api/Add"]["post"]["requestBody"]["content"]["application/json"][
               "schema"
             ]["required"] == ["a", "b"]
    end

    test "honors --version, --base-url, and --description" do
      output = tmp_path("override.json")

      capture_io(fn ->
        Mix.Tasks.Lather.Openapi.run([
          "--service",
          inspect(TaskService),
          "--output",
          output,
          "--version",
          "9.0.0",
          "--base-url",
          "https://api.example.com/soap/",
          "--description",
          "Hand-written description"
        ])
      end)

      document = Jason.decode!(File.read!(output))
      assert document["info"]["version"] == "9.0.0"
      assert document["info"]["description"] == "Hand-written description"
      assert document["servers"] == [%{"url" => "https://api.example.com/soap"}]
    end

    test "raises when neither --service nor --wsdl is given" do
      assert_raise Mix.Error, fn -> Mix.Tasks.Lather.Openapi.run([]) end
    end

    test "raises when both are given" do
      assert_raise Mix.Error, fn ->
        Mix.Tasks.Lather.Openapi.run(["--service", inspect(TaskService), "--wsdl", "x.wsdl"])
      end
    end

    test "raises for a module that is not a SOAP service" do
      assert_raise Mix.Error, fn -> Mix.Tasks.Lather.Openapi.run(["--service", "Integer"]) end
    end
  end

  describe "from a WSDL" do
    test "converts a generated WSDL into a spec" do
      wsdl =
        Lather.Server.WSDLGenerator.generate(
          TaskService.__soap_service__(),
          "http://localhost:4000/soap"
        )

      wsdl_path = tmp_path("service.wsdl")
      output = tmp_path("wsdl.json")
      File.write(wsdl_path, wsdl)

      capture_io(fn ->
        Mix.Tasks.Lather.Openapi.run(["--wsdl", wsdl_path, "--output", output])
      end)

      document = Jason.decode!(File.read!(output))

      assert document["openapi"] == "3.1.0"
      assert document["info"]["title"] == "TaskService API"
      assert document["servers"] == [%{"url" => "http://localhost:4000/soap/TaskService"}]

      for {path, item} <- document["paths"] do
        if String.starts_with?(path, "/api/") do
          assert is_map(item["post"])
        end
      end

      assert Map.has_key?(document["paths"], "/api/Ping")
      assert Map.has_key?(document["paths"], "/health")
      assert Map.has_key?(document["paths"], "/metrics")
    end

    test "the WSDL-derived spec loads in Infusion" do
      wsdl =
        Lather.Server.WSDLGenerator.generate(
          TaskService.__soap_service__(),
          "http://localhost:4000/soap"
        )

      wsdl_path = tmp_path("infusion.wsdl")
      output = tmp_path("infusion.json")
      File.write(wsdl_path, wsdl)

      capture_io(fn ->
        Mix.Tasks.Lather.Openapi.run(["--wsdl", wsdl_path, "--output", output])
      end)

      case Infusion.Spec.load(output) do
        {:ok, spec} -> assert spec.version == "3.1.0"
        {:error, reason} -> flunk("Infusion rejected the WSDL-derived spec: #{reason}")
      end
    end
  end
end
