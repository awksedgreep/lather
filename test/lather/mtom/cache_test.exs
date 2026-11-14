defmodule Lather.Mtom.CacheTest do
  use ExUnit.Case, async: false

  alias Lather.Mtom.{Builder, Cache}
  alias Lather.Mtom.Attachment

  setup do
    name = :"MtomCacheTest-#{inspect(self())}"
    {:ok, pid} = Cache.start_link(name: name)
    on_exit(fn -> Process.exit(pid, :kill) end)

    {:ok, name: name}
  end

  test "store and lookup by content hash", %{name: name} do
    attachment = Attachment.new("hello world", "text/plain")

    {:ok, _hash} = Cache.store(name, attachment)
    assert {:hit, stored} = Cache.lookup(name, "hello world")
    assert stored.content_type == "text/plain"

    assert {:miss, _} = Cache.lookup(name, "other content")
  end

  test "builder reuses cached attachments", %{name: name} do
    params = %{"file" => {:attachment, "same bytes", "application/octet-stream"}}

    {:ok, {_, [first]}} = Builder.process_parameters(params, name)
    {:ok, {_, [second]}} = Builder.process_parameters(params, name)

    assert first.content_id == second.content_id

    stats = Cache.stats(name)
    assert stats[:size] == 1
    assert stats[:hits] == 1
  end

  test "distinct contents are stored separately", %{name: name} do
    Builder.process_parameters(%{"a" => {:attachment, "one", "text/plain"}}, name)
    Builder.process_parameters(%{"b" => {:attachment, "two", "text/plain"}}, name)

    assert Cache.stats(name)[:size] == 2
  end
end
