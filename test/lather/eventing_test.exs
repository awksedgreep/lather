defmodule Lather.EventingTest do
  use ExUnit.Case, async: false

  alias Lather.Eventing

  setup do
    name = :"EventingTest-#{inspect(self())}"
    {:ok, pid} = Eventing.start_link(name: name)
    on_exit(fn -> Process.exit(pid, :kill) end)

    {:ok, name: name}
  end

  test "subscribe/publish/poll round trip", %{name: name} do
    {:ok, sub} = Eventing.subscribe("orders", name: name)

    {:ok, count} = Eventing.publish("orders", "order-1", name: name)
    assert count == 1

    {:ok, envelopes} = Eventing.poll(sub, name: name)
    assert length(envelopes) == 1
    assert hd(envelopes) =~ "order-1"
  end

  test "poll drains the queue", %{name: name} do
    {:ok, sub} = Eventing.subscribe("orders", name: name)
    Eventing.publish("orders", "a", name: name)
    Eventing.publish("orders", "b", name: name)

    {:ok, envelopes} = Eventing.poll(sub, name: name)
    assert length(envelopes) == 2

    {:ok, drained} = Eventing.poll(sub, name: name)
    assert drained == []
  end

  test "publishing to an unsubscribed channel notifies nobody", %{name: name} do
    Eventing.subscribe("orders", name: name)
    {:ok, count} = Eventing.publish("other", "x", name: name)
    assert count == 0
  end

  test "unknown subscription poll errors", %{name: name} do
    assert Eventing.poll("nope", name: name) == {:error, :unknown_subscription}
  end
end
