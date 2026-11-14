defmodule Lather.Mtom.Cache do
  @moduledoc """
  In-memory cache for MTOM attachments keyed by content hash.

  Repeated sends of the same attachment content reuse the cached
  attachment (and its content id) instead of re-encoding it.

  ## Examples

      iex> {:ok, pid} = Lather.Mtom.Cache.start_link(name: :demo_cache)
      iex> attachment = %Lather.Mtom.Attachment{content_type: "text/plain", data: "hello"}
      iex> {:ok, _hash} = Lather.Mtom.Cache.store(:demo_cache, attachment)
      iex> Lather.Mtom.Cache.lookup(:demo_cache, "hello") |> elem(0)
      :hit

  """

  use GenServer

  @doc """
  Starts a cache process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Looks up attachment content by hash.

  Returns `{:hit, attachment}` or `{:miss, hash}`.
  """
  @spec lookup(GenServer.on_start(), binary()) :: {:hit, term()} | {:miss, String.t()}
  def lookup(cache, data) when is_binary(data) do
    GenServer.call(cache, {:lookup, hash(data)})
  end

  @doc """
  Stores an attachment under the hash of its data.
  """
  @spec store(GenServer.on_start(), term()) :: {:ok, String.t()}
  def store(cache, attachment) do
    GenServer.call(cache, {:store, hash(attachment.data), attachment})
  end

  @doc """
  Returns the number of cached attachments and cache hits.
  """
  @spec stats(GenServer.on_start()) :: %{size: non_neg_integer(), hits: non_neg_integer()}
  def stats(cache) do
    GenServer.call(cache, :stats)
  end

  @doc """
  Clears the cache.
  """
  @spec clear(GenServer.on_start()) :: :ok
  def clear(cache) do
    GenServer.call(cache, :clear)
  end

  defp hash(data) when is_binary(data),
    do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  @impl true
  def init(_opts) do
    {:ok, %{entries: %{}, hits: 0}}
  end

  @impl true
  def handle_call({:lookup, key}, _from, state) do
    case Map.get(state.entries, key) do
      nil ->
        {:reply, {:miss, key}, state}

      attachment ->
        {:reply, {:hit, attachment}, %{state | hits: state.hits + 1}}
    end
  end

  def handle_call({:store, key, attachment}, _from, state) do
    {:reply, {:ok, key}, %{state | entries: Map.put(state.entries, key, attachment)}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{size: map_size(state.entries), hits: state.hits}, state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | entries: %{}, hits: 0}}
  end
end
