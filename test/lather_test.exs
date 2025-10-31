defmodule LatherTest do
  use ExUnit.Case
  doctest Lather

  test "returns version" do
    version = Lather.version()
    assert is_binary(version)
    assert version != ""
  end
end
