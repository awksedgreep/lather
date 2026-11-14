defmodule Lather.Auth.APIKeyTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.APIKey

  test "header builds the x-api-key header" do
    assert APIKey.header("abc") == [{"x-api-key", "abc"}]
  end

  test "valid? accepts a list of keys" do
    assert APIKey.valid?(["a", "b"], "a")
    refute APIKey.valid?(["a", "b"], "c")
    refute APIKey.valid?(["a", "b"], nil)
    refute APIKey.valid?(["a", "b"], "")
  end

  test "valid? accepts a map of keys" do
    keys = %{"a" => [scope: "read"], "b" => [scope: "write"]}
    assert APIKey.valid?(keys, "b")
    refute APIKey.valid?(keys, "z")
    assert APIKey.metadata(keys, "a") == [scope: "read"]
  end

  test "extract finds the key in request headers" do
    assert APIKey.extract([{"x-api-key", "abc"}, {"accept", "text/xml"}]) == "abc"
    assert APIKey.extract([{"X-API-Key", "abc"}]) == "abc"
    assert APIKey.extract([]) == nil
  end
end
