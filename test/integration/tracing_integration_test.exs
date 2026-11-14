defmodule Lather.TracingIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils
  alias Lather.Tracing.Collector

  defmodule TraceService do
    @moduledoc false
    use Lather.Server

    @service_name "TraceService"
    @namespace "urn:trace:service"

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

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: TraceService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    name = :"TraceCollector-#{inspect(self())}"
    {:ok, collector_pid} = Collector.start_link(name: name)
    on_exit(fn -> Process.exit(collector_pid, :kill) end)

    {:ok, client: client, collector: name}
  end

  test "traced calls record spans", %{client: client, collector: collector} do
    {:ok, response} =
      Lather.DynamicClient.call(
        client,
        "Echo",
        %{"message" => "hi"},
        trace: true,
        trace_collector: collector
      )

    assert response["echo"] == "hi"

    spans = Collector.spans(collector)
    assert length(spans) == 1
    span = hd(spans)
    assert span[:operation] == "Echo"
    assert span[:endpoint] =~ "127.0.0.1"
    assert span[:duration_us]
  end

  test "untraced calls do not record spans", %{client: client, collector: collector} do
    {:ok, _response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    assert Collector.spans(collector) == []
  end
end
