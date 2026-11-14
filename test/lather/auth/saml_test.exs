defmodule Lather.Auth.SAMLTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.SAML

  test "assertion produces a signed structure" do
    assertion = SAML.assertion("alice", secret: "s3cret", attributes: %{"role" => "admin"})
    signature = assertion["saml:Assertion"]["saml:Signature"]
    assert is_binary(signature["#text"])
    assert signature["@Algorithm"] == "HMAC-SHA256"
  end

  test "verify round trips claims" do
    assertion = SAML.assertion("alice", secret: "s3cret", attributes: %{"role" => "admin"})

    assert {:ok, claims} = SAML.verify(assertion["saml:Assertion"], "s3cret")
    assert claims["subject"] == "alice"
    assert claims["issuer"] == "lather"
    assert claims["attributes"]["role"] == "admin"
  end

  test "tampered assertions fail verification" do
    assertion = SAML.assertion("alice", secret: "s3cret", attributes: %{"role" => "admin"})
    tampered = put_in(assertion["saml:Assertion"]["saml:Attribute"]["@Value"], "superuser")

    assert SAML.verify(tampered["saml:Assertion"], "s3cret") == {:error, :invalid_signature}
  end

  test "wrong secret fails verification" do
    assertion = SAML.assertion("alice", secret: "s3cret")
    assert SAML.verify(assertion["saml:Assertion"], "other") == {:error, :invalid_signature}
  end

  test "expired assertions are rejected" do
    assertion = SAML.assertion("alice", secret: "s3cret", ttl: -60)
    assert SAML.verify(assertion["saml:Assertion"], "s3cret") == {:error, :expired}
  end

  test "assertion without signature fails" do
    assertion = SAML.assertion("alice", secret: "s3cret")
    unsigned = Map.delete(assertion["saml:Assertion"], "saml:Signature")
    assert SAML.verify(unsigned, "s3cret") == {:error, :missing_signature}
  end

  test "extract finds assertion inside a security header" do
    header = SAML.security_header(SAML.assertion("alice", secret: "s3cret"))
    headers = [{"wsse:Security", header["wsse:Security"]}]

    extracted = SAML.extract(headers)
    assert is_map(extracted)
    assert extracted["saml:Issuer"] == "lather"
    assert SAML.extract([]) == nil
  end

  test "security_header wraps the assertion in wsse:Security" do
    header = SAML.security_header(SAML.assertion("a", secret: "k"))
    assert header["wsse:Security"]["saml:Assertion"]["@Version"] == "2.0"
  end
end
