defmodule Lather.Auth.JWT do
  @moduledoc """
  Minimal JWT (HS256) support for SOAP headers, no external dependencies.

  Tokens are placed in a SOAP header:

      <wsse:Security xmlns:wsse="...">
        <jwt:JWT xmlns:jwt="urn:ietf:params:oauth:jwt">eyJ...</jwt:JWT>
      </wsse:Security>

  ## Examples

      iex> token = Lather.Auth.JWT.token(%{"sub" => "user"}, "secret")
      iex> {:ok, claims} = Lather.Auth.JWT.verify(token, "secret")
      iex> claims["sub"]
      "user"

  """

  alias Lather.Soap.Elements

  @jwt_namespace "urn:ietf:params:oauth:jwt"
  @wsse_namespace "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"

  @doc """
  Creates a signed JWT (HS256) from the given claims.

  Claims may include `exp` (Unix seconds); `iat` is added automatically.
  """
  @spec token(map(), binary()) :: String.t()
  def token(claims, secret) when is_map(claims) and is_binary(secret) do
    claims = Map.put(claims, "iat", :os.system_time(:second))
    header = Jason.encode!(%{"alg" => "HS256", "typ" => "JWT"})
    payload = Jason.encode!(claims)
    signing_input = url64(header) <> "." <> url64(payload)
    signature = :crypto.mac(:hmac, :sha256, secret, signing_input) |> url64
    signing_input <> "." <> signature
  end

  @doc """
  Verifies a JWT's signature and `exp` claim.

  Returns `{:ok, claims}` or `{:error, reason}`.
  """
  @spec verify(String.t(), binary()) :: {:ok, map()} | {:error, term()}
  def verify(token, secret) when is_binary(token) and is_binary(secret) do
    case String.split(token, ".") do
      [header, payload, signature] ->
        expected = :crypto.mac(:hmac, :sha256, secret, header <> "." <> payload) |> url64

        if signature != expected do
          {:error, :invalid_signature}
        else
          decoded =
            with(
              {:ok, json} <- Base.decode64(url64_to_std(payload)),
              {:ok, claims} <- Jason.decode(json)
            ) do
              claims
            end

          cond do
            is_map(decoded) ->
              if expired?(decoded), do: {:error, :expired}, else: {:ok, decoded}

            true ->
              {:error, :malformed_payload}
          end
        end

      _ ->
        {:error, :malformed_token}
    end
  end

  @doc """
  Builds a SOAP header carrying the JWT inside a WS-Security element.

  ## Examples

      iex> header = Lather.Auth.JWT.security_header("abc")
      iex> header["wsse:Security"]["jwt:JWT"]
      "abc"

  """
  @spec security_header(String.t()) :: map()
  def security_header(token) when is_binary(token) do
    %{
      "wsse:Security" => %{
        "@xmlns:wsse" => @wsse_namespace,
        "@xmlns:jwt" => @jwt_namespace,
        "jwt:JWT" => token
      }
    }
  end

  @doc """
  Extracts a JWT from parsed SOAP headers, if present.
  """
  @spec extract(list()) :: String.t() | nil
  def extract(headers) when is_list(headers) do
    Enum.find_value(headers, fn pair ->
      {name, value} = pair

      if Elements.local_name(to_string(name)) == "Security" and is_map(value) do
        Enum.find_value(value, fn sub ->
          {sub_name, sub_value} = sub

          if Elements.local_name(to_string(sub_name)) == "JWT" do
            cond do
              is_binary(sub_value) -> sub_value
              is_map(sub_value) -> Map.get(sub_value, "#text") || Map.get(sub_value, "token")
              true -> nil
            end
          end
        end)
      end
    end)
  end

  defp url64(data) do
    data
    |> Base.encode64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.trim_trailing("=")
  end

  defp url64_to_std(value) do
    padded =
      case rem(String.length(value), 4) do
        0 -> value
        n -> value <> String.duplicate("=", 4 - n)
      end

    padded
    |> String.replace("-", "+")
    |> String.replace("_", "/")
  end

  defp expired?(claims) do
    case Map.get(claims, "exp") do
      exp when is_integer(exp) -> exp < :os.system_time(:second)
      _ -> false
    end
  end
end
