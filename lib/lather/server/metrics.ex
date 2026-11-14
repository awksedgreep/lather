defmodule Lather.Server.Metrics do
  @moduledoc """
  In-memory usage analytics for an enhanced-plug server instance.

  Tracks total requests, error requests, cumulative response duration, and
  per-status-code counts using an ETS table. Created by
  `Lather.Server.EnhancedPlug.init/1` when `:enable_metrics` is set and
  exposed at `GET /service?metrics`.
  """

  def new do
    table = :ets.new(:lather_metrics, [:set, :public])
    :ets.insert(table, {:requests, 0})
    :ets.insert(table, {:errors, 0})
    :ets.insert(table, {:duration_us, 0})
    %{table: table}
  end

  def record(metrics, status, duration_microseconds) when is_integer(status) do
    try do
      ensure_counter(metrics.table, {:status, status})

      :ets.update_counter(metrics.table, :requests, 1)
      :ets.update_counter(metrics.table, :duration_us, duration_microseconds)

      if status >= 400 do
        :ets.update_counter(metrics.table, :errors, 1)
      end

      :ets.update_counter(metrics.table, {:status, status}, 1)
    rescue
      ArgumentError -> :ok
    end
  end

  defp ensure_counter(table, key) do
    case :ets.lookup(table, key) do
      [] -> :ets.insert(table, {key, 0})
      _ -> :ok
    end
  end

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

    %{
      requests: requests,
      errors: counter.(:errors),
      total_duration_us: total_duration_us,
      average_duration_ms:
        if(requests > 0, do: Float.round(total_duration_us / requests / 1000, 2), else: 0.0),
      status_counts: status_counts
    }
  end
end
