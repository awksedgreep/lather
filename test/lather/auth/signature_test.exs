defmodule Lather.Auth.SignatureTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.Signature

  test "sign_header produces a WS-Security signature structure" do
    header = Signature.sign_header("Echo", %{"message" => "hello"}, "secret")
    security = header["wsse:Security"]

    assert security["wsse:Signature"]["DigestValue"]
    assert security["wsse:Signature"]["SignatureValue"]
    assert security["wsse:Signature"]["@Algorithm"] == "HMAC-SHA256"
  end

  test "verify accepts a correctly signed request" do
    header = Signature.sign_header("Echo", %{"message" => "hello"}, "secret")
    headers = [{"wsse:Security", header["wsse:Security"]}]

    assert Signature.verify(headers, "Echo", %{"message" => "hello"}, "secret") == :ok
  end

  test "verify rejects a tampered parameter" do
    header = Signature.sign_header("Echo", %{"message" => "hello"}, "secret")
    headers = [{"wsse:Security", header["wsse:Security"]}]

    assert Signature.verify(headers, "Echo", %{"message" => "evil"}, "secret") ==
             {:error, :digest_mismatch}
  end

  test "verify rejects the wrong key" do
    header = Signature.sign_header("Echo", %{"message" => "hello"}, "secret")
    headers = [{"wsse:Security", header["wsse:Security"]}]

    assert Signature.verify(headers, "Echo", %{"message" => "hello"}, "other-secret") ==
             {:error, :invalid_signature}
  end

  test "verify reports missing signatures" do
    assert Signature.verify([], "Echo", %{"message" => "hello"}, "secret") ==
             {:error, :missing_signature}
  end

  test "canonicalization is order independent" do
    a = Signature.canonicalize("Op", %{"b" => "2", "a" => "1"})
    b = Signature.canonicalize("Op", %{"a" => "1", "b" => "2"})

    assert a == b
    assert a == "Op|a=1;b=2"
  end

  test "nested structures canonicalize deterministically" do
    canonical = Signature.canonicalize("Op", %{"user" => %{"name" => "Bob", "id" => 7}})
    assert canonical == "Op|user=id=7,name=Bob"
  end
end
