defmodule Lather.Http.Transport do
  @moduledoc """
  HTTP transport layer for SOAP requests.

  Handles HTTP/HTTPS communication using Finch for connection pooling
  and efficient request handling.
  """

  require Logger
  alias Lather.Auth.Basic
  alias Lather.Error
  alias Lather.Http.SSLPoolManager

  # SOAP 1.1 headers
  @soap_1_1_headers [
    {"content-type", "text/xml; charset=utf-8"},
    {"accept", "text/xml"},
    {"soapaction", ""}
  ]

  # SOAP 1.2 headers (no SOAPAction header - embedded in Content-Type)
  @soap_1_2_headers [
    {"content-type", "application/soap+xml; charset=utf-8"},
    {"accept", "application/soap+xml, text/xml"}
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
  * `:soap_version` - SOAP protocol version (`:v1_1` or `:v1_2`, default: `:v1_1`)
  * `:ssl_options` - SSL/TLS options for HTTPS connections.
    Each distinct set of options starts a dedicated Finch pool on first
    use. The number of distinct SSL pools is bounded by
    `Application.get_env(:lather, :max_ssl_pools, 50)` (see
    `Lather.Http.SSLPoolManager`); requests that would exceed the limit
    fail with a `:ssl_pool_limit_exceeded` transport error. Reuse stable
    options (e.g. via `ssl_options/1`) instead of generating them
    per-request.
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

    finch_options = [
      receive_timeout: timeout,
      pool_timeout: pool_timeout
    ]

    case Keyword.get(options, :ssl_options) do
      nil ->
        request = Finch.build(:post, url, headers, body)
        perform_request(request, Lather.Finch, finch_options, url, options)

      ssl_opts ->
        # NOTE: Finch auto-starts unknown pools on demand with default
        # connection options, which would silently discard our custom
        # `transport_opts`. Claim a bounded pool slot and explicitly
        # start the pool with our SSL options *before* the first request.
        pool_tag = SSLPoolManager.pool_tag(ssl_opts)
        request = Finch.build(:post, url, headers, body, pool_tag: pool_tag)

        with :ok <- SSLPoolManager.claim(url, ssl_opts),
             :ok <- ensure_ssl_pool(Lather.Finch, url, pool_tag, ssl_opts) do
          perform_request(request, Lather.Finch, finch_options, url, options)
        else
          {:error, :pool_limit_exceeded} ->
            Logger.warning(
              "SSL pool limit (#{SSLPoolManager.max_pools()}) exceeded, refusing new pool for #{url}"
            )

            {:error,
             Error.transport_error(:ssl_pool_limit_exceeded, %{
               message:
                 "SSL connection pool limit (#{SSLPoolManager.max_pools()}) exceeded; reuse stable ssl_options instead of generating them per-request"
             })}

          {:error, reason} ->
            SSLPoolManager.release(url, ssl_opts)
            handle_request_error(reason, finch_options)
        end
    end
  end

  # Starts the tagged SSL pool with the given transport options unless it
  # is already running. Returns `:ok` or `{:error, reason}` (never raises).
  defp ensure_ssl_pool(finch, url, pool_tag, ssl_opts) do
    pool = Finch.Pool.new(url, tag: pool_tag)

    case Finch.start_pool(finch, pool, conn_opts: [transport_opts: ssl_opts]) do
      :ok -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end
 
  defp perform_request(request, finch, options, url, original_options) do
    case Finch.request(request, finch, options) do
      {:ok, %Finch.Response{} = response} ->
        handle_response(response)
 
      {:error, :no_such_pool} ->
        # Defensive fallback: pools are pre-started in `post/3`, but one
        # may have been stopped concurrently. Re-claim and restart once.
        case Keyword.get(original_options, :ssl_options) do
          nil ->
            {:error, :no_such_pool}

          ssl_opts ->
            case SSLPoolManager.claim(url, ssl_opts) do
              {:error, :pool_limit_exceeded} ->
                {:error,
                 Error.transport_error(:ssl_pool_limit_exceeded, %{
                   message: "SSL connection pool limit exceeded"
                 })}

              :ok ->
                pool_tag = SSLPoolManager.pool_tag(ssl_opts)

                case ensure_ssl_pool(finch, url, pool_tag, ssl_opts) do
                  :ok ->
                    Finch.request(request, finch, options)
                    |> case do
                      {:ok, response} -> handle_response(response)
                      {:error, reason} -> handle_request_error(reason, options)
                    end

                  {:error, reason} ->
                    SSLPoolManager.release(url, ssl_opts)
                    handle_request_error(reason, options)
                end
            end
        end
 
      {:error, reason} ->
        handle_request_error(reason, options)
    end
  end
 
  defp handle_request_error(reason, options) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
 
    case reason do
      %Finch.TransportError{} = r ->
        handle_transport_error(r, "transport")
 
      %Mint.TransportError{} = r ->
        handle_transport_error(r, "transport")
 
      %Mint.HTTPError{} = r ->
        handle_transport_error(r, "HTTP")
 
      %Finch.Error{} = r ->
        handle_transport_error(r, "Finch")
 
      :timeout ->
        Logger.error("SOAP request timeout after #{timeout}ms")
 
        error =
          Error.transport_error(:timeout, %{
            message: "Request timeout after #{timeout}ms",
            timeout: timeout
          })
 
        {:error, error}
 
      reason ->
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

  ## Parameters

  * `options` - Request options including SOAP version and action

  ## Options

  * `:soap_version` - SOAP protocol version (`:v1_1` or `:v1_2`, default: `:v1_1`)
  * `:soap_action` - SOAPAction header value or action to embed in Content-Type
  * `:headers` - Additional custom headers
  * `:basic_auth` - Basic authentication credentials

  """
  @spec build_headers(keyword()) :: [{String.t(), String.t()}]
  def build_headers(options) do
    soap_version = Keyword.get(options, :soap_version, :v1_1)
    soap_action = Keyword.get(options, :soap_action, "")
    custom_headers = Keyword.get(options, :headers, [])
    basic_auth = Keyword.get(options, :basic_auth)

    # Get version-specific default headers
    default_headers = default_headers_for_version(soap_version)

    # Filter out default headers that are overridden by custom headers
    custom_header_names = Enum.map(custom_headers, fn {name, _} -> String.downcase(name) end)

    filtered_defaults =
      Enum.reject(default_headers, fn {name, _} ->
        String.downcase(name) in custom_header_names
      end)

    base_headers =
      filtered_defaults
      |> update_soap_action(soap_action, soap_version)
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

  defp update_soap_action(headers, soap_action, soap_version) do
    case soap_version do
      :v1_1 ->
        # SOAP 1.1: Use SOAPAction header (value MUST be quoted per SOAP 1.1 spec)
        # See: https://www.w3.org/TR/2000/NOTE-SOAP-20000508/#_Toc478383528
        quoted_action = "\"" <> soap_action <> "\""

        Enum.map(headers, fn
          {"soapaction", _} -> {"soapaction", quoted_action}
          header -> header
        end)

      :v1_2 ->
        # SOAP 1.2: Embed action in Content-Type header
        Enum.map(headers, fn
          {"content-type", content_type} when soap_action != "" ->
            {"content-type", content_type <> "; action=\"" <> soap_action <> "\""}

          {"content-type", content_type} ->
            {"content-type", content_type}

          header ->
            header
        end)
    end
  end

  defp default_headers_for_version(:v1_1), do: @soap_1_1_headers
  defp default_headers_for_version(:v1_2), do: @soap_1_2_headers

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

  defp handle_transport_error(reason, label) do
    normalized_reason = transport_reason(reason)

    Logger.error("SOAP #{label} error: #{inspect(normalized_reason)}")

    error =
      Error.transport_error(normalized_reason, %{
        message: "#{label} error: #{inspect(normalized_reason)}",
        source: reason
      })

    {:error, error}
  end

  defp transport_reason(%Finch.TransportError{source: source}), do: transport_reason(source)
  defp transport_reason(%{reason: reason}), do: reason
  defp transport_reason(reason), do: reason
end
