defmodule Lather.Auth.WSTrustTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.WSTrust

  test "issue and validate a token" do
    token = WSTrust.issue_token("issuer-secret", "alice")
    {:ok, claims} = WSTrust.validate_token(token, "issuer-secret")

    assert claims["sub"] == "alice"
    assert claims["iss"] == "lather-wstrust"
    assert claims["exp"] > claims["iat"]
  end

  test "wrong secret fails validation" do
    token = WSTrust.issue_token("issuer-secret", "alice")

    assert {:error, :invalid_signature} = WSTrust.validate_token(token, "wrong-secret")
  end

  test "expired tokens are rejected" do
    token = WSTrust.issue_token("secret", "bob", ttl: -10)

    assert {:error, :expired} = WSTrust.validate_token(token, "secret")
  end

  test "malformed tokens are rejected" do
    assert {:error, :malformed_token} = WSTrust.validate_token("not-a-token", "secret")
  end

  test "security_header and extract round-trip" do
    header = WSTrust.security_header("token123")
    assert header["wsse:Security"]["wst:Token"] == "token123"

    extracted = WSTrust.extract([{"wsse:Security", header["wsse:Security"]}])
    assert extracted == "token123"
  end

  test "extract returns nil when no token present" do
    assert WSTrust.extract([]) == nil
  end
end
