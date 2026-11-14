defmodule Lather.Auth.PolicyTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.Policy

  test "valid policy passes" do
    opts = [api_keys: ["secret"], jwt_secret: "jwt"]
    policy = %{require_auth: ["api_key", "jwt"], min_factors: 2}

    assert Policy.validate(opts, policy) == :ok
  end

  test "missing required factor is a violation" do
    policy = %{require_auth: [:jwt]}

    assert {:error, [violation]} = Policy.validate([], policy)
    assert violation =~ "jwt"
  end

  test "all violations are reported" do
    opts = [max_body_size: 5_000_000]
    policy = %{require_auth: [:api_key], min_factors: 2, max_body_size: 1_000_000}

    assert {:error, violations} = Policy.validate(opts, policy)
    assert length(violations) == 3
  end

  test "require_encryption demands an encryption key" do
    policy = %{require_encryption: true}

    assert {:error, [violation]} = Policy.validate([], policy)
    assert violation =~ "encryption"

    assert Policy.validate([encryption_key: "key"], policy) == :ok
  end

  test "validate! raises on violations" do
    assert_raise ArgumentError, fn ->
      Policy.validate!([], %{require_auth: [:api_key]})
    end
  end

  test "validate! returns :ok when satisfied" do
    assert Policy.validate!([jwt_secret: "s"], %{require_auth: ["jwt"]}) == :ok
  end
end
