defmodule Lather.PersistenceTest do
  use ExUnit.Case, async: false

  alias Lather.Persistence

  defp cleanup(pid) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    Process.sleep(20)
  end

  test "records and retrieves history" do
    name = :"PersistenceTest-#{inspect(self())}"
    {:ok, pid} = Persistence.start_link(name: name)

    {:ok, id} = Persistence.record(name, "Echo", %{"message" => "hi"}, %{"echo" => "hi"})

    assert id == "req-0"
    assert Persistence.count(name) == 1

    [record] = Persistence.history(name)
    assert record[:operation] == "Echo"
    assert record[:params] == %{"message" => "hi"}

    cleanup(pid)
  end

  test "file-backed store persists across restarts" do
    name = :"PersistenceFileTest-#{inspect(self())}"
    path = "/tmp/lather_persistence_#{name}.jsonl"
    File.write(path, "")

    {:ok, pid1} = Persistence.start_link(name: name, file: path)
    Persistence.record(name, "Ping", %{}, %{"pong" => "pong"})
    cleanup(pid1)

    {:ok, pid2} = Persistence.start_link(name: name, file: path)

    history = Persistence.history(name)
    assert length(history) == 1
    assert hd(history)["operation"] == "Ping"

    cleanup(pid2)
  end
end
