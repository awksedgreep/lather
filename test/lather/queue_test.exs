defmodule Lather.QueueTest do
  use ExUnit.Case, async: false

  alias Lather.Queue

  defp cleanup(pid) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    Process.sleep(20)
  end

  test "enqueue/dequeue preserves order" do
    name = :"QueueTest-#{inspect(self())}"
    {:ok, pid} = Queue.start_link(name: name)

    Queue.enqueue(name, {"A", %{}})
    Queue.enqueue(name, {"B", %{}})

    assert Queue.size(name) == 2
    assert Queue.dequeue(name) == {"A", %{}}
    assert Queue.dequeue(name) == {"B", %{}}
    assert Queue.dequeue(name) == :empty

    cleanup(pid)
  end

  test "max_size rejects overflow" do
    name = :"QueueMaxTest-#{inspect(self())}"
    {:ok, pid} = Queue.start_link(name: name, max_size: 1)

    assert Queue.enqueue(name, {"A", %{}}) == :ok
    assert Queue.enqueue(name, {"B", %{}}) == {:error, :queue_full}

    cleanup(pid)
  end
end
