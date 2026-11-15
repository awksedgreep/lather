defmodule Lather.Http.Metrics do
  @moduledoc """
  Client-side request analytics for Lather SOAP clients.

  A handle created with `new/0` is handed to `Lather.Http.Transport` through
  the `:metrics` option, or enabled on a `Lather.DynamicClient` with
  `metrics: true`. Every request the transport performs records its status,
  duration, and operation name; retries issued by `Lather.ReliableMessaging`
  are counted separately from the requests themselves.

  ## Examples

      metrics = Lather.Http.Metrics.new()

      {:ok, client} =
        Lather.DynamicClient.new("http://localhost:4000/soap?wsdl", metrics: metrics)

      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

      Lather.Http.Metrics.snapshot(metrics)
      # %{requests: 1, errors: 0, average_duration_ms: 12.4, ...}
  """

  @doc """
  Creates a new, empty metrics handle.
  """
  @spec new() :: map()
  def new do
    table = :ets.new(:lather_client_metrics, [:set, :public])
    :ets.insert(table, {:requests, 0})
    :ets.insert(table, {:errors, 0})
    :ets.insert(table, {:duration_us, 0})
    :ets.insert(table, {:retries, 0})
    %{table: table}
  end

  @doc """
  Records one completed request.

  `status` is the HTTP status code, or `0` when the request never reached the
  server (transport failure). `operation` is optional and, when given, is
  counted in `operation_counts`.
  """
  @spec record(map(), integer(), non_neg_integer(), String.t() | nil) :: :ok
  def record(metrics, status, duration_us, operation \\ nil) when is_integer(status) do
    try do
      ensure_counter(metrics.table, {:status, status})

      if is_binary(operation) do
        ensure_counter(metrics.table, {:operation, operation})
      end

      :ets.update_counter(metrics.table, :requests, 1)
      :ets.update_counter(metrics.table, :duration_us, duration_us)

      if status >= 400 or status == 0 do
        :ets.update_counter(metrics.table, :errors, 1)
      end

      :ets.update_counter(metrics.table, {:status, status}, 1)

      if is_binary(operation) do
        :ets.update_counter(metrics.table, {:operation, operation}, 1)
      end
    rescue
      ArgumentError -> :ok
    end
  end

  @doc """
  Records a retry performed by reliable messaging.
  """
  @spec record_retry(map()) :: :ok
  def record_retry(metrics) do
    try do
      :ets.update_counter(metrics.table, :retries, 1)
    rescue
      ArgumentError -> :ok
    end
  end

  @doc """
  Returns the current analytics as a plain map.
  """
  @spec snapshot(map()) :: map()
  def snapshot(metrics) do
    counter = fn key ->
      try do
        case :ets.lookup(metrics.table, key) do
          [{_, value}] -> value
          [] -> 0
        end
      rescue
        ArgumentError -> 0
      end
    end

    requests = counter.(:requests)
    total_duration_us = counter.(:duration_us)

    status_counts =
      try do
        for [status, count] <- :ets.match(metrics.table, {{:status, :"$1"}, :"$2"}) do
          {status, count}
        end
      rescue
        ArgumentError -> []
      end

    operation_counts =
      try do
        for [operation, count] <- :ets.match(metrics.table, {{:operation, :"$1"}, :"$2"}) do
          {operation, count}
        end
      rescue
        ArgumentError -> []
      end

    %{
      requests: requests,
      errors: counter.(:errors),
      retries: counter.(:retries),
      total_duration_us: total_duration_us,
      average_duration_ms:
        if(requests > 0, do: Float.round(total_duration_us / requests / 1000, 2), else: 0.0),
      status_counts: status_counts,
      operation_counts: operation_counts
    }
  end

  defp ensure_counter(table, key) do
    case :ets.lookup(table, key) do
      [] -> :ets.insert(table, {key, 0})
      _ -> :ok
    end
  end
end
