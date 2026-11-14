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
  alias Lather.Http.BasicClient

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
  Starts a dedicated, supervised connection pool for a target endpoint.

  This "warms up" connections to a service ahead of the first request: the
  pool is created with `size` connection slots (and optional `count`) so
  the first burst of traffic does not pay connection-establishment costs.

  Returns `{:ok, pool_name}` or `{:error, reason}`.

  ## Examples

      {:ok, pool} = Lather.Http.Transport.warm_connection("https://api.example.com/soap")
      {:ok, response} = Lather.Http.Transport.get("https://api.example.com/soap?wsdl", pool_name: pool)

  """
  @spec warm_connection(String.t(), keyword()) :: {:ok, atom()}
  def warm_connection(url, options \\ []) do
    size = Keyword.get(options, :size, 20)
    count = Keyword.get(options, :count, 1)
    pool_name = Keyword.get(options, :pool_name, Lather.Finch)

    unless Process.whereis(concat_pool_supervisor(pool_name)) do
      Finch.start_link(name: pool_name)
    end

    pool = Finch.Pool.new(url, tag: {:lather_warm, pool_name, size, count})
    Finch.start_pool(pool_name, pool, size: size, count: count)

    {:ok, pool_name}
  end

  defp concat_pool_supervisor(name) do
    String.to_atom("#{name}.Supervisor")
  end

  @doc """
  Stops a pool previously started with `warm_connection/2`.
  """
  @spec close_connection(atom(), String.t()) :: :ok | {:error, term()}
  def close_connection(pool_name, url) do
    Finch.stop_pool(pool_name, url)
  end

  @doc """
  Reports whether a warmed pool exists for `url` under `pool_name`.
  """
  @spec pool_status(atom(), String.t()) :: map() | {:error, term()}
  def pool_status(pool_name, url) do
    Finch.get_pool_status(pool_name, url)
  end

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
    if basic_client?(options) do
      BasicClient.request(
        :post,
        url,
        build_headers(options),
        body,
        Keyword.get(options, :timeout, @default_timeout)
      )
    else
      finch_post(url, body, options)
    end
  end

  defp finch_post(url, body, options) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    pool_timeout = Keyword.get(options, :pool_timeout, 5_000)
    pool_name = Keyword.get(options, :pool_name, Lather.Finch)
    headers = build_headers(options)

    Logger.debug("Sending SOAP request to #{url}")

    finch_options = [
      receive_timeout: timeout,
      pool_timeout: pool_timeout
    ]

    case Keyword.get(options, :ssl_options) do
      nil ->
        request = Finch.build(:post, url, headers, body)
        perform_request(request, pool_name, finch_options, url, options)

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

  @doc """
  Sends a GET request to the specified URL.

  ## Options

  * `:timeout` - Request timeout in milliseconds
  * `:headers` - Additional headers to include
  * `:pool_name` - Finch pool name to use (default `Lather.Finch`)

  Returns `{:ok, %{status: status, body: body, headers: headers}}` or
  `{:error, reason}`.
  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get(url, options \\ []) do
    if basic_client?(options) do
      BasicClient.request(
        :get,
        url,
        List.wrap(Keyword.get(options, :headers, [])),
        nil,
        Keyword.get(options, :timeout, @default_timeout)
      )
    else
      finch_get(url, options)
    end
  end

  defp finch_get(url, options) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    pool_timeout = Keyword.get(options, :pool_timeout, 5_000)
    pool_name = Keyword.get(options, :pool_name, Lather.Finch)

    headers =
      [{"accept", "application/soap+xml, text/xml, application/xml"}] ++
        List.wrap(Keyword.get(options, :headers, []))

    request = Finch.build(:get, url, headers)

    case Finch.request(request, pool_name,
           receive_timeout: timeout,
           pool_timeout: pool_timeout
         ) do
      {:ok, %Finch.Response{status: status, body: body, headers: headers}} ->
        {:ok, %{status: status, body: body, headers: headers}}

      {:error, reason} ->
        handle_request_error(reason, receive_timeout: timeout, pool_timeout: pool_timeout)
    end
  end

  @doc """
  Sends a POST request with a streaming request body.

  The body is any enumerable of binary chunks (e.g. a lazy stream produced
  by `Lather.Mtom.Builder.build_message_chunks/3`), which is sent to the
  server incrementally instead of buffering the whole message.

  ## Options

    * `:timeout` - Request timeout in milliseconds
    * `:headers` - Additional headers to include

  Returns `{:ok, %{status: status, body: body, headers: headers}}` or
  `{:error, reason}`.
  """
  @spec post_stream(String.t(), String.t(), Enumerable.t(), keyword()) ::
          {:ok, map()} | {:error, any()}
  def post_stream(url, content_type, body_stream, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_timeout)
    pool_timeout = Keyword.get(options, :pool_timeout, 5_000)

    headers =
      [{"content-type", content_type}, {"accept", "application/soap+xml, text/xml"}] ++
        List.wrap(Keyword.get(options, :headers, []))

    request = Finch.build(:post, url, headers, {:stream, body_stream})

    case Finch.request(request, Lather.Finch,
           receive_timeout: timeout,
           pool_timeout: pool_timeout
         ) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body, headers: response.headers}}

      {:error, reason} ->
        {:error, Error.transport_error(:transport_error, %{message: inspect(reason)})}
    end
  end

  # Starts the tagged SSL pool with the given transport options unless it
  # is already running. Returns `:ok` or `{:error, reason}` (never raises).
  defp ensure_ssl_pool(finch, url, pool_tag, ssl_opts) do
    pool = Finch.Pool.new(url, tag: pool_tag)
    # Finch.start_pool/3 is idempotent (returns :ok when the pool already
    # exists) and raises on invalid arguments; normalize both to our
    # {:error, reason} convention via rescue.
    :ok = Finch.start_pool(finch, pool, conn_opts: [transport_opts: ssl_opts])
    :ok
  rescue
    error -> {:error, error}
  end

  defp perform_request(request, finch, options, url, original_options) do
    case Keyword.get(original_options, :max_response_bytes) do
      nil ->
        perform_request_unbounded(request, finch, options, url, original_options)

      limit when is_integer(limit) ->
        perform_request_streamed(request, finch, options, limit)
    end
  end

  # Streams the response incrementally so oversized responses are aborted
  # early instead of fully buffered in memory.
  defp perform_request_streamed(request, finch, options, limit) do
    callback = fn event, acc ->
      status = elem(acc, 0)
      headers = elem(acc, 1)
      body = elem(acc, 2)
      bytes = elem(acc, 3)

      case event do
        {:status, new_status} ->
          {:cont, {new_status, headers, body, bytes}}

        {:headers, new_headers} ->
          {:cont, {status, new_headers, body, bytes}}

        {:data, chunk} ->
          new_bytes = bytes + byte_size(chunk)

          if new_bytes > limit do
            {:halt, {:too_large, status, headers, body, bytes}}
          else
            {:cont, {status, headers, body <> chunk, new_bytes}}
          end
      end
    end

    case Finch.stream_while(request, finch, {nil, [], "", 0}, callback) do
      {:ok, {:too_large, status, _headers, _body, bytes}} ->
        Logger.warning("SOAP response exceeded max_response_bytes (#{limit}) at #{bytes} bytes")

        {:error,
         Error.transport_error(:response_too_large, %{
           message: "response exceeded max_response_bytes of #{limit} bytes",
           status: status
         })}

      {:ok, {status, headers, body, _bytes}} ->
        handle_response(%Finch.Response{status: status, body: body, headers: headers})

      {:error, reason, _acc} ->
        handle_request_error(reason, options)
    end
  end

  defp perform_request_unbounded(request, finch, options, url, original_options) do
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

  defp basic_client?(options) do
    Keyword.get(options, :client, Application.get_env(:lather, :http_client, :finch)) == :basic
  end

  defp handle_request_error(reason, options) do
    timeout =
      Keyword.get(options, :receive_timeout) ||
        Keyword.get(options, :timeout, @default_timeout)

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

    # SOAP 1.2 (and some SOAP 1.1 servers) return faults with a successful
    # HTTP status. Detect them so callers receive the fault rather than a
    # bogus successful response.
    case Error.parse_soap_fault(body) do
      {:ok, fault} -> {:error, {:soap_fault, fault}}
      _ -> {:ok, %{status: status, body: body, headers: headers}}
    end
  end

  defp handle_response(%Finch.Response{status: status, body: body, headers: headers}) do
    Logger.warning("SOAP request returned HTTP #{status}")

    # SOAP faults are not limited to HTTP 500: many services return them with
    # 400/404/etc. If the body carries a SOAP Fault, surface the fault detail
    # instead of a generic HTTP error so callers get the fault code/string.
    case Error.parse_soap_fault(body) do
      {:ok, fault} ->
        {:error, {:soap_fault, fault}}

      _ ->
        {:error, Error.http_error(status, body, headers)}
    end
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
