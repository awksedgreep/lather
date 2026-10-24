defmodule Lather.Http.SSLPoolManager do
  @moduledoc """
  Bounds the number of distinct Finch pools created for custom `:ssl_options`.

  `Lather.Http.Transport.post/3` tags each request with
  `{:lather_ssl, hash(ssl_opts)}` and starts a dedicated Finch pool on
  first use. Without a bound, callers that generate `ssl_options`
  dynamically (per-request certs, timestamps, changing versions) would
  create an unbounded number of permanent pool processes, exhausting
  memory and file descriptors.

  This registry tracks `{origin, ssl_hash}` keys in ETS and refuses to
  start new pools once `max_ssl_pools` is reached (default `50`,
  configurable via `Application.put_env(:lather, :max_ssl_pools, n)`).
  When the limit is hit, `claim/2` returns
  `{:error, :pool_limit_exceeded}` and the transport layer surfaces a
  `:ssl_pool_limit_exceeded` transport error instead of starting a pool.

  Callers should reuse stable `ssl_options` (e.g. via
  `Lather.Http.Transport.ssl_options/1`) so distinct configurations map
  to a small set of pools. Options are canonicalized (keyword order
  normalized) before hashing so equivalent configurations share a pool.

  The registry is a `GenServer` owned by a supervised process started from
  `Lather.Application`. Serializing all mutations through that single
  process removes the check-then-insert race that would otherwise let the
  limit be exceeded under concurrent requests, and keeps the ETS table
  alive for the lifetime of the application.
  """

  use GenServer

  @default_max 50

  @doc """
  Starts the registry process. Invoked by `Lather.Application`.
  """
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Maximum number of distinct SSL pools allowed.

  Reads `Application.get_env(:lather, :max_ssl_pools, 50)`.
  """
  @spec max_pools() :: pos_integer()
  def max_pools do
    Application.get_env(:lather, :max_ssl_pools, @default_max)
  end

  @doc """
  Returns the canonical pool tag for the given `ssl_options`.

  Options are normalized (keyword order sorted recursively) before
  hashing so equivalent configurations share a pool.
  """
  @spec pool_tag(keyword()) :: {:lather_ssl, non_neg_integer()}
  def pool_tag(ssl_opts) do
    {:lather_ssl, :erlang.phash2(:erlang.term_to_binary(normalize(ssl_opts)))}
  end

  @doc """
  Normalizes `ssl_options` into a canonical form for hashing.

  Keyword lists are sorted by key (recursively); other terms pass
  through unchanged.
  """
  @spec normalize(keyword()) :: keyword()
  def normalize(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> Enum.map(fn {k, v} -> {k, normalize_value(v)} end)
      |> Enum.sort_by(fn {k, _} -> k end)
    else
      Enum.map(opts, &normalize_value/1)
    end
  end

  def normalize(other), do: other

  @doc """
  Claims a pool slot for `{url, ssl_opts}`.

  Returns `:ok` if the pool was already registered or a new slot was
  available, or `{:error, :pool_limit_exceeded}` when the registry is at
  capacity.
  """
  @spec claim(String.t(), keyword()) :: :ok | {:error, :pool_limit_exceeded}
  def claim(url, ssl_opts) do
    GenServer.call(__MODULE__, {:claim, url, ssl_opts})
  end

  @doc """
  Returns the number of registered SSL pools.
  """
  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Releases a previously claimed pool slot (e.g. when pool startup fails).

  Slots for successfully started pools are intentionally retained for the
  lifetime of the VM: Finch pools are permanent processes, so forgetting
  them would re-open the proliferation vector.
  """
  @spec release(String.t(), keyword()) :: :ok
  def release(url, ssl_opts) do
    GenServer.call(__MODULE__, {:release, url, ssl_opts})
  end

  @doc """
  Clears the registry. Intended for tests.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(:ok) do
    table = :ets.new(:lather_ssl_pool_registry, [:named_table, :public, :set, read_concurrency: true])
    {:ok, table}
  end

  @impl true
  def handle_call({:claim, url, ssl_opts}, _from, table) do
    key = key(url, ssl_opts)

    result =
      if :ets.member(table, key) do
        :ok
      else
        max = max_pools()
        size = :ets.info(table, :size)

        if is_integer(size) and size >= max do
          {:error, :pool_limit_exceeded}
        else
          :ets.insert(table, {key, true})
          :ok
        end
      end

    {:reply, result, table}
  end

  def handle_call(:count, _from, table) do
    {:reply, :ets.info(table, :size), table}
  end

  def handle_call({:release, url, ssl_opts}, _from, table) do
    :ets.delete(table, key(url, ssl_opts))
    {:reply, :ok, table}
  end

  def handle_call(:reset, _from, table) do
    :ets.delete_all_objects(table)
    {:reply, :ok, table}
  end

  defp key(url, ssl_opts) do
    {:lather_ssl, _hash} = pool_tag(ssl_opts)
    {origin(url), :erlang.phash2(:erlang.term_to_binary(normalize(ssl_opts)))}
  end

  defp origin(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port}
      when is_binary(scheme) and is_binary(host) ->
        "#{scheme}://#{host}:#{port}"

      _ ->
        url
    end
  end

  defp normalize_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      normalize(value)
    else
      Enum.map(value, &normalize_value/1)
    end
  end

  defp normalize_value({k, v}), do: {k, normalize_value(v)}
  defp normalize_value(value), do: value
end
