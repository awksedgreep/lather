defmodule Lather.Prefetch do
  @moduledoc """
  Client-side predictive prefetching for related SOAP operations.

  After a response is received, `Lather.DynamicClient` can asynchronously
  prefetch operations declared as related (via the `:prefetch` call
  option or `prefetch_map:` service metadata). Later calls with the same
  operation and parameters are served from the in-memory prefetch cache.

  ## Examples

      {:ok, pool} = Lather.Prefetch.start_link()

      {:ok, response} =
        Lather.DynamicClient.call(client, "GetUser", %{"id" => "1"},
          prefetch: [{"GetPermissions", %{"id" => "1"}}],
          prefetch_pool: pool
        )

      # Later, this call is answered from the prefetch cache:
      {:ok, cached} = Lather.DynamicClient.call(client, "GetPermissions", %{"id" => "1"}, prefetch_pool: pool)
      cached["prefetched"] # true

  """

  use GenServer

  @default_ttl 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Store a prefetched result for `{operation, params}`.
  """
  def put(pool, operation, params, result) do
    GenServer.call(pool, {:put, operation, params, result})
  end

  @doc """
  Fetch a cached result, if present and not expired.
  """
  def fetch(pool, operation, params) do
    GenServer.call(pool, {:fetch, operation, params})
  end

  @doc """
  Number of entries currently stored.
  """
  def size(pool) do
    GenServer.call(pool, :size)
  end

  @doc """
  Clear the cache.
  """
  def clear(pool) do
    GenServer.call(pool, :clear)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       ttl: Keyword.get(opts, :ttl, @default_ttl),
       entries: %{},
       clock: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_call({:put, operation, params, result}, _from, state) do
    key = {operation, canonical(params)}
    entries = Map.put(state.entries, key, {result, state.clock})
    {:reply, :ok, %{state | entries: entries}}
  end

  def handle_call({:fetch, operation, params}, _from, state) do
    key = {operation, canonical(params)}

    case Map.get(state.entries, key) do
      {result, stored_at} ->
        if state.clock - stored_at <= state.ttl do
          {:reply, {:ok, result}, state}
        else
          {:reply, :miss, %{state | entries: Map.delete(state.entries, key)}}
        end

      nil ->
        {:reply, :miss, state}
    end
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.entries), state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | entries: %{}}}
  end

  defp canonical(params) when is_map(params) do
    params |> Map.to_list() |> Enum.sort()
  end

  defp canonical(other), do: other
end
