defmodule Lather.Queue do
  @moduledoc """
  Message queue integration for asynchronous SOAP processing.

  Provides an in-memory FIFO queue (a stand-in for RabbitMQ/Kafka-style
  brokers) with a worker that drains queued invocations against a
  `Lather.DynamicClient`.

  ## Examples

      iex> {:ok, pid} = Lather.Queue.start_link(name: :demo_queue)
      iex> Lather.Queue.enqueue(:demo_queue, {"Echo", %{"message" => "hi"}})
      :ok
      iex> Lather.Queue.size(:demo_queue)
      1

  """

  use GenServer

  @doc """
  Starts a queue process.

  ## Options

    * `:name` - queue process name
    * `:max_size` - optional maximum queue size (enqueue fails when full)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Enqueues `{operation, params}`. Returns `:ok` or `{:error, :queue_full}`.
  """
  @spec enqueue(GenServer.on_start(), {String.t(), map()}) :: :ok | {:error, :queue_full}
  def enqueue(queue, job) do
    GenServer.call(queue, {:enqueue, job})
  end

  @doc """
  Dequeues one job, or `:empty` when the queue is empty.
  """
  @spec dequeue(GenServer.on_start()) :: {String.t(), map()} | :empty
  def dequeue(queue) do
    GenServer.call(queue, :dequeue)
  end

  @doc """
  Number of queued jobs.
  """
  @spec size(GenServer.on_start()) :: non_neg_integer()
  def size(queue) do
    GenServer.call(queue, :size)
  end

  @doc """
  Starts a worker that drains the queue against `client`, invoking each
  job until the queue is empty. Returns the list of results.
  """
  @spec drain(GenServer.on_start(), Lather.DynamicClient.t()) :: [term()]
  def drain(queue, client) do
    drain_loop(queue, client, [])
  end

  defp drain_loop(queue, client, acc) do
    case dequeue(queue) do
      :empty ->
        acc

      {operation, params} ->
        drain_loop(queue, client, acc ++ [Lather.DynamicClient.call(client, operation, params)])
    end
  end

  @impl true
  def init(opts) do
    {:ok, %{jobs: [], max_size: Keyword.get(opts, :max_size)}}
  end

  @impl true
  def handle_call({:enqueue, job}, _from, state) do
    if state.max_size && length(state.jobs) >= state.max_size do
      {:reply, {:error, :queue_full}, state}
    else
      {:reply, :ok, %{state | jobs: state.jobs ++ [job]}}
    end
  end

  def handle_call(:dequeue, _from, state) do
    case state.jobs do
      [] ->
        {:reply, :empty, state}

      [job | rest] ->
        {:reply, job, %{state | jobs: rest}}
    end
  end

  def handle_call(:size, _from, state) do
    {:reply, length(state.jobs), state}
  end
end
