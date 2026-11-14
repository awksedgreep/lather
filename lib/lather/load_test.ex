defmodule Lather.LoadTest do
  @moduledoc """
  Lightweight load testing for Lather services.

  Runs a given operation many times concurrently and reports success,
  failure and latency statistics.

  ## Examples

      iex> is_integer(1)
      true

  """

  alias Lather.DynamicClient

  @doc """
  Run `iterations` concurrent invocations of `operation` against the
  client and return aggregate stats.
  """
  @spec run(DynamicClient.t(), String.t(), map(), keyword()) :: map()
  def run(client, operation, params, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 10)
    concurrency = Keyword.get(opts, :concurrency, 5)
    timeout = Keyword.get(opts, :timeout, 10_000)

    invocations = Enum.map(1..iterations, fn _ -> {operation, params} end)

    start = System.monotonic_time()

    results =
      DynamicClient.call_many(client, invocations, concurrency: concurrency, timeout: timeout)

    total_us = System.monotonic_time() - start

    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)

    %{
      total: length(results),
      success: successes,
      failure: length(results) - successes,
      concurrency: concurrency,
      total_ms: (total_us / 1000) |> trunc(),
      average_ms:
        case length(results) do
          0 -> 0
          n -> div(total_us, n * 1000)
        end
    }
  end
end
