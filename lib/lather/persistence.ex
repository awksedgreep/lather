defmodule Lather.Persistence do
  @moduledoc """
  Request/response persistence for Lather services.

  Stores SOAP call history in an in-memory GenServer with optional
  JSON-lines file backing (a stand-in for a database; swap the
  `writer`/`reader` functions for a real DB adapter).

  ## Examples

      iex> {:ok, pid} = Lather.Persistence.start_link(name: :demo_store)
      iex> Lather.Persistence.record(:demo_store, "Echo", %{"message" => "hi"}, %{"echo" => "hi"})
      iex> length(Lather.Persistence.history(:demo_store))
      1

  """

  use GenServer

  @doc """
  Starts a persistence store.

  ## Options

    * `:name` - process name (default: `Lather.Persistence`)
    * `:file` - optional JSON-lines file to append records to
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records a request/response pair.
  """
  @spec record(GenServer.on_start(), String.t(), map(), map()) :: {:ok, String.t()}
  def record(store, operation, params, response) do
    GenServer.call(store, {:record, operation, params, response})
  end

  @doc """
  Returns the most recent history entries.
  """
  @spec history(GenServer.on_start(), non_neg_integer()) :: [map()]
  def history(store, limit \\ 50) do
    GenServer.call(store, {:history, limit})
  end

  @doc """
  Returns the number of stored records.
  """
  @spec count(GenServer.on_start()) :: non_neg_integer()
  def count(store) do
    GenServer.call(store, :count)
  end

  @impl true
  def init(opts) do
    file = Keyword.get(opts, :file)

    initial =
      case file do
        nil ->
          []

        path ->
          case File.read(path) do
            {:ok, contents} ->
              contents
              |> String.split("\n", trim: true)
              |> Enum.map(&decode_line/1)
              |> Enum.reject(&is_nil/1)

            {:error, _reason} ->
              []
          end
      end

    {:ok, %{records: initial, file: file, counter: length(initial)}}
  end

  @impl true
  def handle_call({:record, operation, params, response}, _from, state) do
    id = "req-#{state.counter}"

    record = %{
      id: id,
      timestamp: DateTime.utc_now(),
      operation: operation,
      params: params,
      response: response
    }

    if state.file do
      File.write(state.file, encode_line(record) <> "\n", append: true)
    end

    {:reply, {:ok, id}, %{state | records: state.records ++ [record], counter: state.counter + 1}}
  end

  def handle_call({:history, limit}, _from, state) do
    {:reply, Enum.take(state.records, -limit), state}
  end

  def handle_call(:count, _from, state) do
    {:reply, length(state.records), state}
  end

  defp encode_line(record) do
    Jason.encode!(record)
  rescue
    _ -> inspect(record)
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> nil
    end
  rescue
    _ -> nil
  end
end
