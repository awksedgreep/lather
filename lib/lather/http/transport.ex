defmodule Lather.Http.Transport do
  @moduledoc """
  HTTP transport layer for SOAP requests.

  Handles HTTP/HTTPS communication using Finch for connection pooling
  and efficient request handling.
  """

  require Logger
  alias Lather.Auth.Basic
  alias Lather.Error

  @default_headers [
    {"content-type", "text/xml; charset=utf-8"},
    {"accept", "text/xml"},
    {"soapaction", ""}
  ]

  @default_timeout 30_000

  @doc """
  Sends a POST request with the SOAP envelope to the specified endpoint.

  ## Parameters

  * `url` - The SOAP endpoint URL
  * `body` - The SOAP envelope XML as a string
  * `options` - Request options

  ## Options

  * `:timeout` - Request timeout in milliseconds
  * `:headers` - Additional headers to include
  * `:soap_action` - SOAPAction header value
  * `:ssl_options` - SSL/TLS options for HTTPS connections
  * `:pool_timeout` - Connection pool timeout in milliseconds
  * `:basic_auth` - Basic authentication credentials `{username, password}`

  ## Examples

      # Example usage (would make actual HTTP request):
      # Transport.post("https://example.com/soap", "<soap>...</soap>", [])
      # {:ok, %{status: 200, body: "<response>...</response>"}}

      # With Basic authentication:
      # Transport.post(url, body, basic_auth: {"user", "pass"})

  """
  @spec post(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def post(url, body, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    pool_timeout = Keyword.get(options, :pool_timeout, 5_000)
    headers = build_headers(options)

    Logger.debug("Sending SOAP request to #{url}")

    request = Finch.build(:post, url, headers, body)

    finch_options = [
      receive_timeout: timeout,
      pool_timeout: pool_timeout
    ]

    # Add SSL options if provided
    finch_options =
      case Keyword.get(options, :ssl_options) do
        nil -> finch_options
        ssl_opts -> Keyword.put(finch_options, :ssl, ssl_opts)
      end

    case Finch.request(request, Lather.Finch, finch_options) do
      {:ok, %Finch.Response{} = response} ->
        handle_response(response)

      {:error, %Mint.TransportError{reason: reason}} ->
        Logger.error("SOAP transport error: #{inspect(reason)}")

        error =
          Error.transport_error(reason, %{
            message: "Transport error: #{inspect(reason)}"
          })

        {:error, error}

      {:error, %Mint.HTTPError{reason: reason}} ->
        Logger.error("SOAP HTTP error: #{inspect(reason)}")

        error =
          Error.transport_error(reason, %{
            message: "HTTP error: #{inspect(reason)}"
          })

        {:error, error}

      {:error, %Finch.Error{reason: reason}} ->
        Logger.error("SOAP Finch error: #{inspect(reason)}")

        error =
          Error.transport_error(reason, %{
            message: "Finch error: #{inspect(reason)}"
          })

        {:error, error}

      {:error, :timeout} ->
        Logger.error("SOAP request timeout after #{timeout}ms")

        error =
          Error.transport_error(:timeout, %{
            message: "Request timeout after #{timeout}ms",
            timeout: timeout
          })

        {:error, error}

      {:error, reason} ->
        Logger.error("SOAP request failed: #{inspect(reason)}")

        error =
          Error.transport_error(reason, %{
            message: "Request failed: #{inspect(reason)}"
          })

        {:error, error}
    end
  end

  @doc """
  Builds HTTP headers for SOAP requests.
  """
  @spec build_headers(keyword()) :: [{String.t(), String.t()}]
  def build_headers(options) do
    soap_action = Keyword.get(options, :soap_action, "")
    custom_headers = Keyword.get(options, :headers, [])
    basic_auth = Keyword.get(options, :basic_auth)

    # Filter out default headers that are overridden by custom headers
    custom_header_names = Enum.map(custom_headers, fn {name, _} -> String.downcase(name) end)

    filtered_defaults =
      Enum.reject(@default_headers, fn {name, _} ->
        String.downcase(name) in custom_header_names
      end)

    base_headers =
      filtered_defaults
      |> update_soap_action(soap_action)
      |> Kernel.++(custom_headers)

    # Add Basic authentication header if provided
    case basic_auth do
      {username, password} when is_binary(username) and is_binary(password) ->
        auth_header = Basic.header(username, password)
        [auth_header | base_headers]

      _ ->
        base_headers
    end
  end

  @doc """
  Validates a URL for SOAP requests.

  ## Examples

      iex> Lather.Http.Transport.validate_url("https://example.com/soap")
      :ok

      iex> Lather.Http.Transport.validate_url("invalid-url")
      {:error, :invalid_url}

  """
  @spec validate_url(String.t()) :: :ok | {:error, :invalid_url}
  def validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        :ok

      _ ->
        {:error, :invalid_url}
    end
  end

  def validate_url(_), do: {:error, :invalid_url}

  @doc """
  Creates SSL options for secure SOAP connections.

  ## Parameters

  * `options` - SSL configuration options

  ## Options

  * `:verify` - Verification mode (:verify_peer or :verify_none)
  * `:cacerts` - List of CA certificates
  * `:cert` - Client certificate
  * `:key` - Client private key
  * `:versions` - Supported TLS versions

  """
  @spec ssl_options(keyword()) :: keyword()
  def ssl_options(options \\ []) do
    default_ssl_options = [
      verify: :verify_peer,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ],
      versions: [:"tlsv1.2", :"tlsv1.3"]
    ]

    Keyword.merge(default_ssl_options, options)
  end

  defp update_soap_action(headers, soap_action) do
    Enum.map(headers, fn
      {"soapaction", _} -> {"soapaction", soap_action}
      header -> header
    end)
  end

  defp handle_response(%Finch.Response{status: status, body: body, headers: headers})
       when status in 200..299 do
    Logger.debug("SOAP request completed with status #{status}")
    {:ok, %{status: status, body: body, headers: headers}}
  end

  defp handle_response(%Finch.Response{status: status, body: body, headers: headers}) do
    Logger.warning("SOAP request returned HTTP #{status}")
    error = Error.http_error(status, body, headers)
    {:error, error}
  end
end
