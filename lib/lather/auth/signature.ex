defmodule Lather.Auth.Signature do
  @moduledoc """
  WS-Security-style digital signatures for SOAP requests.

  Produces a `wsse:Security` header containing a `wsse:Signature` element
  with a SHA-256 digest of the canonicalized operation and parameters,
  and an HMAC-SHA256 signature of that digest. The server side can verify
  incoming requests against a shared secret with the `:verify_signature`
  option of `Lather.Server.EnhancedPlug.init/1`.

  ## Client

      {:ok, client} =
        Lather.DynamicClient.new("http://localhost:4000/soap?wsdl",
          authentication: {:signature, "shared-secret"})

  ## Server

      plug Lather.Server.EnhancedPlug,
        service: MyApp.UserService,
        verify_signature: "shared-secret"

  ## Notes

  Canonicalization is a deterministic key-sorted rendering of the
  operation name and parameter map, not full XML C14N. It is stable for
  requests built and verified by Lather itself.

  ## Examples

      header = Lather.Auth.Signature.sign_header("Echo", %{"message" => "hi"}, "secret")
      :ok = Lather.Auth.Signature.verify([{"Security", header["wsse:Security"]}], "Echo", %{"message" => "hi"}, "secret")
  """

  alias Lather.Soap.Elements

  @wsse_namespace "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"

  @doc """
  Builds a WS-Security header map containing the signature for the given
  operation and parameters.
  """
  @spec sign_header(String.t(), map(), binary()) :: map()
  def sign_header(operation_name, parameters, key) when is_binary(key) do
    canonical = canonicalize(operation_name, parameters)
    digest = Base.encode64(:crypto.hash(:sha256, canonical))
    signature = Base.encode64(:crypto.mac(:hmac, :sha256, key, digest))

    %{
      "wsse:Security" => %{
        "@xmlns:wsse" => @wsse_namespace,
        "wsse:Signature" => %{
          "@Algorithm" => "HMAC-SHA256",
          "DigestValue" => digest,
          "SignatureValue" => signature
        }
      }
    }
  end

  @doc """
  Verifies a signature against the operation and parameters.

  Accepts either the parsed header list from `Lather.Server.RequestParser`
  (`[{name, content}, ...]`) or a single Security header map.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec verify(list() | map(), String.t(), map(), binary()) :: :ok | {:error, term()}
  def verify(headers, operation_name, parameters, key) when is_binary(key) do
    case find_signature(normalize_headers(headers)) do
      nil ->
        {:error, :missing_signature}

      signature ->
        canonical = canonicalize(operation_name, parameters)
        digest = Base.encode64(:crypto.hash(:sha256, canonical))
        expected = Base.encode64(:crypto.mac(:hmac, :sha256, key, digest))

        cond do
          signature["DigestValue"] != digest -> {:error, :digest_mismatch}
          signature["SignatureValue"] != expected -> {:error, :invalid_signature}
          true -> :ok
        end
    end
  end

  @doc """
  Deterministic canonical form of an operation and its parameters: the
  operation name followed by key-sorted `key=value` pairs. Nested maps and
  lists are rendered recursively; atoms become their string form.
  """
  @spec canonicalize(String.t(), map()) :: String.t()
  def canonicalize(operation_name, parameters) do
    pairs =
      parameters
      |> Enum.sort_by(&to_string(elem(&1, 0)))
      |> Enum.map(&"#{elem(&1, 0)}=#{canonical_value(elem(&1, 1))}")

    "#{operation_name}|" <> Enum.join(pairs, ";")
  end

  defp canonical_value(value) when is_binary(value), do: value
  defp canonical_value(value) when is_number(value), do: to_string(value)
  defp canonical_value(value) when is_atom(value), do: to_string(value)

  defp canonical_value(value) when is_map(value) do
    value
    |> Enum.sort_by(&to_string(elem(&1, 0)))
    |> Enum.map(&"#{elem(&1, 0)}=#{canonical_value(elem(&1, 1))}")
    |> Enum.join(",")
  end

  defp canonical_value(value) when is_list(value) do
    Enum.map_join(value, ",", &canonical_value/1)
  end

  defp canonical_value(value), do: inspect(value)

  defp normalize_headers(%{} = map) do
    for pair <- map, do: {elem(pair, 0), elem(pair, 1)}
  end

  defp normalize_headers(headers) when is_list(headers), do: headers

  defp find_signature(headers) do
    security =
      Enum.find_value(headers, fn pair ->
        name = elem(pair, 0)

        if Elements.local_name(to_string(name)) == "Security" do
          elem(pair, 1)
        end
      end)

    if is_map(security) do
      signature =
        Enum.find_value(security, fn pair ->
          if Elements.local_name(elem(pair, 0)) == "Signature", do: elem(pair, 1)
        end)

      if is_map(signature), do: signature, else: nil
    else
      nil
    end
  end
end
