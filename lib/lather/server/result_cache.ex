defmodule Lather.Server.ResultCache do
  @moduledoc """
  A per-server ETS cache for successful operation results.

  Results are keyed by `{service_module, operation_name, params_hash}` and
  expire after a configurable TTL (default 300 seconds). Only successful
  (`{:ok, result}`) invocations are cached; faults and errors are never
  stored.

  The cache is created by `Lather.Server.EnhancedPlug.init/1` when the
  `:cache_results` option is enabled and lives for as long as the server
  process that created it.
  """

  def new(ttl_seconds) do
    %{
      table: :ets.new(:lather_result_cache, [:set, :public]),
      ttl: ttl_seconds
    }
  end

  def get(cache, service, operation, params) do
    key = key(service, operation, params)
    now = System.monotonic_time(:millisecond)

    try do
      case :ets.lookup(cache.table, key) do
        [{^key, result, expires_at}] when expires_at > now -> {:hit, result}
        _ -> :miss
      end
    rescue
      ArgumentError -> :miss
    end
  end

  def put(cache, service, operation, params, result) do
    key = key(service, operation, params)
    expires_at = System.monotonic_time(:millisecond) + cache.ttl * 1000

    try do
      :ets.insert(cache.table, {key, result, expires_at})
    rescue
      ArgumentError -> :ok
    end
  end

  def clear(cache) do
    try do
      :ets.delete_all_objects(cache.table)
    rescue
      ArgumentError -> :ok
    end
  end

  defp key(service, operation, params) do
    {service, operation, :erlang.phash2(params)}
  end
end
