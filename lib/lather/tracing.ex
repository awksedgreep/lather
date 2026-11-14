defmodule Lather.Tracing do
  @moduledoc """
  OpenTelemetry-style request tracing for Lather.

  Spans are emitted as `:telemetry` events and can optionally be
  recorded in a `Lather.Tracing.Collector` for inspection.

  Events:

    * `[:lather, :soap, :request, :start]`
    * `[:lather, :soap, :request, :stop]`

  with attributes such as `trace_id`, `span_id`, `operation`, `endpoint`,
  `status` and `duration_us`.

  ## Examples

      iex> {:ok, _} = Lather.Tracing.Collector.start_link(name: :demo_collector)
      iex> result = Lather.Tracing.span("Echo", %{operation: "Echo"}, fn -> :ok end)
      iex> result
      :ok

  """

  alias Lather.Tracing.Collector

  @doc """
  Generates a W3C-style trace id (16 random bytes, hex).
  """
  @spec trace_id() :: String.t()
  def trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @doc """
  Generates a span id (8 random bytes, hex).
  """
  @spec span_id() :: String.t()
  def span_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  @doc """
  Wraps `fun` in a tracing span, emitting telemetry start/stop events
  and recording the span in the collector (when provided).
  """
  @spec span(String.t(), map(), (-> term()), GenServer.on_start() | nil) :: term()
  def span(name, attributes, fun, collector \\ nil) do
    span_attrs =
      Map.merge(
        %{
          trace_id: attributes[:trace_id] || trace_id(),
          span_id: attributes[:span_id] || span_id(),
          name: name
        },
        attributes
      )

    start = System.monotonic_time()
    :telemetry.execute([:lather, :soap, :request, :start], %{count: 1}, span_attrs)

    result = fun.()

    duration = System.monotonic_time() - start
    stop_attrs = Map.put(span_attrs, :duration_us, duration)

    :telemetry.execute(
      [:lather, :soap, :request, :stop],
      %{count: 1, duration: duration},
      stop_attrs
    )

    if collector do
      Collector.record(collector, stop_attrs)
    end

    result
  end

  @doc """
  Returns the current tracing context (trace id / span id) from a
  keyword list of call options, creating one if absent.
  """
  @spec trace_context(keyword()) :: map()
  def trace_context(options) do
    case Keyword.get(options, :trace_id) do
      nil -> %{trace_id: trace_id(), span_id: span_id()}
      trace -> %{trace_id: trace, span_id: Keyword.get(options, :span_id) || span_id()}
    end
  end

  @doc """
  Builds W3C trace context headers suitable for propagation to other
  services.
  """
  @spec traceparent(map()) :: String.t()
  def traceparent(context) do
    "00-#{context[:trace_id]}-#{context[:span_id]}-01"
  end
end

defmodule Lather.Tracing.Collector do
  @moduledoc """
  In-memory collector of tracing spans, useful for tests and
  observability tooling.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec record(GenServer.on_start(), map()) :: :ok
  def record(collector, attributes) do
    GenServer.call(collector, {:record, attributes})
  end

  @spec spans(GenServer.on_start()) :: [map()]
  def spans(collector) do
    GenServer.call(collector, :spans)
  end

  @spec clear(GenServer.on_start()) :: :ok
  def clear(collector) do
    GenServer.call(collector, :clear)
  end

  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call({:record, attributes}, _from, state) do
    {:reply, :ok, state ++ [attributes]}
  end

  def handle_call(:spans, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, []}
  end
end
