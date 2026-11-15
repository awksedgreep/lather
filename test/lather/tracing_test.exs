defmodule Lather.TracingTest do
  use ExUnit.Case, async: false

  alias Lather.Tracing
  alias Lather.Tracing.Collector

  test "span emits telemetry and records in collector" do
    name = :"TracingTest-#{inspect(self())}"
    {:ok, pid} = Collector.start_link(name: name)
    on_exit(fn -> Process.exit(pid, :kill) end)

    :telemetry.attach(
      "test-span",
      [:lather, :soap, :request, :stop],
      fn _event, _measurements, metadata, _config ->
        send(self(), {:span, metadata})
      end,
      nil
    )

    result = Tracing.span("Echo", %{operation: "Echo"}, fn -> {:ok, "body"} end, name)

    assert result == {:ok, "body"}

    assert_received {:span, metadata}
    assert metadata[:operation] == "Echo"
    assert metadata[:duration_us]

    spans = Collector.spans(name)
    assert length(spans) == 1
    assert hd(spans)[:trace_id]
  end

  test "trace context and traceparent format" do
    context = Tracing.trace_context([])

    assert String.length(context[:trace_id]) == 32
    assert String.length(context[:span_id]) == 16

    traceparent = Tracing.traceparent(context)
    assert String.starts_with?(traceparent, "00-")
  end

  test "collector can be cleared" do
    name = :"TracingClearTest-#{inspect(self())}"
    {:ok, pid} = Collector.start_link(name: name)
    on_exit(fn -> Process.exit(pid, :kill) end)

    Tracing.span("Clear", %{operation: "Clear"}, fn -> :ok end, name)
    assert length(Collector.spans(name)) == 1

    assert Collector.clear(name) == :ok
    assert Collector.spans(name) == []
  end

  test "start_link defaults to the collector module name" do
    case Collector.start_link() do
      {:ok, pid} -> on_exit(fn -> Process.exit(pid, :kill) end)
      {:error, {:already_started, _pid}} -> :ok
    end

    assert Collector.spans(Lather.Tracing.Collector) == []
  end
end
