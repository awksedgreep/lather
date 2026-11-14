defmodule Lather.LoadTestIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.LoadTest
  alias Lather.TestUtils

  defmodule LoadService do
    @moduledoc false
    use Lather.Server

    @service_name "LoadService"
    @namespace "urn:load:service"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(_params), do: {:ok, %{"pong" => "pong"}}
  end

  test "load test reports aggregate stats" do
    plug = {Lather.Server.EnhancedPlug, [service: LoadService, enable_metrics: true]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    stats = LoadTest.run(client, "Ping", %{}, iterations: 10, concurrency: 4)

    assert stats[:total] == 10
    assert stats[:success] == 10
    assert stats[:failure] == 0
    assert stats[:concurrency] == 4
    assert stats[:total_ms] >= 0
  end
end
