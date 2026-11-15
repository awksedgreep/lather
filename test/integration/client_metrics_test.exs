defmodule Lather.Integration.ClientMetricsTest do
  @moduledoc """
  Client-side telemetry: `Lather.Http.Metrics` handles attached to a
  `Lather.DynamicClient` accumulate request counts, durations, status codes,
  per-operation counts, and reliable-messaging retries.
  """
  use ExUnit.Case, async: false

  alias Lather.DynamicClient
  alias Lather.Http.Metrics
  alias Lather.Http.Transport
  alias Lather.TestUtils

  defmodule ClientMetricsService do
    @moduledoc false
    use Lather.Server

    @service_name "ClientMetricsService"
    @namespace "urn:clientmetrics"

    soap_operation "Ping" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("pong", :string)
      end
    end

    def ping(%{"message" => message}), do: {:ok, %{"pong" => message}}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: ClientMetricsService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  test "metrics: true accumulates analytics for the client", %{base_url: base_url} do
    {:ok, client} = DynamicClient.new("#{base_url}?wsdl", metrics: true)

    {:ok, _} = DynamicClient.call(client, "Ping", %{"message" => "one"})
    {:ok, _} = DynamicClient.call(client, "Ping", %{"message" => "two"})

    snapshot = DynamicClient.metrics(client)

    assert snapshot.requests == 2
    assert snapshot.errors == 0
    assert snapshot.retries == 0
    assert Map.new(snapshot.operation_counts)["Ping"] == 2
    assert Map.new(snapshot.status_counts)[200] == 2
    assert snapshot.total_duration_us > 0
    assert snapshot.average_duration_ms > 0.0
  end

  test "clients without metrics report nil", %{base_url: base_url} do
    {:ok, client} = DynamicClient.new("#{base_url}?wsdl")
    assert DynamicClient.metrics(client) == nil
  end

  test "a shared handle aggregates across clients", %{base_url: base_url} do
    metrics = Metrics.new()

    {:ok, first} = DynamicClient.new("#{base_url}?wsdl", metrics: metrics)
    {:ok, second} = DynamicClient.new("#{base_url}?wsdl", metrics: metrics)

    {:ok, _} = DynamicClient.call(first, "Ping", %{"message" => "a"})
    {:ok, _} = DynamicClient.call(second, "Ping", %{"message" => "b"})

    assert Metrics.snapshot(metrics).requests == 2
  end

  test "server errors are recorded as client errors", %{base_url: base_url} do
    metrics = Metrics.new()

    {:error, _fault} = Transport.post(base_url, "not xml at all", metrics: metrics)

    snapshot = Metrics.snapshot(metrics)
    assert snapshot.requests == 1
    assert snapshot.errors == 1
    assert Map.new(snapshot.status_counts)[400] == 1
  end

  test "every transport request emits a client telemetry event", %{base_url: base_url} do
    event_id = "client-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      event_id,
      [:lather, :client, :request, :stop],
      fn _event, measurements, metadata, _config ->
        send(self(), {:client_request, measurements, metadata})
      end,
      nil
    )

    {:ok, client} = DynamicClient.new("#{base_url}?wsdl")
    {:ok, _} = DynamicClient.call(client, "Ping", %{"message" => "telemetry"})

    assert_received {:client_request, measurements, metadata}
    assert metadata.status == 200
    assert metadata.operation == "Ping"
    assert metadata.method == "POST"
    assert measurements.duration >= 0

    :telemetry.detach(event_id)
  end
end
