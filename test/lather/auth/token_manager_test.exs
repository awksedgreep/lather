defmodule Lather.Auth.TokenManagerTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.{JWT, TokenManager}

  setup do
    name = String.to_atom("tm_#{:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)}")
    {:ok, manager} = TokenManager.start_link(name: name, secret: "s3cret", ttl: 60)
    {:ok, manager: manager}
  end

  test "issued tokens validate", %{manager: manager} do
    token = TokenManager.issue(manager, %{"sub" => "alice", "role" => "admin"})

    assert {:ok, claims} = TokenManager.validate(manager, token)
    assert claims["sub"] == "alice"
    assert claims["role"] == "admin"
    assert is_integer(claims["exp"])
    assert is_binary(claims["jti"])
  end

  test "tokens from another secret are rejected", %{manager: manager} do
    foreign = JWT.token(%{"sub" => "eve", "exp" => :os.system_time(:second) + 60}, "other-secret")
    assert TokenManager.validate(manager, foreign) == {:error, :invalid_signature}
  end

  test "refreshing issues a new token and revokes the old one", %{manager: manager} do
    token = TokenManager.issue(manager, %{"sub" => "alice"})
    {:ok, refreshed} = TokenManager.refresh(manager, token)

    assert TokenManager.validate(manager, token) == {:error, :revoked}
    assert {:ok, claims} = TokenManager.validate(manager, refreshed)
    assert claims["sub"] == "alice"
    assert TokenManager.revoked_count(manager) == 1
  end

  test "expired tokens cannot be refreshed without grace", %{manager: manager} do
    expired =
      JWT.token(
        %{"sub" => "alice", "jti" => "old-jti", "exp" => :os.system_time(:second) - 10},
        "s3cret"
      )

    assert TokenManager.refresh(manager, expired) == {:error, :expired}
  end

  test "expired tokens can be refreshed within the grace window" do
    name =
      String.to_atom("tm_grace_#{:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)}")

    {:ok, manager} =
      TokenManager.start_link(name: name, secret: "s3cret", ttl: 60, refresh_grace: 300)

    expired =
      JWT.token(
        %{"sub" => "alice", "jti" => "jti-1", "exp" => :os.system_time(:second) - 30},
        "s3cret"
      )

    assert {:ok, refreshed} = TokenManager.refresh(manager, expired)
    assert {:ok, claims} = TokenManager.validate(manager, refreshed)
    assert claims["sub"] == "alice"
  end

  test "manual revocation blocks validation", %{manager: manager} do
    token = TokenManager.issue(manager, %{"sub" => "bob"})
    assert :ok = TokenManager.revoke(manager, token)
    assert TokenManager.validate(manager, token) == {:error, :revoked}
  end

  test "expired tokens fail validation", %{manager: manager} do
    expired = JWT.token(%{"sub" => "bob", "exp" => :os.system_time(:second) - 5}, "s3cret")
    assert TokenManager.validate(manager, expired) == {:error, :expired}
  end
end
