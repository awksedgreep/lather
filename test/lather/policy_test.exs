defmodule Lather.PolicyTest do
  use ExUnit.Case, async: true

  alias Lather.Policy

  test "build and parse round-trip" do
    policy = %{
      "require_auth" => ["api_key"],
      "max_message_size" => 1_048_576,
      "operations" => ["Echo", "Ping"]
    }

    xml = Policy.build_policy_xml(policy)
    {:ok, parsed} = Policy.parse_policy(xml)

    assert parsed["require_auth"] == "api_key"
    assert parsed["max_message_size"] == 1_048_576
    assert parsed["operations"] == ["Echo", "Ping"]
  end

  test "validate reports missing auth factor" do
    policy = %{"require_auth" => ["api_key"]}

    assert Policy.validate([], policy) == {:error, ["policy requires api_key authentication"]}
    assert Policy.validate([authentication: {:api_key, "k"}], policy) == :ok
    assert match?({:error, _}, Policy.validate([authentication: {:jwt, "s"}], policy))
  end
end
