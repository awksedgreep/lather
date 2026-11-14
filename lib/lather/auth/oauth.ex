defmodule Lather.Auth.OAuth do
  @moduledoc """
  OAuth 2.0 client credentials flow for SOAP endpoints.

  Fetches an access token from a token endpoint and attaches it as a
  `Bearer` authorization header (or as a custom JWT header on the SOAP
  envelope via `Lather.Auth.JWT`).

  ## Examples

      {:ok, token} =
        Lather.Auth.OAuth.client_credentials_token(
          "client-id",
          "client-secret",
          "https://auth.example.com/oauth/token"
        )

      {:ok, client} =
        Lather.DynamicClient.new(wsdl_url, headers: [{"authorization", "Bearer " <> token}])
  """

  alias Lather.DynamicClient

  @default_timeout 10_000

  @doc """
  Fetches an access token using the OAuth 2.0 client credentials grant.

  ## Options

    * `:scope` - optional scope parameter
    * `:grant_type` - defaults to `"client_credentials"`
    * `:timeout` - request timeout in milliseconds (default 10,000)

  Returns `{:ok, access_token}` or `{:error, reason}`.
  """
  @spec client_credentials_token(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def client_credentials_token(client_id, client_secret, token_url, opts \\ []) do
    body =
      [
        {"grant_type", Keyword.get(opts, :grant_type, "client_credentials")},
        {"client_id", client_id},
        {"client_secret", client_secret}
      ]
      |> append_scope(opts)

    request =
      Finch.build(
        :post,
        token_url,
        [{"content-type", "application/x-www-form-urlencoded"}],
        URI.encode_query(body)
      )

    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case Finch.request(request, Lather.Finch, receive_timeout: timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, %{"access_token" => token}} -> {:ok, token}
          {:ok, _} -> {:error, :missing_access_token}
          {:error, _} -> {:error, :invalid_token_response}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_endpoint_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns request headers carrying an OAuth access token.

  ## Examples

      iex> Lather.Auth.OAuth.bearer_headers("abc123")
      [{"authorization", "Bearer abc123"}]

  """
  @spec bearer_headers(String.t()) :: [{String.t(), String.t()}]
  def bearer_headers(access_token) when is_binary(access_token) do
    [{"authorization", "Bearer #{access_token}"}]
  end

  @doc """
  Refreshes an access token using a refresh token (OAuth 2.0 refresh grant).

  Returns `{:ok, %{"access_token" => token, "refresh_token" => refresh}}` or
  `{:error, reason}`.
  """
  @spec refresh_token(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def refresh_token(client_id, client_secret, refresh_token_value, token_url) do
    body =
      URI.encode_query([
        {"grant_type", "refresh_token"},
        {"client_id", client_id},
        {"client_secret", client_secret},
        {"refresh_token", refresh_token_value}
      ])

    request =
      Finch.build(
        :post,
        token_url,
        [{"content-type", "application/x-www-form-urlencoded"}],
        body
      )

    case Finch.request(request, Lather.Finch, receive_timeout: @default_timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_endpoint_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds a dynamic client that authenticates with an OAuth 2.0 bearer token
  obtained via the client credentials grant.

  ## Examples

      {:ok, client} =
        Lather.Auth.OAuth.client_with_token(
          wsdl_url,
          "client-id",
          "client-secret",
          "https://auth.example.com/oauth/token"
        )
  """
  @spec client_with_token(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, DynamicClient.t()} | {:error, term()}
  def client_with_token(wsdl_url, client_id, client_secret, token_url, opts \\ []) do
    with {:ok, token} <- client_credentials_token(client_id, client_secret, token_url, opts) do
      Lather.DynamicClient.new(wsdl_url, headers: bearer_headers(token))
    end
  end

  defp append_scope(body, opts) do
    case Keyword.get(opts, :scope) do
      nil -> body
      scope -> body ++ [{"scope", scope}]
    end
  end
end
