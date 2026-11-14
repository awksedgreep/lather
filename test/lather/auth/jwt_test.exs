defmodule Lather.Auth.JWTTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.JWT

  test "token round trips through verify" do
    token = JWT.token(%{"sub" => "user", "role" => "admin"}, "secret")
    assert {:ok, claims} = JWT.verify(token, "secret")
    assert claims["sub"] == "user"
    assert claims["role"] == "admin"
    assert is_integer(claims["iat"])
  end

  test "wrong secret fails verification" do
    token = JWT.token(%{"sub" => "user"}, "secret")
    assert JWT.verify(token, "other") == {:error, :invalid_signature}
  end

  test "tampered claims fail verification" do
    token = JWT.token(%{"sub" => "user"}, "secret")
    [header, _payload, signature] = String.split(token, ".")
    tampered = JWT.token(%{"sub" => "evil"}, "secret")
    [_, tampered_payload, _] = String.split(tampered, ".")

    assert JWT.verify("#{header}.#{tampered_payload}.#{signature}", "secret") ==
             {:error, :invalid_signature}
  end

  test "expired tokens are rejected" do
    token = JWT.token(%{"sub" => "user", "exp" => :os.system_time(:second) - 10}, "secret")
    assert JWT.verify(token, "secret") == {:error, :expired}
  end

  test "future exp claims are accepted" do
    token = JWT.token(%{"exp" => :os.system_time(:second) + 60}, "secret")
    assert {:ok, _} = JWT.verify(token, "secret")
  end

  test "malformed tokens are rejected" do
    assert JWT.verify("abc", "secret") == {:error, :malformed_token}
    assert {:error, reason} = JWT.verify("not.a.jwt", "secret")
    assert reason in [:invalid_signature, :malformed_payload]
  end

  test "security_header wraps the token in a wsse element" do
    header = JWT.security_header("tok")
    assert header["wsse:Security"]["jwt:JWT"] == "tok"
  end

  test "extract finds the JWT in parsed headers" do
    header = JWT.security_header("tok")
    headers = [{"wsse:Security", header["wsse:Security"]}]
    assert JWT.extract(headers) == "tok"
    assert JWT.extract([]) == nil
  end
end
