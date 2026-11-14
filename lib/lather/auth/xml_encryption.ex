defmodule Lather.Auth.XMLEncryption do
  @moduledoc """
  WS-Security-style XML Encryption for SOAP bodies.

  Implements the subset of the XML Encryption spec that is practical for
  symmetric key services: AES-256-CBC with a shared secret key, wrapped in
  an `<xenc:EncryptedData>` element:

      <xenc:EncryptedData xmlns:xenc="http://www.w3.org/2001/04/xmlenc#"
                          Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc">
        <xenc:CipherText>
          <xenc:CipherValue>base64(iv || hmac || ciphertext)</xenc:CipherValue>
        </xenc:CipherText>
      </xenc:EncryptedData>

  The ciphertext carries a 16-byte HMAC (computed over the plaintext with
  the derived key) so tampering is detected before the decrypted payload is
  used.

  ## Examples

      encrypted = Lather.Auth.XMLEncryption.encrypt_data(%{"message" => "hi"}, "secret")
      {:ok, params} = Lather.Auth.XMLEncryption.decrypt(encrypted["xenc:EncryptedData"], "secret")
      params["message"]
      # "hi"

  """

  alias Lather.Soap.Elements

  @xmlenc_namespace "http://www.w3.org/2001/04/xmlenc#"
  @algorithm "http://www.w3.org/2001/04/xmlenc#aes256-cbc"

  @doc """
  Encrypts arbitrary data (a map of parameters or a binary) into an
  `xenc:EncryptedData` element map ready for a SOAP body.

  The key may be a 32-byte binary or any shared secret string; strings are
  SHA-256 hashed to derive the AES key.
  """
  @spec encrypt_data(map() | binary(), binary()) :: map()
  def encrypt_data(data, key) when is_binary(key) do
    plaintext =
      case data do
        d when is_binary(d) -> "b64:" <> Base.encode64(d)
        _ -> Jason.encode!(data)
      end

    derived = derive_key(key)
    iv = :crypto.strong_rand_bytes(16)
    ciphertext = :crypto.crypto_one_time(:aes_256_cbc, derived, iv, pad(plaintext), true)
    mac = integrity_mac(derived, plaintext)

    %{
      "xenc:EncryptedData" => %{
        "@xmlns:xenc" => @xmlenc_namespace,
        "@Algorithm" => @algorithm,
        "xenc:CipherText" => %{
          "xenc:CipherValue" => Base.encode64(iv <> mac <> ciphertext)
        }
      }
    }
  end

  @doc """
  Replace the contents of an operation's body element in a built SOAP
  envelope with an `xenc:EncryptedData` element carrying the encrypted
  parameters.
  """
  @spec encrypt_envelope(String.t(), String.t(), map() | binary(), binary()) :: String.t()
  def encrypt_envelope(envelope, operation_name, parameters, key) do
    value =
      encrypt_data(parameters, key)
      |> Map.get("xenc:EncryptedData")

    enc_xml =
      "<xenc:EncryptedData xmlns:xenc=\"#{@xmlenc_namespace}\" Algorithm=\"#{@algorithm}\">" <>
        "<xenc:CipherText><xenc:CipherValue>#{value["xenc:CipherText"]["xenc:CipherValue"]}</xenc:CipherValue>" <>
        "</xenc:CipherText></xenc:EncryptedData>"

    pattern = "<#{operation_name}((?:\\s[^>]*?)?)(?:/>|>(.*?)</#{operation_name}>)"

    case Regex.compile(pattern, "s") do
      {:ok, regex} ->
        Regex.replace(
          regex,
          envelope,
          fn _whole, attrs, _children ->
            "<#{operation_name}#{attrs}>#{enc_xml}</#{operation_name}>"
          end
        )

      _ ->
        envelope
    end
  end

  @doc """
  Decrypts an (parsed) `xenc:EncryptedData` element map.

  Returns `{:ok, decoded_data}` where decoded_data is the JSON-decoded
  payload (a map when one was encrypted), or `{:error, reason}`.
  """
  @spec decrypt(map(), binary()) :: {:ok, term()} | {:error, term()}
  def decrypt(encrypted, key) when is_binary(key) do
    derived = derive_key(key)

    with cipher_value when is_binary(cipher_value) <- find_cipher_value(encrypted),
         {:ok, raw} <- Base.decode64(cipher_value),
         <<iv::binary-16, mac::binary-16, ciphertext::binary>> <- raw,
         plaintext when is_binary(plaintext) <-
           unpad(:crypto.crypto_one_time(:aes_256_cbc, derived, iv, ciphertext, false)),
         true <- integrity_mac(derived, plaintext) == mac do
      case plaintext do
        "b64:" <> encoded ->
          case Base.decode64(encoded) do
            {:ok, decoded} -> {:ok, decoded}
            :error -> {:error, :decryption_failed}
          end

        _ ->
          Jason.decode(plaintext)
      end
    else
      _ -> {:error, :decryption_failed}
    end
  end

  @doc """
  True when an (parsed) SOAP body content is an XML-encrypted payload.
  """
  @spec encrypted?(map()) :: boolean()
  def encrypted?(content) when is_map(content) do
    Enum.any?(content, fn {key, _} -> Elements.local_name(to_string(key)) == "EncryptedData" end)
  end

  def encrypted?(_content), do: false

  defp derive_key(key) do
    if byte_size(key) == 32 do
      key
    else
      :crypto.hash(:sha256, key)
    end
  end

  defp integrity_mac(derived, plaintext) do
    :crypto.mac(:hmac, :sha256, derived, plaintext) |> binary_part(0, 16)
  end

  defp pad(data) do
    pad_len = 16 - rem(byte_size(data), 16)
    data <> :binary.copy(<<pad_len>>, pad_len)
  end

  defp unpad(padded) do
    pad_len = :binary.last(padded)

    if pad_len >= 1 and pad_len <= 16 and byte_size(padded) >= pad_len do
      tail_start = byte_size(padded) - pad_len
      expected_tail = :binary.copy(<<pad_len>>, pad_len)

      if binary_part(padded, tail_start, pad_len) == expected_tail do
        binary_part(padded, 0, tail_start)
      else
        nil
      end
    else
      nil
    end
  end

  defp find_cipher_value(value) when is_map(value) do
    Enum.find_value(value, fn {key, child} ->
      if Elements.local_name(to_string(key)) == "CipherValue" and is_binary(child) do
        child
      else
        find_cipher_value(child)
      end
    end)
  end

  defp find_cipher_value(_), do: nil
end
