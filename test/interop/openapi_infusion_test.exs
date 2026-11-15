defmodule Lather.Interop.OpenAPIInfusionTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule InteropUserService do
    use Lather.Server

    @namespace "http://interop.example.com/users"
    @service_name "InteropUserService"

    soap_type "User" do
      description("A user record")

      element("id", :string, required: true)
      element("name", :string, required: true)
      element("email", :string)
      element("age", :int)
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

    soap_operation "ListUsers" do
      description("List users")

      input do
        parameter("limit", :int, default: 10)
        parameter("activeOnly", :boolean)
      end

      output do
        parameter("users", "User", max_occurs: 100)
        parameter("total", :int)
      end
    end

    soap_operation "CreateUser" do
      description("Create a user")

      input do
        parameter("name", :string, required: true)
        parameter("email", :string, required: true)
      end

      output do
        parameter("user", "User")
      end
    end

    def get_user(%{"userId" => user_id}) do
      {:ok,
       %{
         "user" => %{
           "id" => user_id,
           "name" => "Ada Lovelace",
           "email" => "ada@example.com",
           "age" => 36,
           "tags" => ["mathematics", "computing"]
         }
       }}
    end

    def list_users(_params) do
      {:ok,
       %{
         "users" => [%{"id" => "1", "name" => "Ada Lovelace"}],
         "total" => 1
       }}
    end

    def create_user(params) do
      {:ok, %{"user" => %{"id" => "new-1", "name" => params["name"], "email" => params["email"]}}}
    end
  end

  defmodule InteropRouter do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    match "/soap" do
      Lather.Server.EnhancedPlug.call(
        conn,
        Lather.Server.EnhancedPlug.init(
          service: Lather.Interop.OpenAPIInfusionTest.InteropUserService
        )
      )
    end

    match "/soap/*_rest" do
      Lather.Server.EnhancedPlug.call(
        conn,
        Lather.Server.EnhancedPlug.init(
          service: Lather.Interop.OpenAPIInfusionTest.InteropUserService
        )
      )
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:lather)
    {:ok, server_pid, port} = TestUtils.start_server(InteropRouter, 0)

    on_exit(fn ->
      try do
        GenServer.stop(server_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, port: port, spec_url: "http://127.0.0.1:#{port}/soap?openapi"}
  end

  describe "the enhanced plug serves the spec" do
    test "GET /soap?openapi returns a parseable OpenAPI 3.1 document", %{port: port} do
      {:ok, response} = Req.get("http://127.0.0.1:#{port}/soap?openapi")
      assert response.status == 200
      assert response.headers["content-type"] |> List.first() =~ "application/json"

      document = response.body

      assert document["openapi"] == "3.1.0"
      assert document["info"]["title"] == "InteropUserService API"

      operation_paths =
        document["paths"]
        |> Map.filter(fn {path, _item} ->
          String.starts_with?(path, "/api/")
        end)

      for {path, item} <- operation_paths do
        assert is_map(item["post"]), "#{path} has a post operation"
        assert is_map(item["post"]["requestBody"])
        assert item["post"]["responses"]["200"]
      end

      assert Map.has_key?(document["paths"], "/health")
      assert Map.has_key?(document["paths"], "/metrics")
    end

    test "GET /soap/openapi.json returns the same document", %{port: port} do
      {:ok, response} = Req.get("http://127.0.0.1:#{port}/soap/openapi.json")
      assert response.status == 200
      assert response.body["openapi"] == "3.1.0"
    end
  end

  describe "Infusion code generation against the live spec" do
    test "the spec loads as a valid OpenAPI document", %{spec_url: spec_url} do
      case Infusion.Spec.load(spec_url) do
        {:ok, spec} -> assert spec.version == "3.1.0"
        {:error, reason} -> flunk("Infusion rejected the spec: #{reason}")
      end
    end

    test "Infusion generates a compiling SDK with one function per operation", %{
      spec_url: spec_url
    } do
      {:ok, %{files: files, warnings: warnings}} = Infusion.generate(spec_url, name: "InteropSdk")

      assert warnings == []

      sources =
        for file <- files, String.ends_with?(file.path, ".ex"), do: file.source

      assert length(sources) >= 4

      for source <- sources do
        Code.string_to_quoted!(source)
      end

      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "lather_infusion_interop_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)

      for file <- files, String.ends_with?(file.path, ".ex") do
        path = Path.join([tmp_dir, file.path])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, file.source)
      end

      for file <- files, String.ends_with?(file.path, ".ex") do
        Code.require_file(Path.join([tmp_dir, file.path]))
      end

      # The generated SDK talks to the live Lather server over its JSON API.
      {:ok, body} = apply(InteropSdk.GetUser, :create, [%{"userId" => "42"}])
      assert body["success"] == true
      assert body["data"]["user"]["id"] == "42"
      assert body["data"]["user"]["name"] == "Ada Lovelace"

      {:ok, body} = apply(InteropSdk.ListUsers, :create, [%{"limit" => 5}])
      assert body["success"] == true
      assert body["data"]["total"] == 1

      {:ok, body} =
        apply(InteropSdk.CreateUser, :create, [
          %{"name" => "Grace", "email" => "grace@example.com"}
        ])

      assert body["success"] == true
      assert body["data"]["user"]["name"] == "Grace"

      # A required-parameter violation surfaces as a documented 400 error.
      {:error, error} = InteropSdk.GetUser.create(%{})
      assert error.status == 400
    end
  end
end
