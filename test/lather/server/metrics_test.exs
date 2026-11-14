defmodule Lather.Server.MetricsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lather.Server.EnhancedPlug

  defmodule MetricsService do
    use Lather.Server

    @service_name "MetricsService"
    @api_version "1.0.0"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  test "metrics endpoint returns usage analytics" do
    config = EnhancedPlug.init(service: MetricsService, enable_metrics: true)

    conn(:get, "/soap?health") |> EnhancedPlug.call(config)
    conn(:get, "/soap?health") |> EnhancedPlug.call(config)
    conn(:post, "/soap", "bad xml") |> EnhancedPlug.call(config)

    response = conn(:get, "/soap?metrics") |> EnhancedPlug.call(config)
    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert body["service"] == "MetricsService"
    assert body["version"] == "1.0.0"
    assert body["requests"] == 3
    assert body["errors"] == 1
    assert body["average_duration_ms"] >= 0.0
    assert body["operations"] == 1
    assert body["uptime_seconds"] >= 0
  end

  test "status counts are tracked per code" do
    config = EnhancedPlug.init(service: MetricsService, enable_metrics: true)

    conn(:get, "/soap?health") |> EnhancedPlug.call(config)
    conn(:post, "/soap/api/Nonexistent", "{}") |> EnhancedPlug.call(config)

    response = conn(:get, "/soap?metrics") |> EnhancedPlug.call(config)
    body = Jason.decode!(response.resp_body)

    counts = Map.new(body["status_counts"])
    assert counts["200"] == 1
    assert counts["400"] == 1
  end

  test "metrics are disabled by default" do
    config = EnhancedPlug.init(service: MetricsService)
    response = conn(:get, "/soap?metrics") |> EnhancedPlug.call(config)

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] =~ "not enabled"
  end

  test "cache hits keep responses identical while metrics advance" do
    config =
      EnhancedPlug.init(service: MetricsService, enable_metrics: true, cache_results: true)

    body = Jason.encode!(%{"message" => "cached"})

    first = conn(:post, "/soap/api/Echo", body) |> EnhancedPlug.call(config)
    second = conn(:post, "/soap/api/Echo", body) |> EnhancedPlug.call(config)

    assert first.resp_body == second.resp_body

    metrics = conn(:get, "/soap?metrics") |> EnhancedPlug.call(config)
    snapshot = Jason.decode!(metrics.resp_body)
    assert snapshot["requests"] == 2
  end
end
