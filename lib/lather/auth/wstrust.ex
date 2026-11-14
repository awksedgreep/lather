defmodule Lather.Auth.WSTrust do
  @moduledoc """
  WS-Trust style token issuance and validation.

  A trusted issuer issues security tokens (HMAC-signed, JWT-like) that
  clients present in the WS-Security header of SOAP requests:

      <wsse:Security xmlns:wsse="...">
        <wst:Token xmlns:wst="http://schemas.xmlsoap.org/ws/2005/04/auth">eyJ...</wst:Token>
      </wsse:Security>

  ## Examples

      iex> token = Lather.Auth.WSTrust.issue_token("issuer-secret", "alice")
      iex> {:ok, claims} = Lather.Auth.WSTrust.validate_token(token, "issuer-secret")
      iex> claims["sub"]
      "alice"

  """

  alias Lather.Soap.Elements

  @wsse_namespace "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
  @wst_namespace "http://schemas.xmlsoap.org/ws/2005/04/auth"
  @default_ttl 3600

  @doc """
  Issues a security token for `subject` signed with the issuer's secret.

  ## Options

    * `:ttl` - token lifetime in seconds (default 3600)
    * `:issuer` - issuer name recorded in the token

  """
  @spec issue_token(binary(), binary(), keyword()) :: String.t()
  def issue_token(secret, subject, opts \\ []) when is_binary(secret) and is_binary(subject) do
    now = :os.system_time(:second)
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    claims =
      Map.merge(
        %{
          "sub" => subject,
          "iss" => Keyword.get(opts, :issuer, "lather-wstrust"),
          "iat" => now,
          "exp" => now + ttl
        },
        Keyword.get(opts, :claims, %{})
      )

    payload = Base.encode64(Jason.encode!(claims))
    signature = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode64()
    payload <> "." <> signature
  end

  @doc """
  Requests a token from a WS-Trust issuer endpoint.

  The endpoint is POSTed a JSON body `%{"username" => ..., "password" => ...}`
  and must respond with `%{"token" => ...}`.
  """
  @spec request_token(String.t(), binary(), binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def request_token(issuer_url, username, password, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    request =
      Finch.build(
        :post,
        issuer_url,
        [{"content-type", "application/json"}],
        Jason.encode!(%{"username" => username, "password" => password})
      )

    case Finch.request(request, Lather.Finch, receive_timeout: timeout) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"token" => token}} -> {:ok, token}
          _ -> {:error, :invalid_issuer_response}
        end

      {:ok, %Finch.Response{status: status}} ->
        {:error, {:issuer_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates a token's signature and expiry.

  Returns `{:ok, claims}` or `{:error, reason}`.
  """
  @spec validate_token(String.t(), binary()) :: {:ok, map()} | {:error, term()}
  def validate_token(token, secret) when is_binary(token) and is_binary(secret) do
    case String.split(token, ".") do
      [payload, signature] ->
        expected = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode64()

        if signature != expected do
          {:error, :invalid_signature}
        else
          case Jason.decode(Base.decode64!(payload)) do
            {:ok, claims} ->
              exp = claims["exp"]

              if is_integer(exp) and exp < :os.system_time(:second) do
                {:error, :expired}
              else
                {:ok, claims}
              end

            {:error, _} ->
              {:error, :malformed_token}
          end
        end

      _ ->
        {:error, :malformed_token}
    end
  end

  @doc """
  Builds a WS-Security header containing a WS-Trust token.
  """
  @spec security_header(String.t()) :: map()
  def security_header(token) when is_binary(token) do
    %{
      "wsse:Security" => %{
        "@xmlns:wsse" => @wsse_namespace,
        "@xmlns:wst" => @wst_namespace,
        "wst:Token" => token
      }
    }
  end

  @doc """
  Extracts a WS-Trust token from parsed SOAP headers, if present.
  """
  @spec extract(list()) :: String.t() | nil
  def extract(headers) when is_list(headers) do
    Enum.find_value(headers, fn pair ->
      {name, value} = pair

      if Elements.local_name(to_string(name)) == "Security" and is_map(value) do
        Enum.find_value(value, fn sub ->
          {sub_name, sub_value} = sub

          if Elements.local_name(to_string(sub_name)) == "Token" and is_binary(sub_value) do
            sub_value
          end
        end)
      end
    end)
  end
end
