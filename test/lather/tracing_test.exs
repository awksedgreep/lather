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
end
