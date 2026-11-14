defmodule Lather.Auth.XMLEncryptionTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.XMLEncryption

  test "encrypt/decrypt round trips a parameter map" do
    encrypted = XMLEncryption.encrypt_data(%{"message" => "hello", "count" => 3}, "secret")

    assert {:ok, decoded} =
             XMLEncryption.decrypt(encrypted["xenc:EncryptedData"], "secret")

    assert decoded == %{"message" => "hello", "count" => 3}
  end

  test "wrong key fails decryption" do
    encrypted = XMLEncryption.encrypt_data(%{"a" => "b"}, "secret")

    assert XMLEncryption.decrypt(encrypted["xenc:EncryptedData"], "other") ==
             {:error, :decryption_failed}
  end

  test "tampered cipher value fails decryption" do
    import Bitwise

    encrypted = XMLEncryption.encrypt_data(%{"a" => "b"}, "secret")
    cipher_value = encrypted["xenc:EncryptedData"]["xenc:CipherText"]["xenc:CipherValue"]

    raw = Base.decode64!(cipher_value)
    <<first::8, rest::binary>> = raw
    tampered = Base.encode64(<<bxor(first, 1), rest::binary>>)

    tampered_encrypted =
      put_in(
        encrypted["xenc:EncryptedData"]["xenc:CipherText"]["xenc:CipherValue"],
        tampered
      )

    assert XMLEncryption.decrypt(tampered_encrypted, "secret") == {:error, :decryption_failed}
  end

  test "binary plaintext round trips" do
    data = :crypto.strong_rand_bytes(1000)
    encrypted = XMLEncryption.encrypt_data(data, "secret")
    assert {:ok, ^data} = XMLEncryption.decrypt(encrypted["xenc:EncryptedData"], "secret")
  end

  test "32-byte raw keys are used directly" do
    key = :crypto.strong_rand_bytes(32)
    encrypted = XMLEncryption.encrypt_data(%{"x" => 1}, key)
    assert {:ok, %{"x" => 1}} = XMLEncryption.decrypt(encrypted["xenc:EncryptedData"], key)
  end

  test "encrypted? detects EncryptedData elements" do
    encrypted = XMLEncryption.encrypt_data(%{"a" => 1}, "k")
    assert XMLEncryption.encrypted?(encrypted)
    refute XMLEncryption.encrypted?(%{"message" => "plain"})
  end

  test "cipher structure follows the xmlenc shape" do
    encrypted = XMLEncryption.encrypt_data(%{"a" => 1}, "k")
    data = encrypted["xenc:EncryptedData"]

    assert data["@Algorithm"] == "http://www.w3.org/2001/04/xmlenc#aes256-cbc"
    assert is_binary(data["xenc:CipherText"]["xenc:CipherValue"])
  end
end
