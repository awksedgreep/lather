defmodule Lather.Server.ObservabilityPathsTest do
  @moduledoc """
  The built-in observability endpoints are matched on complete path segments
  and can be relocated or disabled, so applications that own their own
  `/health` or `/metrics` routes are not hijacked.
  """
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lather.Server.EnhancedPlug

  defmodule PathService do
    @moduledoc false
    use Lather.Server

    @service_name "PathService"

    soap_operation "Ping" do
      input do
        parameter("seq", :int, required: true)
      end

      output do
        parameter("pong", :string)
      end
    end

    def ping(%{"seq" => seq}), do: {:ok, %{"pong" => "pong #{seq}"}}
  end

  defp call(method, path, opts \\ []) do
    config = EnhancedPlug.init([service: PathService] ++ opts)
    conn(method, path) |> EnhancedPlug.call(config)
  end

  defp health_json?(response), do: String.contains?(response.resp_body, "\"status\":\"ok\"")

  test "health is served at /health and under the base path" do
    assert health_json?(call(:get, "/health"))
    assert health_json?(call(:get, "/soap/health"))
  end

  test "paths that merely contain health are not hijacked" do
    for path <- ["/healthcare/patients", "/api/health-check", "/healthchecks", "/soap/healthz"] do
      response = call(:get, path)
      refute health_json?(response), "#{path} should not return the health payload"
    end
  end

  test "health_path can be relocated" do
    assert health_json?(call(:get, "/soap/ping-health", health_path: "/ping-health"))
    refute health_json?(call(:get, "/soap/health", health_path: "/ping-health"))
  end

  test "health_path: nil disables the built-in endpoint" do
    refute health_json?(call(:get, "/health", health_path: nil))
    refute health_json?(call(:get, "/soap?health", health_path: nil))
  end

  test "metrics_path can be relocated or disabled" do
    relocated = call(:get, "/soap/usage", metrics_path: "/usage", enable_metrics: true)
    assert relocated.status == 200
    assert Jason.decode!(relocated.resp_body)["requests"] == 0

    default = call(:get, "/soap/metrics", metrics_path: "/usage", enable_metrics: true)
    refute String.contains?(default.resp_body, "\"requests\"")

    disabled = call(:get, "/soap/metrics", metrics_path: nil, enable_metrics: true)
    refute String.contains?(disabled.resp_body, "\"requests\"")
  end

  test "the OpenAPI spec reflects relocated and disabled observability paths" do
    response =
      call(:get, "/soap?openapi",
        health_path: nil,
        metrics_path: "/usage"
      )

    document = Jason.decode!(response.resp_body)

    assert Map.has_key?(document["paths"], "/api/Ping")
    refute Map.has_key?(document["paths"], "/health")
    refute Map.has_key?(document["paths"], "/metrics")
    assert Map.has_key?(document["paths"], "/usage")
  end

  test "openapi_path: nil disables the spec endpoints" do
    refute String.contains?(
             call(:get, "/soap/openapi.json", openapi_path: nil).resp_body,
             "\"openapi\""
           )

    refute String.contains?(
             call(:get, "/soap?openapi", openapi_path: nil).resp_body,
             "\"openapi\""
           )
  end
end
