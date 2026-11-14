defmodule Lather.DynamicClient do
  @moduledoc """
  Dynamic SOAP client that can work with any SOAP service.

  This client uses WSDL analysis to understand service operations and
  dynamically builds SOAP requests without requiring service-specific code.
  """

  alias Lather.Client
  alias Lather.Wsdl.Analyzer
  alias Lather.Operation.Builder

  alias Lather.Auth.{
    WSSecurity,
    Signature,
    JWT,
    APIKey,
    SAML,
    XMLEncryption,
    WSTrust,
    Certificate
  }

  alias Lather.Error
  alias Lather.Soap.Elements

  defstruct [:base_client, :service_info, :default_options]

  @type t :: %__MODULE__{
          base_client: Client.t(),
          service_info: map(),
          default_options: keyword()
        }

  @doc """
  Creates a new dynamic client from a WSDL URL or file path.

  ## Parameters

    * `wsdl_source` - URL or file path to the WSDL
    * `options` - Client configuration options

  ## Options

    * `:service_name` - Specific service name if WSDL contains multiple services
    * `:endpoint_override` - Override the endpoint URL from WSDL
    * `:default_headers` - Default headers to include in all requests
    * `:authentication` - `{:basic, username, password}` sends an HTTP
      `Authorization` header; `{:wssecurity, username, password}` (or
      `{:wssecurity, username, password, opts}` with the options of
      `Lather.Auth.WSSecurity.username_token/3`, e.g. `password_type: :digest`)
      adds a WS-Security `UsernameToken` SOAP header to every call;
      `{:signature, key}`       adds a WS-Security `Signature` header (digest +
      HMAC-SHA256) verified server-side with `:verify_signature`
    * `:encryption` - `{:aes256, key}` sends the operation body as an
      XML-encrypted payload (`xenc:EncryptedData`, AES-256-CBC) that servers
      configured with `:encryption_key` decrypt transparently
    * `:timeout` - Default request timeout
    * `:soap_version` - SOAP protocol version (`:v1_1` or `:v1_2`, auto-detected if not specified)
    * `:namespace_prefix` - Default namespace prefix for operation elements in all calls (e.g. `"ns0"`).
      Can be overridden per call via `call/4`.

  ## Examples

      {:ok, client} = Lather.DynamicClient.new("http://example.com/service?wsdl")

      {:ok, client} = Lather.DynamicClient.new(
        "http://example.com/service?wsdl",
        authentication: {:basic, "user", "pass"},
        timeout: 60_000
      )
  """
  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(wsdl_source, options \\ []) do
    with {:ok, service_info} <- Analyzer.load_and_analyze(wsdl_source, options),
         {:ok, base_client} <-
           create_base_client(service_info, options ++ [wsdl_source: wsdl_source]) do
      # Determine SOAP version - use explicit option or detect from WSDL
      soap_version =
        Keyword.get(options, :soap_version) ||
          Map.get(service_info, :soap_version, :v1_1)

      # Add soap_version to default options
      enhanced_options = Keyword.put(options, :soap_version, soap_version)

      dynamic_client = %__MODULE__{
        base_client: base_client,
        service_info: service_info,
        default_options: enhanced_options
      }

      {:ok, dynamic_client}
    end
  end

  @doc """
  Warm up the HTTP connection pool for a dynamic client's endpoint.

  Starts a dedicated Finch pool sized for the client so the first requests
  reuse already-established connections. Pass the returned pool name via
  the `pool_name:` option on subsequent calls (or set it in the client's
  default options with `with_pool/2`).

  ## Examples

      {:ok, client} = Lather.DynamicClient.new(wsdl_url)
      {:ok, pool} = Lather.DynamicClient.warm_pool(client)
      {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"}, pool_name: pool)

  """
  @spec warm_pool(t(), keyword()) :: {:ok, atom()} | {:error, term()}
  def warm_pool(%__MODULE__{base_client: base_client}, options \\ []) do
    alias Lather.Http.Transport
    Transport.warm_connection(base_client.endpoint, options)
  end

  @doc """
  Returns a copy of the client whose default transport options use the
  given Finch pool.
  """
  @spec with_pool(t(), atom()) :: t()
  def with_pool(%__MODULE__{} = client, pool_name) do
    %{client | default_options: Keyword.put(client.default_options, :pool_name, pool_name)}
  end

  @doc """
  Lists all available operations for the service.

  ## Examples

      operations = Lather.DynamicClient.list_operations(client)
      # [
      #   %{name: "GetUser", required_parameters: ["userId"], ...},
      #   %{name: "CreateUser", required_parameters: ["userData"], ...}
      # ]
  """
  @spec list_operations(t()) :: [map()]
  def list_operations(%__MODULE__{service_info: service_info}) do
    Enum.map(service_info.operations, &Builder.get_operation_metadata/1)
  end

  @doc """
  Gets detailed information about a specific operation.

  ## Parameters

    * `client` - The dynamic client
    * `operation_name` - Name of the operation to inspect

  ## Examples

      {:ok, operation_info} = Lather.DynamicClient.get_operation_info(client, "GetUser")
      # %{
      #   name: "GetUser",
      #   required_parameters: ["userId"],
      #   optional_parameters: [],
      #   return_type: "User",
      #   soap_action: "http://example.com/GetUser"
      # }
  """
  @spec get_operation_info(t(), String.t()) :: {:ok, map()} | {:error, :operation_not_found}
  def get_operation_info(%__MODULE__{service_info: service_info}, operation_name) do
    case Enum.find(service_info.operations, fn op -> op.name == operation_name end) do
      nil ->
        error =
          Error.validation_error(operation_name, :operation_not_found, %{
            message: "Operation '#{operation_name}' not found in WSDL",
            available_operations: Enum.map(service_info.operations, & &1.name)
          })

        {:error, error}

      operation ->
        {:ok, Builder.get_operation_metadata(operation)}
    end
  end

  @doc """
  Calls a SOAP operation dynamically.

  ## Parameters

    * `client` - The dynamic client
    * `operation_name` - Name of the operation to call
    * `parameters` - Map of parameters for the operation
    * `options` - Additional call options

  ## Options

    * `:headers` - Additional SOAP headers
    * `:timeout` - Request timeout override
    * `:validate` - Whether to validate parameters (default: true)
    * `:namespace_prefix` - Namespace prefix for the operation element (e.g. `"ns0"`).
      Overrides the client-level `:namespace_prefix` set in `new/2` for this call only.

  ## Examples

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "GetUser",
        %{"userId" => "12345"}
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "CreateUser",
        %{"userData" => %{"name" => "John", "email" => "john@example.com"}},
        headers: [%{"Authentication" => "Bearer token123"}]
      )
  """
  @spec call(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def call(%__MODULE__{} = dynamic_client, operation_name, parameters, options \\ []) do
    %{service_info: service_info, base_client: base_client, default_options: default_opts} =
      dynamic_client

    pool = Keyword.get(options, :prefetch_pool) || Keyword.get(default_opts, :prefetch_pool)

    if pool do
      case Lather.Prefetch.fetch(pool, operation_name, parameters) do
        {:ok, result} ->
          {:ok, Map.put(result, "prefetched", true)}

        :miss ->
          do_call(
            dynamic_client,
            operation_name,
            parameters,
            options,
            service_info,
            base_client,
            default_opts,
            pool
          )
      end
    else
      do_call(
        dynamic_client,
        operation_name,
        parameters,
        options,
        service_info,
        base_client,
        default_opts,
        nil
      )
    end
  end

  defp do_call(
         %__MODULE__{} = dynamic_client,
         operation_name,
         parameters,
         options,
         service_info,
         base_client,
         default_opts,
         pool
       ) do
    merged_opts = Keyword.merge(default_opts, options)
    plugins = Keyword.get(merged_opts, :plugins, [])

    merged_opts =
      Keyword.put(
        merged_opts,
        :headers,
        Keyword.get(merged_opts, :headers, []) ++
          addressing_headers(merged_opts, base_client.endpoint, operation_name) ++
          reliable_headers(merged_opts)
      )

    plugin_before =
      if plugins == [] do
        {:ok, merged_opts}
      else
        Lather.Plugin.run_before_request(plugins, operation_name, merged_opts)
      end

    with {:ok, plugin_opts} <- plugin_before,
         opts = Keyword.merge(merged_opts, plugin_opts),
         {:ok, operation_info} <- find_operation(service_info, operation_name),
         :ok <- check_policy_negotiation(opts, base_client.endpoint),
         :ok <- maybe_validate_parameters(operation_info, parameters, options),
         {:ok, soap_envelope} <-
           build_request(
             operation_info,
             parameters,
             service_info,
             opts
           ),
         {:ok, response} <-
           traced_send(
             opts,
             base_client,
             soap_envelope,
             operation_info,
             default_opts,
             options
           ),
         {:ok, parsed_response} <- parse_response(operation_info, response, options) do
      maybe_prefetch(
        pool,
        Keyword.get(options, :prefetch) || Keyword.get(default_opts, :prefetch),
        dynamic_client,
        options
      )

      persist_store = Keyword.get(opts, :persist_store)

      if persist_store do
        Lather.Persistence.record(persist_store, operation_name, parameters, parsed_response)
      end

      {:ok, parsed_response}
    end
    |> then(fn result ->
      if plugins == [] do
        result
      else
        if match?({:error, _}, result) do
          Lather.Plugin.run_on_error(plugins, operation_name, elem(result, 1))
        end

        Lather.Plugin.run_after_response(plugins, operation_name, result)
      end
    end)
  end

  defp traced_send(opts, base_client, envelope, operation_info, default_opts, options) do
    if Keyword.get(opts, :trace, false) do
      context = Lather.Tracing.trace_context(opts)

      Lather.Tracing.span(
        operation_info.name,
        %{
          operation: operation_info.name,
          endpoint: base_client.endpoint,
          trace_id: context[:trace_id],
          span_id: context[:span_id]
        },
        fn ->
          send_with_reliability(
            base_client,
            envelope,
            operation_info,
            default_opts,
            options,
            opts
          )
        end,
        Keyword.get(opts, :trace_collector)
      )
    else
      send_with_reliability(base_client, envelope, operation_info, default_opts, options, opts)
    end
  end

  defp reliable_headers(options) do
    if Keyword.get(options, :reliable, false) do
      Lather.ReliableMessaging.headers(Lather.ReliableMessaging.generate_message_id(), 1)
    else
      []
    end
  end

  defp send_with_reliability(
         base_client,
         envelope,
         operation_info,
         default_opts,
         options,
         merged_opts
       ) do
    if Keyword.get(merged_opts, :reliable, false) do
      retries = Keyword.get(merged_opts, :retries, 3)

      Lather.ReliableMessaging.deliver(
        fn -> send_request(base_client, envelope, operation_info, default_opts, options) end,
        retries
      )
    else
      send_request(base_client, envelope, operation_info, default_opts, options)
    end
  end

  defp maybe_prefetch(_pool, nil, _client, _options), do: :ok

  defp maybe_prefetch(pool, invocations, client, options) when is_list(invocations) do
    Task.start(fn ->
      Enum.each(invocations, fn {operation, params} ->
        case call(client, operation, params, Keyword.delete(options, :prefetch)) do
          {:ok, result} -> Lather.Prefetch.put(pool, operation, params, result)
          _ -> :ok
        end
      end)
    end)

    :ok
  end

  @doc """
  Calls a streaming operation and returns a lazy stream of response maps.

  Operations whose handlers return `{:stream, items}` are sent as chunked
  SOAP responses ("gRPC-style"); each chunk is one response envelope and
  is parsed as it arrives.

  ## Examples

      stream = Lather.DynamicClient.stream_operation(client, "StreamItems", %{})
      Enum.take(stream, 3)

  """
  @spec stream_operation(t(), String.t(), map(), keyword()) :: Enumerable.t()
  def stream_operation(%__MODULE__{} = dynamic_client, operation_name, parameters, options \\ []) do
    %{service_info: service_info, default_options: default_opts} =
      dynamic_client

    case find_operation(service_info, operation_name) do
      {:ok, operation_info} ->
        case build_request(
               operation_info,
               parameters,
               service_info,
               Keyword.merge(default_opts, options)
             ) do
          {:ok, envelope} ->
            start_envelope_stream(dynamic_client, envelope, options, default_opts)

          {:error, reason} ->
            Stream.map([{:error, reason}], fn item -> item end)
        end

      {:error, reason} ->
        Stream.map([{:error, reason}], fn item -> item end)
    end
  end

  defp start_envelope_stream(client, envelope, options, default_opts) do
    sender = self()

    soap_version =
      Keyword.get(options, :soap_version, Keyword.get(default_opts, :soap_version, :v1_1))

    content_type =
      if soap_version == :v1_2,
        do: "application/soap+xml; charset=utf-8",
        else: "text/xml; charset=utf-8"

    headers =
      [{"content-type", content_type}, {"accept", "application/soap+xml, text/xml"}] ++
        List.wrap(Keyword.get(options, :headers, []))

    endpoint = client.base_client.endpoint

    Task.start(fn ->
      request = Finch.build(:post, endpoint, headers, envelope)

      case Finch.stream_while(request, Lather.Finch, nil, fn event, acc ->
             case event do
               {:data, chunk} -> send(sender, {:chunk, chunk})
               _ -> :ok
             end

             {:cont, acc}
           end) do
        {:ok, _} -> :ok
        {:error, reason} -> send(sender, {:error, reason})
      end

      send(sender, :done)
    end)

    unfold_envelopes("")
  end

  defp unfold_envelopes(buffer) do
    Stream.unfold(buffer, fn state -> unfold_step(state) end)
  end

  defp unfold_step(buffer) do
    case take_envelope(buffer) do
      {envelope, rest} ->
        case Lather.Xml.Parser.parse(envelope) do
          {:ok, parsed} ->
            body = get_in(parsed, ["soap:Envelope", "soap:Body"]) || parsed
            {{:ok, body}, rest}

          {:error, reason} ->
            {{:error, reason}, rest}
        end

      nil ->
        receive do
          {:chunk, chunk} -> unfold_step(buffer <> chunk)
          :done -> nil
          {:error, reason} -> raise "stream failed: #{inspect(reason)}"
        after
          30_000 -> nil
        end
    end
  end

  defp take_envelope(buffer) do
    case :binary.match(buffer, "</soap:Envelope>") do
      {idx, len} ->
        {binary_part(buffer, 0, idx + len),
         binary_part(buffer, idx + len, byte_size(buffer) - idx - len)}

      _ ->
        nil
    end
  end

  @doc """
  Calls an operation asynchronously, returning a `Task`.

  Await it with `await/2` (or `Task.await/2`).

  ## Examples

      task = Lather.DynamicClient.call_async(client, "GetUser", %{"userId" => "1"})
      {:ok, response} = Lather.DynamicClient.await(task)

  """
  @spec call_async(t(), String.t(), map(), keyword()) :: Task.t()
  def call_async(%__MODULE__{} = client, operation_name, parameters, options \\ []) do
    Task.async(fn -> call(client, operation_name, parameters, options) end)
  end

  @doc """
  Awaits an async call created with `call_async/4`.
  """
  @spec await(Task.t(), timeout()) :: {:ok, map()} | {:error, term()}
  def await(task, timeout \\ 30_000) do
    Task.await(task, timeout)
  end

  @doc """
  Calls many operations concurrently.

  `invocations` is a list of `{operation_name, params}` tuples. Results are
  returned in invocation order.

  ## Options

    * `:concurrency` - maximum parallel calls (default 10)
    * `:timeout` - per-call timeout in milliseconds (default 30,000)

  ## Examples

      results = Lather.DynamicClient.call_many(client, [
        {"GetUser", %{"userId" => "1"}},
        {"GetUser", %{"userId" => "2"}}
      ])
      # [{:ok, %{...}}, {:ok, %{...}}]

  """
  @spec call_many(t(), [{String.t(), map()}], keyword()) :: [{:ok, map()} | {:error, term()}]
  def call_many(%__MODULE__{} = client, invocations, options \\ []) do
    concurrency = Keyword.get(options, :concurrency, 10)
    timeout = Keyword.get(options, :timeout, 30_000)
    call_options = Keyword.drop(options, [:concurrency, :timeout])

    invocations
    |> Task.async_stream(
      fn {operation_name, params} ->
        call(client, operation_name, params, call_options)
      end,
      max_concurrency: concurrency,
      timeout: timeout,
      ordered: true
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:error, reason} -> {:error, {:task_failure, reason}}
    end)
  end

  @doc """
  Returns a lazy stream of results for a sequence of invocations, useful
  for processing large batches without materializing all responses.

  ## Examples

      Lather.DynamicClient.call_stream(client, large_list_of_invocations)
      |> Enum.take(10)

  """
  @spec call_stream(t(), [{String.t(), map()}], keyword()) :: Enumerable.t()
  def call_stream(%__MODULE__{} = client, invocations, options \\ []) do
    Stream.map(invocations, fn {operation_name, params} ->
      call(client, operation_name, params, options)
    end)
  end

  @doc """
  Validates parameters for a specific operation without making the call.

  ## Parameters

    * `client` - The dynamic client
    * `operation_name` - Name of the operation
    * `parameters` - Parameters to validate

  ## Examples

      :ok = Lather.DynamicClient.validate_parameters(client, "GetUser", %{"userId" => "123"})

      {:error, {:missing_required_parameter, "userId"}} =
        Lather.DynamicClient.validate_parameters(client, "GetUser", %{})
  """
  @spec validate_parameters(t(), String.t(), map()) :: :ok | {:error, term()}
  def validate_parameters(%__MODULE__{service_info: service_info}, operation_name, parameters) do
    with {:ok, operation_info} <- find_operation(service_info, operation_name) do
      Builder.validate_parameters(operation_info, parameters)
    end
  end

  @doc """
  Generates a report of the service capabilities.

  ## Examples

      report = Lather.DynamicClient.generate_service_report(client)
      IO.puts(report)
  """
  @spec generate_service_report(t()) :: String.t()
  def generate_service_report(%__MODULE__{service_info: service_info}) do
    Analyzer.generate_report(service_info)
  end

  @doc """
  Gets service information including endpoints, namespaces, and types.

  ## Examples

      service_info = Lather.DynamicClient.get_service_info(client)
      # %{
      #   service_name: "MyService",
      #   target_namespace: "http://example.com/service",
      #   endpoints: [...],
      #   operations: [...],
      #   types: [...]
      # }
  """
  @spec get_service_info(t()) :: map()
  def get_service_info(%__MODULE__{service_info: service_info}) do
    service_info
  end

  # Private helper functions

  defp create_base_client(service_info, options) do
    endpoint = determine_endpoint(service_info, options)
    _service_name = Keyword.get(options, :service_name, service_info.service_name)

    base_client = Client.new(endpoint, options)

    # Apply authentication if specified
    client_with_auth = apply_authentication(base_client, options)

    {:ok, client_with_auth}
  end

  defp determine_endpoint(service_info, options) do
    case Keyword.get(options, :endpoint_override) do
      nil ->
        # Use first available endpoint from WSDL
        extracted_endpoint =
          case service_info.endpoints do
            [first_endpoint | _] -> first_endpoint.address.location
            [] -> ""
          end

        # Check if extracted endpoint is localhost or invalid, use WSDL source as fallback
        if is_localhost_or_invalid?(extracted_endpoint) do
          derive_endpoint_from_wsdl_source(options)
        else
          extracted_endpoint
        end

      override_endpoint ->
        override_endpoint
    end
  end

  defp is_localhost_or_invalid?(endpoint) do
    endpoint == "" or
      String.contains?(endpoint, "localhost") or
      String.contains?(endpoint, "127.0.0.1") or
      String.contains?(endpoint, "http://localhost")
  end

  defp derive_endpoint_from_wsdl_source(options) do
    case Keyword.get(options, :wsdl_source) do
      nil ->
        ""

      wsdl_url when is_binary(wsdl_url) ->
        # Strip the wsdl query parameter (any position) to get the service
        # endpoint, keeping other query params such as ?tenant=...
        parts = String.split(wsdl_url, "?", parts: 2)
        base = hd(parts)

        query =
          case parts do
            [_base, q] -> q
            _other -> ""
          end

        kept =
          query
          |> String.split("&")
          |> Enum.reject(fn part ->
            key = part |> String.split("=") |> hd |> String.downcase()
            key == "wsdl"
          end)

        case kept do
          [] -> base
          _ -> base <> "?" <> Enum.join(kept, "&")
        end

      _ ->
        ""
    end
  end

  defp apply_authentication(client, options) do
    case Keyword.get(options, :authentication) do
      {:basic, username, password} ->
        # Transport.build_headers/1 turns :basic_auth into the Authorization
        # header; Lather.Client has no :headers field to prepend to.
        %{client | options: Keyword.put(client.options, :basic_auth, {username, password})}

      _ ->
        # WS-Security is a SOAP header, added per request in build_request/4.
        client
    end
  end

  # `{:wssecurity, username, password}` or
  # `{:wssecurity, username, password, opts}` (opts as accepted by
  # `Lather.Auth.WSSecurity.username_token/3`, e.g. `password_type: :digest`).
  defp ws_security_headers(options) do
    case Keyword.get(options, :authentication) do
      {:wssecurity, username, password} ->
        [WSSecurity.username_token(username, password)]

      {:wssecurity, username, password, ws_opts} ->
        [WSSecurity.username_token(username, password, ws_opts)]

      _ ->
        []
    end
  end

  # `{:signature, key}` adds a WS-Security Signature header (see
  # Lather.Auth.Signature) computed over the operation and parameters.
  defp signature_headers(options, operation_name, parameters) do
    case Keyword.get(options, :authentication) do
      {:signature, key} when is_binary(key) ->
        [Signature.sign_header(operation_name, parameters, key)]

      _ ->
        []
    end
  end

  # `{:jwt, secret}` or `{:jwt, secret, claims}` adds a WS-Security header
  # containing an HS256-signed JWT (see Lather.Auth.JWT).
  defp jwt_headers(options) do
    case Keyword.get(options, :authentication) do
      {:jwt, secret} when is_binary(secret) ->
        [JWT.security_header(JWT.token(%{}, secret))]

      {:jwt, secret, claims} when is_binary(secret) and is_map(claims) ->
        [JWT.security_header(JWT.token(claims, secret))]

      _ ->
        []
    end
  end

  # `{:api_key, key}` sends the key as an HTTP `X-API-Key` header
  # (see Lather.Auth.APIKey).
  defp api_key_headers(default_opts, call_opts) do
    case Keyword.get(call_opts, :authentication) || Keyword.get(default_opts, :authentication) do
      {:api_key, key} when is_binary(key) -> APIKey.header(key)
      _ -> []
    end
  end

  # `{:certificate, pem}` sends the client certificate as an HTTP
  # `X-Client-Certificate` header (see Lather.Auth.Certificate).
  defp cert_headers(default_opts, call_opts) do
    case Keyword.get(call_opts, :authentication) || Keyword.get(default_opts, :authentication) do
      {:certificate, pem} when is_binary(pem) ->
        Certificate.header(pem)

      {:certificate, {:file, path}} ->
        case File.read(path) do
          {:ok, pem} -> Certificate.header(pem)
          _ -> []
        end

      _ ->
        []
    end
  end

  # `{:saml, secret}`, `{:saml, secret, subject}` or
  # `{:saml, secret, subject, opts}` adds a WS-Security header containing a
  # signed SAML assertion (see Lather.Auth.SAML).
  defp saml_headers(options) do
    case Keyword.get(options, :authentication) do
      {:saml, secret} when is_binary(secret) ->
        [SAML.security_header(SAML.assertion("client", secret: secret))]

      {:saml, secret, subject} when is_binary(secret) and is_binary(subject) ->
        [SAML.security_header(SAML.assertion(subject, secret: secret))]

      {:saml, secret, subject, opts}
      when is_binary(secret) and is_binary(subject) and is_list(opts) ->
        [SAML.security_header(SAML.assertion(subject, Keyword.put(opts, :secret, secret)))]

      _ ->
        []
    end
  end

  # `{:wstrust, issuer_secret}`, `{:wstrust, issuer_secret, subject}` issue a
  # WS-Trust token locally (see Lather.Auth.WSTrust); `{:wstrust_token, token}`
  # presents a token obtained from an issuer endpoint.
  defp wstrust_headers(options) do
    case Keyword.get(options, :authentication) do
      {:wstrust, secret} when is_binary(secret) ->
        [WSTrust.security_header(WSTrust.issue_token(secret, "client"))]

      {:wstrust, secret, subject} when is_binary(secret) and is_binary(subject) ->
        [WSTrust.security_header(WSTrust.issue_token(secret, subject))]

      {:wstrust_token, token} when is_binary(token) ->
        [WSTrust.security_header(token)]

      _ ->
        []
    end
  end

  # WS-Addressing: `addressing: true` or
  # `addressing: %{to:, from:, action:, message_id:}` adds wsa:To/wsa:From/
  # wsa:Action/wsa:MessageID headers to the SOAP envelope.
  defp addressing_headers(options, endpoint, operation_name) do
    case Keyword.get(options, :addressing) do
      nil ->
        []

      true ->
        [ws_addressing_header(endpoint, operation_name, nil, nil)]

      opts when is_map(opts) ->
        [
          ws_addressing_header(
            Map.get(opts, "to") || Map.get(opts, :to) || endpoint,
            Map.get(opts, "action") || Map.get(opts, :action) || operation_name,
            Map.get(opts, "from") || Map.get(opts, :from),
            Map.get(opts, "message_id") || Map.get(opts, :message_id)
          )
        ]

      _ ->
        []
    end
  end

  defp check_policy_negotiation(options, endpoint) do
    case Keyword.get(options, :negotiate) do
      nil ->
        :ok

      _ ->
        with {:ok, policy} <- Lather.Policy.negotiate(endpoint) do
          Lather.Policy.validate(options, policy)
        end
    end
  end

  defp ws_addressing_header(to, action, from, message_id) do
    header = %{
      "wsa:To" => to,
      "wsa:Action" => action,
      "wsa:MessageID" => message_id || Lather.Wsdl.Addressing.generate_message_id()
    }

    header = if from, do: Map.put(header, "wsa:From", from), else: header

    Map.put(header, "@xmlns:wsa", "http://www.w3.org/2005/08/addressing")
  end

  defp find_operation(service_info, operation_name) do
    case Enum.find(service_info.operations, fn op -> op.name == operation_name end) do
      nil ->
        error =
          Error.validation_error(operation_name, :operation_not_found, %{
            message: "Operation '#{operation_name}' not found in WSDL",
            available_operations: Enum.map(service_info.operations, & &1.name)
          })

        {:error, error}

      operation ->
        {:ok, operation}
    end
  end

  defp maybe_validate_parameters(operation_info, parameters, options) do
    should_validate = Keyword.get(options, :validate, true)

    if should_validate do
      Builder.validate_parameters(operation_info, parameters)
    else
      :ok
    end
  end

  defp build_request(operation_info, parameters, service_info, options) do
    headers =
      ws_security_headers(options) ++
        signature_headers(options, operation_info.name, parameters) ++
        jwt_headers(options) ++
        saml_headers(options) ++
        wstrust_headers(options) ++
        List.wrap(Keyword.get(options, :headers, []))

    soap_version = Keyword.get(options, :soap_version, :v1_1)

    request_options = [
      namespace: service_info.target_namespace,
      headers: headers,
      style: get_operation_style(operation_info),
      use: get_operation_use(operation_info),
      version: soap_version,
      namespace_prefix: Keyword.get(options, :namespace_prefix),
      types: Map.get(service_info, :types, [])
    ]

    case Builder.build_request(operation_info, parameters, request_options) do
      {:ok, envelope} ->
        {:ok, maybe_encrypt_envelope(envelope, options, operation_info, parameters)}

      other ->
        other
    end
  end

  # `encryption: {:aes256, key}` replaces the operation body with an
  # XML-encrypted payload (see Lather.Auth.XMLEncryption).
  defp maybe_encrypt_envelope(envelope, options, operation_info, parameters) do
    case Keyword.get(options, :encryption) do
      {:aes256, key} when is_binary(key) ->
        XMLEncryption.encrypt_envelope(envelope, operation_info.name, parameters, key)

      _ ->
        envelope
    end
  end

  defp send_request(base_client, soap_envelope, operation_info, default_opts, call_opts) do
    alias Lather.Http.Transport

    alias Lather.Xml.Parser

    soap_action = operation_info.soap_action || ""
    timeout = Keyword.get(call_opts, :timeout) || Keyword.get(default_opts, :timeout, 30_000)

    # Get SOAP version from default options
    soap_version = Keyword.get(default_opts, :soap_version, :v1_1)

    # Remove :headers from call_opts since those are SOAP headers (already consumed by build_request),
    # not HTTP headers. Transport.build_headers expects HTTP headers as tuples {name, value}.
    http_call_opts = Keyword.delete(call_opts, :headers)

    # Combine client options with call options (call options win), then pin
    # the per-call timeout/action/version last so they always take effect.
    transport_options =
      base_client.options
      |> Keyword.merge(http_call_opts)
      |> Keyword.merge(
        timeout: timeout,
        soap_action: soap_action,
        soap_version: soap_version
      )

    transport_options =
      Keyword.put(
        transport_options,
        :headers,
        Keyword.get(transport_options, :headers, []) ++
          api_key_headers(default_opts, call_opts) ++
          cert_headers(default_opts, call_opts)
      )

    # Send the pre-built envelope directly
    case Transport.post(base_client.endpoint, soap_envelope, transport_options) do
      {:ok, response} ->
        # Parse XML from successful response
        case Parser.parse(response.body) do
          {:ok, parsed_xml} ->
            # SOAP 1.2 may return a fault with an HTTP 200 status; detect it
            # even on a successful status code.
            case extract_soap_fault(parsed_xml) do
              {:ok, fault} -> {:error, {:soap_fault, fault}}
              :not_fault -> {:ok, parsed_xml}
            end

          {:error, parse_error} ->
            {:error,
             %{
               type: :xml_parse_error,
               message: "Failed to parse response XML",
               details: parse_error
             }}
        end

      {:error, %{status: 500, type: :http_error, body: body}} when is_binary(body) ->
        # HTTP 500 might contain a SOAP fault - try to parse it
        case Parser.parse(body) do
          {:ok, parsed_response} ->
            # Check if this is a SOAP fault
            case extract_soap_fault(parsed_response) do
              {:ok, fault} -> {:error, {:soap_fault, fault}}
              :not_fault -> {:error, %{status: 500, type: :http_error, body: body}}
            end

          {:error, _parse_error} ->
            # If we can't parse the response, return the original HTTP error
            {:error, %{status: 500, type: :http_error, body: body}}
        end

      {:error, other_error} ->
        {:error, other_error}
    end
  end

  defp extract_soap_fault(parsed_response) do
    # Prefix-agnostic lookup: peers use soap:, soapenv:, SOAP-ENV:, s:, ...
    fault = Elements.get_in(parsed_response, ["Envelope", "Body", "Fault"])

    if fault do
      # SOAP 1.1 (faultcode/faultstring) and 1.2 (Code/Value, Reason/Text)
      fault_info = %{
        fault_code:
          extract_text_content(
            Elements.get(fault, "faultcode") || Elements.get_in(fault, ["Code", "Value"]) || ""
          ),
        fault_string:
          extract_text_content(
            Elements.get(fault, "faultstring") || Elements.get_in(fault, ["Reason", "Text"]) ||
              ""
          ),
        fault_actor:
          extract_text_content(
            Elements.get(fault, "faultactor") || Elements.get(fault, "Role") || ""
          ),
        detail:
          extract_text_content(
            Elements.get(fault, "detail") || Elements.get(fault, "Detail") || ""
          )
      }

      {:ok, fault_info}
    else
      :not_fault
    end
  end

  defp extract_text_content(value) when is_map(value) do
    Map.get(value, "#text", "")
  end

  defp extract_text_content(value) when is_binary(value) do
    value
  end

  defp extract_text_content(_) do
    ""
  end

  defp parse_response(operation_info, response, _options) do
    style = get_operation_style(operation_info)
    Builder.parse_response(operation_info, response, style: style)
  end

  defp get_operation_style(operation_info) do
    Map.get(operation_info, :style, :document)
  end

  defp get_operation_use(operation_info) do
    Map.get(operation_info.input, :use, :literal)
  end
end
