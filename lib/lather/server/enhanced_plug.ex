defmodule Lather.Server.EnhancedPlug do
  @moduledoc """
  Enhanced Plug implementation for SOAP server endpoints with web form interface.

  Provides comprehensive SOAP service endpoints with interactive web forms,
  multi-protocol support, and complete API documentation similar to .NET Web Services.

  ## Features

  - Interactive web forms for testing operations
  - SOAP 1.1, SOAP 1.2, and JSON protocol support
  - Enhanced WSDL generation with multi-protocol bindings
  - Service overview with complete operation documentation
  - Responsive web interface for operation testing
  - Telemetry: every request emits a `[:lather, :server, :request]` span
    (`:start`/`:stop`) with duration, status, service, method, and path

  ## Usage

  In Phoenix router:

      scope "/soap" do
        pipe_through :api
        match :*, "/users", Lather.Server.EnhancedPlug, service: MyApp.UserService
        match :*, "/users/*path", Lather.Server.EnhancedPlug, service: MyApp.UserService
      end

  As standalone Plug:

      plug Lather.Server.EnhancedPlug, service: MyApp.UserService

  ## URL Patterns

  - `GET /service` - Service overview with operations list
  - `GET /service?wsdl` - Standard WSDL download
  - `GET /service?wsdl&enhanced=true` - Multi-protocol WSDL
  - `GET /service?op=OperationName` - Interactive operation form
  - `POST /service` - SOAP 1.1 endpoint
  - `POST /service/v1.2` - SOAP 1.2 endpoint
  - `POST /service/api` - JSON/REST endpoint
  - `GET /service?openapi` - OpenAPI 3.1 specification (JSON)
  - `GET /service/openapi.json` - OpenAPI 3.1 specification (JSON)
  - `GET /service?swagger` - Swagger UI explorer for the OpenAPI spec
  - `GET /service/swagger` - Swagger UI explorer for the OpenAPI spec

  ## Options

  - `:service` - The SOAP service module (required)
  - `:base_path` - Base path for service (default: "/soap")
  - `:enable_forms` - Enable web form interface (default: true)
  - `:enable_json` - Enable JSON endpoints (default: true)
  - `:auth_handler` - Custom authentication handler
  - `:validate_params` - Enable parameter validation (default: true)
  - `:max_body_size` - Maximum request body size in bytes (default: 10MB).
    Requests exceeding this limit are rejected with HTTP 413.
  """

  # Check if Jason is available for JSON support
  @jason_available Code.ensure_loaded?(Jason)

  import Plug.Conn
  require Logger

  alias Lather.Server.{
    RequestParser,
    ResponseBuilder,
    WSDLGenerator,
    EnhancedWSDLGenerator,
    FormGenerator,
    OpenAPIGenerator,
    ResultCache,
    Metrics
  }

  alias Lather.Soap.Elements
  alias Lather.Soap.FaultCodes
  alias Lather.Auth.{Signature, JWT, APIKey, SAML, XMLEncryption, Policy, WSTrust, Certificate}

  @behaviour Plug

  @min_compress_size 1024

  @impl Plug
  def init(opts) do
    opts =
      case Keyword.get(opts, :config_file) do
        nil ->
          opts

        path ->
          case Lather.Config.from_file(path) do
            {:ok, config_opts} -> Lather.Config.merge(config_opts, opts)
            {:error, _reason} -> opts
          end
      end

    service = Keyword.fetch!(opts, :service)

    unless function_exported?(service, :__soap_service__, 0) do
      raise ArgumentError,
            "#{service} is not a valid SOAP service module. Did you forget to `use Lather.Server`?"
    end

    case Keyword.get(opts, :security_policy) do
      nil -> :ok
      policy -> Policy.validate!(opts, policy)
    end

    %{
      service: service,
      base_path: Keyword.get(opts, :base_path, "/soap"),
      enable_forms: Keyword.get(opts, :enable_forms, true),
      enable_json: Keyword.get(opts, :enable_json, true),
      enable_swagger: Keyword.get(opts, :enable_swagger, true),
      auth_handler: Keyword.get(opts, :auth_handler),
      validate_params: Keyword.get(opts, :validate_params, true),
      max_body_size: Keyword.get(opts, :max_body_size, 10 * 1024 * 1024),
      understood_headers: Keyword.get(opts, :understood_headers),
      soap_roles: Keyword.get(opts, :soap_roles),
      require_addressing: Keyword.get(opts, :require_addressing, false),
      policy: Keyword.get(opts, :policy),
      enable_discovery: Keyword.get(opts, :enable_discovery, false),
      enable_eventing: Keyword.get(opts, :enable_eventing, false),
      persistence_store: Keyword.get(opts, :persistence_store),
      tenants: Keyword.get(opts, :tenants, %{}),
      fault_injection_rate: Keyword.get(opts, :fault_injection_rate, 0.0),
      debug: Keyword.get(opts, :debug, false),
      security_policy: Keyword.get(opts, :security_policy),
      verify_signature: Keyword.get(opts, :verify_signature),
      jwt_secret: Keyword.get(opts, :jwt_secret),
      saml_secret: Keyword.get(opts, :saml_secret),
      wstrust_secret: Keyword.get(opts, :wstrust_secret),
      client_certificates: Keyword.get(opts, :client_certificates),
      encryption_key: Keyword.get(opts, :encryption_key),
      api_keys: Keyword.get(opts, :api_keys),
      require_auth: Keyword.get(opts, :require_auth),
      enable_metrics: Keyword.get(opts, :enable_metrics, false),
      started_at: :os.system_time(:second),
      cache_results: Keyword.get(opts, :cache_results, false),
      cache_ttl: Keyword.get(opts, :cache_ttl, 300),
      audit_log: Keyword.get(opts, :audit_log),
      metrics: if(Keyword.get(opts, :enable_metrics, false), do: Metrics.new(), else: nil),
      result_cache:
        if(Keyword.get(opts, :cache_results, false),
          do: ResultCache.new(Keyword.get(opts, :cache_ttl, 300)),
          else: nil
        )
    }
  end

  @impl Plug
  def call(conn, config) do
    :telemetry.span(
      [:lather, :server, :request],
      %{
        service: config.service,
        method: conn.method,
        path: conn.request_path
      },
      fn ->
        start = System.monotonic_time(:microsecond)
        conn = dispatch_request(conn, config)
        duration_us = System.monotonic_time(:microsecond) - start

        record_audit(config, conn)
        record_metrics(config, conn, duration_us)

        {conn,
         %{
           status: conn.status,
           service: config.service,
           method: conn.method,
           path: conn.request_path
         }}
      end
    )
  end

  defp dispatch_request(conn, config) do
    # Ensure query params are fetched for URL pattern detection
    conn = Plug.Conn.fetch_query_params(conn)
    config = resolve_tenant(config, conn)

    case {conn.method, get_request_type(conn)} do
      # WSDL requests
      {"GET", :wsdl} ->
        handle_wsdl_request(conn, config)

      # WS-Policy requests
      {"GET", :policy} ->
        handle_policy_request(conn, config)

      # WS-Discovery requests
      {"POST", :discovery} ->
        handle_discovery_request(conn, config)

      {"GET", :discovery} ->
        handle_discovery_request(conn, config)

      # WS-Eventing requests
      {"POST", :subscribe} ->
        handle_subscribe_request(conn, config)

      {"POST", :publish} ->
        handle_publish_request(conn, config)

      {"GET", :events} ->
        handle_events_request(conn, config)

      # OpenAPI spec requests
      {"GET", :openapi} ->
        handle_openapi_request(conn, config)

      # Swagger UI requests
      {"GET", :swagger} ->
        handle_swagger_request(conn, config)

      # Operation form requests
      {"GET", {:operation_form, operation_name}} ->
        handle_operation_form_request(conn, config, operation_name)

      # Service overview
      {"GET", :service_overview} ->
        handle_service_overview_request(conn, config)

      # Health check
      {"GET", :health} ->
        handle_health_request(conn, config)

      # Metrics
      {"GET", :metrics} ->
        handle_metrics_request(conn, config)

      # Observability dashboard
      {"GET", :dashboard} ->
        handle_dashboard_request(conn, config)

      # Docs browser
      {"GET", :docs} ->
        handle_docs_request(conn, config)

      # Request history viewer
      {"GET", :history} ->
        handle_history_request(conn, config)

      # SOAP 1.1 requests (default POST)
      {"POST", :soap_1_1} ->
        with_auth(conn, config, fn c -> handle_soap_request(c, config, :v1_1) end)

      # SOAP 1.2 requests
      {"POST", :soap_1_2} ->
        with_auth(conn, config, fn c -> handle_soap_request(c, config, :v1_2) end)

      # JSON/REST requests
      {"POST", :json} when config.enable_json ->
        with_auth(conn, config, fn c -> handle_json_request(c, config) end)

      # Unsupported methods
      _ ->
        handle_unsupported_request(conn)
    end
  rescue
    error ->
      Logger.error("Enhanced SOAP server error: #{inspect(error)}")

      conn
      |> put_resp_content_type("text/xml")
      |> send_content(500, soap_fault_xml("Server", "Internal server error"))
  end

  defp record_audit(%{audit_log: nil}, _conn), do: :ok

  defp record_audit(config, conn) do
    entry = %{
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      service: inspect(config.service),
      method: conn.method,
      path: conn.request_path,
      status: conn.status
    }

    try do
      existing =
        case File.read(config.audit_log) do
          {:ok, contents} -> contents
          {:error, :enoent} -> ""
          {:error, reason} -> raise "cannot read audit log: #{inspect(reason)}"
        end

      File.write(config.audit_log, existing <> encode_json(entry) <> "\n")
    rescue
      error -> Logger.warning("Failed to write audit log: #{inspect(error)}")
    end
  end

  # Run the configured auth handler (if any) before dispatching a request.
  defp with_auth(
         conn,
         %{auth_handler: nil, api_keys: nil, require_auth: nil, client_certificates: nil},
         handler_fn
       ),
       do: handler_fn.(conn)

  defp with_auth(conn, config, handler_fn) do
    cond do
      not certificate_ok?(conn, config) ->
        unauthorized(conn, "Invalid client certificate")

      not api_key_ok?(conn, config) ->
        unauthorized(conn, "Invalid API key")

      not factors_ok?(conn, config) ->
        unauthorized(conn, "Multiple authentication factors required")

      config.auth_handler == nil ->
        handler_fn.(conn)

      true ->
        case config.auth_handler.authenticate(conn) do
          {:ok, c} -> handler_fn.(c)
          _ -> unauthorized(conn, "Authentication required")
        end
    end
  end

  defp api_key_ok?(conn, %{api_keys: keys}) do
    keys == nil or APIKey.valid?(keys, APIKey.extract(conn.req_headers))
  end

  defp certificate_ok?(conn, %{client_certificates: certs}) do
    if certs == nil do
      true
    else
      case Certificate.extract(conn.req_headers) do
        nil -> false
        pem -> match?({:ok, _}, Certificate.verify(pem, certs))
      end
    end
  end

  # `require_auth: [:api_key, :jwt, :signature, :ws_security]` enforces that
  # every listed factor is present (and, where configured, valid).
  defp factors_ok?(_conn, %{require_auth: nil}), do: true

  defp factors_ok?(conn, config) do
    headers = conn.req_headers

    Enum.all?(config.require_auth, fn factor ->
      case factor do
        :api_key ->
          APIKey.valid?(config.api_keys, APIKey.extract(headers))

        :jwt ->
          config.jwt_secret != nil

        :basic ->
          auth = List.first(Plug.Conn.get_req_header(conn, "authorization"))
          is_binary(auth) and String.starts_with?(auth, "Basic ")

        :bearer ->
          auth = List.first(Plug.Conn.get_req_header(conn, "authorization"))
          is_binary(auth) and String.starts_with?(auth, "Bearer ")

        _ ->
          false
      end
    end)
  end

  defp unauthorized(conn, message) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
    |> put_resp_content_type("text/xml")
    |> send_content(401, soap_fault_xml("Client", message))
  end

  # Determine request type from URL and query parameters
  defp get_request_type(conn) do
    cond do
      # WSDL request
      Map.has_key?(conn.query_params, "wsdl") ->
        :wsdl

      # WS-Policy request
      Map.has_key?(conn.query_params, "policy") ->
        :policy

      # WS-Discovery request
      Map.has_key?(conn.query_params, "discovery") ->
        :discovery

      # WS-Eventing requests
      Map.has_key?(conn.query_params, "subscribe") ->
        :subscribe

      Map.has_key?(conn.query_params, "publish") ->
        :publish

      Map.has_key?(conn.query_params, "events") ->
        :events

      # OpenAPI spec request
      Map.has_key?(conn.query_params, "openapi") ->
        :openapi

      String.contains?(conn.request_path, "/openapi") ->
        :openapi

      # Health check request
      Map.has_key?(conn.query_params, "health") ->
        :health

      String.contains?(conn.request_path, "/health") ->
        :health

      # Metrics request
      Map.has_key?(conn.query_params, "metrics") ->
        :metrics

      # Observability dashboard
      Map.has_key?(conn.query_params, "dashboard") ->
        :dashboard

      # Docs browser
      Map.has_key?(conn.query_params, "docs") ->
        :docs

      # Request history viewer
      Map.has_key?(conn.query_params, "history") ->
        :history

      String.contains?(conn.request_path, "/metrics") ->
        :metrics

      # Swagger UI request
      Map.has_key?(conn.query_params, "swagger") ->
        :swagger

      String.contains?(conn.request_path, "/swagger") ->
        :swagger

      # Operation form request
      Map.has_key?(conn.query_params, "op") ->
        {:operation_form, conn.query_params["op"]}

      # Check path or Content-Type for protocol version
      String.contains?(conn.request_path, "/v1.2") ->
        :soap_1_2

      conn.method == "POST" and
          RequestParser.soap_version_from_headers(conn.req_headers) == :v1_2 ->
        :soap_1_2

      String.contains?(conn.request_path, "/api") ->
        :json

      # Default cases
      conn.method == "GET" ->
        :service_overview

      conn.method == "POST" ->
        :soap_1_1

      true ->
        :unsupported
    end
  end

  # Handle Swagger UI requests
  defp handle_swagger_request(conn, config) do
    unless config.enable_swagger do
      conn
      |> put_resp_content_type("text/html")
      |> send_content(404, generate_error_page("Swagger UI is disabled for this service"))
    else
      service_info = config.service.__soap_service__()
      spec_url = get_base_url(conn, config) <> "openapi.json"

      conn
      |> put_resp_content_type("text/html")
      |> send_content(200, swagger_ui_html(service_info.name, spec_url))
    end
  end

  defp swagger_ui_html(service_name, spec_url) do
    escaped_name =
      service_name
      |> to_string()
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{escaped_name} - API Explorer</title>
        <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
        <style>
            body { margin: 0; font-family: Arial, sans-serif; }
            .swagger-header { padding: 12px 20px; background: #1f2937; color: #fff; }
            .swagger-header h1 { margin: 0; font-size: 18px; }
            .swagger-header a { color: #93c5fd; }
        </style>
    </head>
    <body>
        <div class="swagger-header">
            <h1>#{escaped_name} API Explorer</h1>
            <p>OpenAPI spec: <a href="openapi.json">openapi.json</a></p>
        </div>
        <div id="swagger-ui"></div>
        <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" crossorigin></script>
        <script>
            window.ui = SwaggerUIBundle({
                url: "#{spec_url}",
                dom_id: "#swagger-ui",
                deepLinking: true,
                tryItCredentialsPolicy: "include"
            });
        </script>
    </body>
    </html>
    """
  end

  # Handle OpenAPI spec generation requests
  defp handle_openapi_request(conn, %{service: service} = config) do
    try do
      service_info = service.__soap_service__()
      base_url = get_base_url(conn, config)

      spec = OpenAPIGenerator.generate(service_info, base_url)

      conn
      |> put_resp_content_type("application/json")
      |> send_content(200, encode_json(spec))
    rescue
      error ->
        Logger.error("OpenAPI generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_content(
          500,
          encode_json(%{
            error: %{code: "ServerError", message: "Failed to generate OpenAPI spec"}
          })
        )
    end
  end

  # Handle service health check requests
  defp handle_policy_request(conn, config) do
    policy =
      case config.policy do
        nil -> default_policy(config)
        policy -> policy
      end

    conn
    |> put_resp_content_type("application/xml")
    |> send_content(200, Lather.Policy.build_policy_xml(policy))
  end

  defp default_policy(config) do
    service_info = config.service.__soap_service__()

    %{
      "operations" => Enum.map(service_info.operations, & &1.name),
      "require_auth" =>
        cond do
          config.api_keys != nil -> ["api_key"]
          config.jwt_secret != nil -> ["jwt"]
          true -> []
        end,
      "compression" => Map.get(config, :enable_compression, true)
    }
  end

  defp ensure_event_broker(config) do
    name = event_broker_name(config)

    case Process.whereis(name) do
      nil ->
        case Lather.Eventing.start_link(name: name) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      pid ->
        pid
    end
  end

  defp event_broker_name(config) do
    :"Lather.Eventing.#{inspect(config.service)}"
  end

  defp eventing_enabled?(config) do
    config.enable_eventing
  end

  defp handle_subscribe_request(conn, config) do
    unless eventing_enabled?(config) do
      conn
      |> put_resp_content_type("application/json")
      |> send_content(404, encode_json(%{error: "Eventing is not enabled for this service"}))
    else
      broker = ensure_event_broker(config)
      channel = conn.query_params["subscribe"] || "default"
      {:ok, subscription_id} = Lather.Eventing.subscribe(channel, name: broker)

      conn
      |> put_resp_content_type("application/soap+xml")
      |> send_content(200, """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/ws/2003/05/soap-envelope"
        xmlns:wse="http://schemas.xmlsoap.org/ws/2004/06/eventing">
        <soap:Body>
          <wse:SubscribeResponse>
            <wse:SubscriptionId>#{subscription_id}</wse:SubscriptionId>
          </wse:SubscribeResponse>
        </soap:Body>
      </soap:Envelope>
      """)
    end
  end

  defp handle_publish_request(conn, config) do
    unless eventing_enabled?(config) do
      conn
      |> put_resp_content_type("application/json")
      |> send_content(404, encode_json(%{error: "Eventing is not enabled for this service"}))
    else
      broker = ensure_event_broker(config)
      channel = conn.query_params["publish"] || "default"

      body =
        case Plug.Conn.read_body(conn) do
          {:ok, body, _conn} -> body
          {:more, body, _conn} -> body
          {:error, _reason} -> ""
        end

      {:ok, count} = Lather.Eventing.publish(channel, body, name: broker)

      conn
      |> put_resp_content_type("application/json")
      |> send_content(200, encode_json(%{published: true, subscribers: count}))
    end
  end

  defp handle_events_request(conn, config) do
    unless eventing_enabled?(config) do
      conn
      |> put_resp_content_type("application/json")
      |> send_content(404, encode_json(%{error: "Eventing is not enabled for this service"}))
    else
      broker = ensure_event_broker(config)
      subscription = conn.query_params["sub"]

      case Lather.Eventing.poll(subscription, name: broker) do
        {:ok, envelopes} ->
          conn
          |> put_resp_content_type("application/soap+xml")
          |> send_content(200, Enum.join(envelopes, "
"))

        {:error, :unknown_subscription} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_content(404, encode_json(%{error: "Unknown subscription"}))
      end
    end
  end

  defp handle_discovery_request(conn, config) do
    unless config.enable_discovery do
      conn
      |> put_resp_content_type("application/json")
      |> send_content(404, encode_json(%{error: "Discovery is not enabled for this service"}))
    else
      service_info = config.service.__soap_service__()
      endpoint = "#{conn.scheme}://#{conn.host}#{conn.request_path}"

      {:ok, matches_xml} = Lather.Discovery.matches_document(service_info.name, endpoint)

      conn
      |> put_resp_content_type("application/soap+xml")
      |> send_content(200, matches_xml)
    end
  end

  defp handle_health_request(conn, config) do
    service_info = config.service.__soap_service__()

    payload = %{
      status: "ok",
      service: service_info.name,
      version: service_info[:version] || "1.0.0",
      operations: length(service_info.operations),
      uptime_seconds: :os.system_time(:second) - config.started_at
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_content(200, encode_json(payload))
  end

  # Handle service metrics/analytics requests
  defp handle_dashboard_request(conn, config) do
    service_info = config.service.__soap_service__()
    snapshot = if config.metrics, do: Metrics.snapshot(config.metrics), else: %{}

    history =
      if config.persistence_store do
        Lather.Persistence.history(config.persistence_store, 20)
      else
        []
      end

    rows =
      history
      |> Enum.map(fn record ->
        "<tr><td>#{Map.get(record, :id)}</td><td>#{Map.get(record, :operation)}</td>" <>
          "<td>#{inspect(Map.get(record, :params))}</td></tr>"
      end)
      |> Enum.join("\n")

    lang = conn.query_params["lang"] || "en"
    alias Lather.I18n

    html =
      accessible_html(
        "Lather Dashboard - #{service_info.name}",
        """
          <h1>#{I18n.t("dashboard", lang)}: #{service_info.name}</h1>
          <ul>
            <li>#{I18n.t("operations", lang)}: #{length(service_info.operations)}</li>
            <li>#{I18n.t("requests", lang)}: #{Map.get(snapshot, :requests, 0)}</li>
            <li>#{I18n.t("errors", lang)}: #{Map.get(snapshot, :errors, 0)}</li>
            <li>#{I18n.t("avg_duration", lang)}: #{Map.get(snapshot, :average_duration_ms, 0)} ms</li>
            <li>#{I18n.t("uptime", lang)}: #{:os.system_time(:second) - config.started_at} s</li>
          </ul>
          <h3>#{I18n.t("recent_requests", lang)}</h3>
          <table aria-label="#{I18n.t("recent_requests", lang)}"><tr><th>Id</th><th>Operation</th><th>Params</th></tr>#{rows}</table>
        """,
        lang
      )

    conn
    |> put_resp_content_type("text/html")
    |> send_content(200, html)
  end

  defp handle_docs_request(conn, config) do
    service_info = config.service.__soap_service__()

    lang = conn.query_params["lang"] || "en"
    alias Lather.I18n

    items =
      service_info.operations
      |> Enum.map(fn op ->
        description = Map.get(op, :description) || "No description"

        params =
          op.input
          |> Enum.map(fn param ->
            "#{param.name}: #{param.type}#{if param.required, do: " (#{I18n.t("required", lang)})", else: ""}"
          end)
          |> Enum.join(", ")

        "<h3>#{op.name}</h3><p>#{I18n.t("description", lang)}: #{description}</p><p>#{I18n.t("parameters", lang)}: #{params}</p>"
      end)
      |> Enum.join("\n")

    html =
      accessible_html(
        "Lather Docs - #{service_info.name}",
        """
          <h1>#{service_info.name}</h1>
          <h2>#{I18n.t("docs", lang)}</h2>
          #{items}
        """,
        lang
      )

    conn
    |> put_resp_content_type("text/html")
    |> send_content(200, html)
  end

  defp handle_history_request(conn, config) do
    case config.persistence_store do
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_content(404, encode_json(%{error: "Persistence is not enabled for this service"}))

      store ->
        history = Lather.Persistence.history(store, 50)

        conn
        |> put_resp_content_type("application/json")
        |> send_content(200, encode_json(%{history: history}))
    end
  end

  defp handle_metrics_request(conn, %{enable_metrics: true} = config) do
    service_info = config.service.__soap_service__()
    snapshot = Metrics.snapshot(config.metrics)

    payload = %{
      service: service_info.name,
      version: service_info[:version] || "1.0.0",
      uptime_seconds: :os.system_time(:second) - config.started_at,
      requests: snapshot.requests,
      errors: snapshot.errors,
      average_duration_ms: snapshot.average_duration_ms,
      status_counts: Map.new(snapshot.status_counts),
      operations: length(service_info.operations)
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_content(200, encode_json(payload))
  end

  defp handle_metrics_request(conn, _config) do
    conn
    |> put_resp_content_type("application/json")
    |> send_content(404, encode_json(%{error: "Metrics are not enabled for this service"}))
  end

  defp record_metrics(%{metrics: nil}, _conn, _duration_us), do: :ok

  defp record_metrics(config, conn, duration_us) do
    Metrics.record(config.metrics, conn.status, duration_us)
  end

  # Handle WSDL generation requests
  defp handle_wsdl_request(conn, %{service: service} = config) do
    try do
      service_info = service.__soap_service__()
      base_url = get_base_url(conn, config)

      wsdl_content =
        if Map.get(conn.query_params, "enhanced") in [nil, "", "1", "true"] do
          # Generate enhanced multi-protocol WSDL
          protocols =
            if config.enable_json,
              do: [:soap_1_1, :soap_1_2, :http],
              else: [:soap_1_1, :soap_1_2]

          EnhancedWSDLGenerator.cached_generate(service, base_url,
            protocols: protocols,
            include_json: config.enable_json
          )
        else
          # Generate standard WSDL
          WSDLGenerator.cached_generate(service, base_url)
        end

      conn
      |> put_resp_content_type("text/xml")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"#{service_info.name}.wsdl\""
      )
      |> send_content(200, wsdl_content)
    rescue
      error ->
        Logger.error("WSDL generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("text/xml")
        |> send_content(500, soap_fault_xml("Server", "WSDL generation failed"))
    end
  end

  # Handle operation form requests
  defp handle_operation_form_request(
         conn,
         %{service: service, enable_forms: true} = config,
         operation_name
       ) do
    try do
      service_info = service.__soap_service__()
      base_url = get_base_url(conn, config)

      case find_operation(service_info, operation_name) do
        nil ->
          conn
          |> put_resp_content_type("text/html")
          |> send_content(404, generate_error_page("Operation '#{operation_name}' not found"))

        operation ->
          html_content =
            FormGenerator.generate_operation_page(service_info, operation, base_url)

          conn
          |> put_resp_content_type("text/html")
          |> send_content(200, html_content)
      end
    rescue
      error ->
        Logger.error("Operation form generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("text/html")
        |> send_content(500, generate_error_page("Form generation failed"))
    end
  end

  defp handle_operation_form_request(conn, _config, _operation_name) do
    conn
    |> put_resp_content_type("text/html")
    |> send_content(404, generate_error_page("Form interface disabled"))
  end

  # Handle service overview requests
  defp handle_service_overview_request(conn, %{service: service, enable_forms: true} = config) do
    try do
      service_info = service.__soap_service__()
      base_url = get_base_url(conn, config)

      html_content = FormGenerator.generate_service_overview(service_info, base_url)

      conn
      |> put_resp_content_type("text/html")
      |> send_content(200, html_content)
    rescue
      error ->
        Logger.error("Service overview generation failed: #{inspect(error)}")

        conn
        |> put_resp_content_type("text/html")
        |> send_content(500, generate_error_page("Service overview generation failed"))
    end
  end

  defp handle_service_overview_request(conn, _config) do
    # If forms are disabled, redirect to WSDL
    redirect_to_wsdl(conn)
  end

  # Handle SOAP requests (1.1 and 1.2). `hint` comes from the path /
  # Content-Type; once the envelope is parsed its namespace is
  # authoritative for the response version.
  defp handle_soap_request(conn, config, hint) do
    with {:ok, body} <- read_request_body(conn, config.max_body_size),
         {:ok, parsed_request} <- RequestParser.parse(body) do
      dispatch_soap_request(conn, config, parsed_request)
    else
      {:error, :body_too_large} ->
        send_fault(conn, 413, "Client", "Request body too large", hint)

      {:error, reason} ->
        Logger.warning("SOAP request failed: #{inspect(reason)}")
        send_fault(conn, 400, "Client", "Invalid SOAP request", hint)
    end
  end

  defp dispatch_soap_request(conn, config, parsed_request) do
    version = parsed_request.soap_version

    if config.debug do
      Logger.debug("Debug request to #{conn.request_path}: #{inspect(parsed_request)}")
    end

    if config.fault_injection_rate > 0 && :rand.uniform() < config.fault_injection_rate do
      conn
      |> put_resp_content_type("application/soap+xml")
      |> send_content(
        500,
        ResponseBuilder.build_fault(
          FaultCodes.temporary_failure("Simulated transient failure"),
          soap_version: version
        )
      )
    else
      dispatch_soap_with(conn, config, parsed_request, version)
    end
  end

  defp dispatch_soap_with(conn, config, parsed_request, version) do
    with {:ok, operation_name} <- extract_operation_name(parsed_request),
         :ok <- check_addressing(parsed_request, config),
         {:ok, decrypted_request} <- decrypt_encrypted_body(parsed_request, config),
         :ok <- check_understood_headers(decrypted_request, config),
         {:ok, operation_info} <- get_operation_info(config.service, operation_name),
         {:ok, validated_params} <-
           validate_and_extract_params(decrypted_request, operation_info, config),
         :ok <-
           verify_request_signature(decrypted_request, config, operation_name, validated_params),
         :ok <- verify_request_jwt(decrypted_request, config),
         :ok <- verify_request_saml(decrypted_request, config),
         :ok <- verify_request_wstrust(decrypted_request, config),
         {:ok, result} <-
           call_operation_cached(config, operation_name, validated_params) do
      if match?({:stream, _}, result) do
        {:stream, items} = result
        send_stream_response(conn, items, operation_info, version)
      else
        response_xml =
          ResponseBuilder.build_response(result, operation_info, soap_version: version)

        conn
        |> put_resp_content_type(ResponseBuilder.content_type(version))
        |> send_content(200, response_xml)
      end
    else
      {:error, {:soap_fault, fault}} ->
        conn
        |> put_resp_content_type(ResponseBuilder.content_type(version))
        |> send_content(500, ResponseBuilder.build_fault(fault, soap_version: version))

      {:error, reason} ->
        Logger.warning("SOAP request failed: #{inspect(reason)}")
        send_fault(conn, 400, "Client", "Invalid SOAP request", version)
    end
  end

  # Streaming ("gRPC-style") responses: the operation handler returns
  # {:stream, items} and each item is sent as its own chunked SOAP
  # response envelope as it is produced.
  defp resolve_tenant(config, conn) do
    tenant = Map.get(conn.query_params, "tenant")

    case tenant && Map.get(config.tenants, tenant) do
      nil ->
        config

      tenant_service ->
        %{config | service: tenant_service}
    end
  end

  defp check_addressing(_parsed_request, %{require_addressing: false}) do
    :ok
  end

  defp check_addressing(parsed_request, config) do
    if config.require_addressing do
      Lather.Wsdl.Addressing.validate(parsed_request[:headers] || [])
    else
      :ok
    end
  end

  defp send_stream_response(conn, items, operation_info, version) do
    conn =
      conn
      |> put_resp_content_type(ResponseBuilder.content_type(version))
      |> Plug.Conn.send_chunked(200)

    Enum.reduce(items, conn, fn item, acc_conn ->
      envelope =
        ResponseBuilder.build_response({:ok, item}, operation_info, soap_version: version)

      case Plug.Conn.chunk(acc_conn, envelope) do
        {:ok, c} -> c
        {:error, _} -> acc_conn
      end
    end)
  end

  # SOAP 1.1/1.2 mustUnderstand semantics: when a header carries
  # mustUnderstand="1" or "true" and the service declares which headers it
  # understands via the :understood_headers option, unknown headers must
  # produce a NotUnderstood fault. A nil option means "understand everything".
  defp check_understood_headers(
         _parsed_request,
         %{understood_headers: nil, soap_roles: nil}
       ),
       do: :ok

  defp check_understood_headers(parsed_request, config) do
    understood = config.understood_headers
    roles = config.soap_roles

    Enum.reduce_while(parsed_request[:headers] || [], :ok, fn {name, content}, _acc ->
      cond do
        not must_understand?(content) ->
          {:cont, :ok}

        not header_understood?(name, content, understood) ->
          fault = %{
            fault_code: "soap:NotUnderstood",
            fault_string: "Cannot process header '#{name}' marked with mustUnderstand"
          }

          {:halt, {:error, {:soap_fault, fault}}}

        not role_understood?(content, roles) ->
          fault = %{
            fault_code: "soap:NotUnderstood",
            fault_string: "Cannot process header '#{name}' with unrecognized role"
          }

          {:halt, {:error, {:soap_fault, fault}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp must_understand?(content) when is_map(content) do
    Enum.any?(content, fn {key, value} ->
      Elements.local_name(key) == "mustUnderstand" and value in ["1", "true"]
    end)
  end

  defp must_understand?(_), do: false

  defp header_understood?(name, content, understood) do
    namespace =
      case content do
        map when is_map(map) -> map["xmlns"] || map["@xmlns"] || map["soap:xmlns"]
        _ -> nil
      end

    understood == nil || Enum.any?(understood, &(&1 == name or &1 == namespace))
  end

  # SOAP 1.2 headers may carry a `role` attribute (SOAP 1.1 used `actor`).
  # When the server declares `:soap_roles`, a mustUnderstand header whose
  # role is not in that list (and is not the default power role) produces
  # a NotUnderstood fault.
  defp role_understood?(_, nil), do: true

  defp role_understood?(content, roles) do
    role =
      if is_map(content) do
        Enum.find_value(content, fn {key, value} ->
          if Elements.local_name(key) in ["role", "actor"], do: value
        end)
      end

    role == nil or
      role == "http://www.w3.org/2003/05/soap/power" or
      Enum.member?(roles, role)
  end

  defp verify_request_signature(_parsed_request, %{verify_signature: nil}, _operation, _params) do
    :ok
  end

  defp verify_request_signature(parsed_request, config, operation_name, params) do
    case Signature.verify(
           parsed_request[:headers] || [],
           operation_name,
           params,
           config.verify_signature
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        fault = %{
          fault_code: "Client",
          fault_string: "WS-Security signature verification failed: #{reason}"
        }

        {:error, {:soap_fault, fault}}
    end
  end

  defp verify_request_jwt(_parsed_request, %{jwt_secret: nil}) do
    :ok
  end

  defp verify_request_jwt(parsed_request, config) do
    token = JWT.extract(parsed_request[:headers] || [])

    case token && JWT.verify(token, config.jwt_secret) do
      {:ok, _claims} ->
        :ok

      nil ->
        {:error, {:soap_fault, %{fault_code: "Client", fault_string: "Missing JWT token"}}}

      {:error, reason} ->
        {:error,
         {:soap_fault,
          %{fault_code: "Client", fault_string: "JWT verification failed: #{reason}"}}}
    end
  end

  defp decrypt_encrypted_body(parsed_request, %{encryption_key: nil}) do
    {:ok, parsed_request}
  end

  defp decrypt_encrypted_body(parsed_request, config) do
    params = Map.get(parsed_request, :params)

    if XMLEncryption.encrypted?(params) do
      encrypted =
        Enum.find_value(params, fn {key, value} ->
          if Elements.local_name(to_string(key)) == "EncryptedData", do: value
        end)

      case XMLEncryption.decrypt(encrypted, config.encryption_key) do
        {:ok, decoded} when is_map(decoded) ->
          {:ok, Map.put(parsed_request, :params, decoded)}

        _ ->
          {:error, {:soap_fault, %{fault_code: "Client", fault_string: "XML decryption failed"}}}
      end
    else
      {:ok, parsed_request}
    end
  end

  defp verify_request_saml(_parsed_request, %{saml_secret: nil}) do
    :ok
  end

  defp verify_request_saml(parsed_request, config) do
    assertion = SAML.extract(parsed_request[:headers] || [])

    cond do
      assertion == nil ->
        {:error, {:soap_fault, %{fault_code: "Client", fault_string: "Missing SAML assertion"}}}

      match?({:ok, _}, SAML.verify(assertion, config.saml_secret)) ->
        :ok

      true ->
        {:error, {:soap_fault, %{fault_code: "Client", fault_string: "SAML verification failed"}}}
    end
  end

  defp verify_request_wstrust(_parsed_request, %{wstrust_secret: nil}) do
    :ok
  end

  defp verify_request_wstrust(parsed_request, config) do
    token = WSTrust.extract(parsed_request[:headers] || [])

    cond do
      token == nil ->
        {:error, {:soap_fault, %{fault_code: "Client", fault_string: "Missing WS-Trust token"}}}

      match?({:ok, _}, WSTrust.validate_token(token, config.wstrust_secret)) ->
        :ok

      true ->
        {:error, {:soap_fault, %{fault_code: "Client", fault_string: "WS-Trust token invalid"}}}
    end
  end

  defp send_fault(conn, status, code, message, version) do
    conn
    |> put_resp_content_type(ResponseBuilder.content_type(version))
    |> send_content(status, soap_fault_xml(code, message, version))
  end

  # Sends a response, gzip-compressing it when the client accepts gzip and
  # the body is large enough to benefit.
  defp send_content(conn, status, body) do
    if accepts_gzip?(conn) and byte_size(body) >= @min_compress_size do
      conn
      |> put_resp_header("content-encoding", "gzip")
      |> Plug.Conn.send_resp(status, :zlib.gzip(body))
    else
      Plug.Conn.send_resp(conn, status, body)
    end
  end

  defp accepts_gzip?(conn) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.any?(fn value -> String.contains?(String.downcase(value), "gzip") end)
  end

  # Handle JSON/REST requests
  defp handle_json_request(conn, config) do
    # Extract operation from path or query parameters
    operation_name = extract_json_operation_name(conn)

    with {:ok, body} <- read_request_body(conn, config.max_body_size),
         {:ok, json_params} <- decode_json_body(body),
         {:ok, operation_info} <- get_json_operation_info(config.service, operation_name),
         {:ok, validated_params} <- validate_json_params(json_params, operation_info, config),
         {:ok, result} <-
           call_operation_cached(config, operation_info.name, validated_params) do
      # Format JSON response
      json_response = format_json_response(result, operation_info)

      conn
      |> put_resp_content_type("application/json")
      |> send_content(200, encode_json(json_response))
    else
      {:error, :body_too_large} ->
        error_response = %{
          error: %{
            code: "RequestEntityTooLarge",
            message: "Request body too large",
            detail: nil
          }
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_content(413, encode_json(error_response))

      {:error, {:soap_fault, fault}} ->
        error_response = %{
          error: %{
            code: fault.fault_code || "ServerError",
            message: fault.fault_string || "Operation failed",
            detail: Map.get(fault, :detail)
          }
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_content(
          if(fault.fault_code == "Client", do: 400, else: 500),
          encode_json(error_response)
        )

      {:error, reason} ->
        Logger.warning("JSON request failed: #{inspect(reason)}")

        error_response = %{
          error: %{
            code: "InvalidRequest",
            message: "Invalid JSON request",
            detail: inspect(reason)
          }
        }

        conn
        |> put_resp_content_type("application/json")
        |> send_content(400, encode_json(error_response))
    end
  end

  # Handle unsupported requests
  defp handle_unsupported_request(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_content(405, generate_error_page("Method not allowed"))
  end

  # Helper functions

  defp get_base_url(conn, config) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = conn.host
    port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"

    "#{scheme}://#{host}#{port}#{config.base_path}/"
  end

  defp find_operation(service_info, operation_name) do
    Enum.find(service_info.operations, &(&1.name == operation_name))
  end

  defp read_request_body(conn, max_size) do
    case read_full_body(conn, max_size) do
      {:ok, body} ->
        case get_req_header(conn, "content-encoding") do
          ["gzip" | _] ->
            try do
              decompressed = :zlib.gunzip(body)

              if byte_size(decompressed) > max_size do
                {:error, :body_too_large}
              else
                {:ok, decompressed}
              end
            rescue
              _ -> {:error, :invalid_compressed_body}
            end

          _ ->
            {:ok, body}
        end

      {:error, _} = error ->
        error
    end
  end

  defp read_full_body(conn, max_size, body \\ "") do
    if byte_size(body) > max_size do
      {:error, :body_too_large}
    else
      case Plug.Conn.read_body(conn) do
        {:ok, chunk, _conn} ->
          new_body = body <> chunk

          if byte_size(new_body) > max_size do
            {:error, :body_too_large}
          else
            {:ok, new_body}
          end

        {:more, chunk, conn} ->
          new_body = body <> chunk

          if byte_size(new_body) > max_size do
            {:error, :body_too_large}
          else
            read_full_body(conn, max_size, new_body)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_operation_name(parsed_request) do
    # RequestParser returns %{operation: name, params: params}
    case parsed_request do
      %{operation: operation_name} when is_binary(operation_name) ->
        {:ok, operation_name}

      _ ->
        {:error, :operation_not_found}
    end
  end

  defp extract_json_operation_name(conn) do
    # Extract from path like /api/getUserInfo or from query params
    case String.split(conn.request_path, "/") do
      segments when segments != [] ->
        segments |> List.last() |> String.replace(~r/[^a-zA-Z0-9]/, "")

      _ ->
        "UnknownOperation"
    end
  end

  defp get_operation_info(service_module, operation_name) do
    case service_module.__soap_operation__(operation_name) do
      nil ->
        suggestion = suggest_operation(operation_name, service_module.__soap_operations__())

        detail =
          if suggestion do
            %{suggestion: suggestion}
          else
            nil
          end

        {:error,
         {:soap_fault,
          %{
            fault_code: "Client",
            fault_string:
              "Operation '#{operation_name}' not found" <>
                if(suggestion, do: ". Did you mean '#{suggestion}'?", else: ""),
            detail: detail
          }}}

      operation_info ->
        {:ok, operation_info}
    end
  end

  defp suggest_operation(name, operations) do
    target = String.downcase(name)

    operations
    |> Enum.map(fn op ->
      {op.name, levenshtein(target, String.downcase(op.name))}
    end)
    |> Enum.sort_by(fn pair ->
      elem(pair, 1)
    end)
    |> case do
      [{best, distance} | _rest] when distance < max(byte_size(target), 4) -> best
      _other -> nil
    end
  end

  defp levenshtein(a, b) do
    a_chars = String.to_charlist(a)
    b_chars = String.to_charlist(b)

    final_row =
      a_chars
      |> Enum.with_index()
      |> Enum.reduce(Enum.to_list(0..length(b_chars)), fn {a_char, i}, prev_row ->
        Enum.reduce(Enum.with_index(b_chars), [i + 1], fn {b_char, j}, acc ->
          cost = if a_char == b_char, do: 0, else: 1

          acc ++
            [
              min(
                min(Enum.at(acc, j) + 1, Enum.at(prev_row, j + 1) + 1),
                Enum.at(prev_row, j) + cost
              )
            ]
        end)
      end)

    List.last(final_row)
  end

  defp get_json_operation_info(service_module, operation_name) do
    canonical_name =
      Enum.find_value(service_module.__soap_operations__(), fn operation ->
        if String.downcase(operation.name) == String.downcase(operation_name), do: operation.name
      end)

    get_operation_info(service_module, canonical_name || operation_name)
  end

  defp validate_and_extract_params(parsed_request, operation_info, config) do
    # Extract parameters from SOAP body
    case extract_soap_parameters(parsed_request) do
      {:ok, params} ->
        if config.validate_params do
          validate_operation_params(params, operation_info)
        else
          {:ok, params}
        end

      error ->
        error
    end
  end

  defp extract_soap_parameters(parsed_request) do
    # RequestParser returns %{operation: name, params: params}
    case parsed_request do
      %{params: params} when is_map(params) ->
        {:ok, params}

      %{params: _} ->
        {:ok, %{}}

      _ ->
        {:error, :invalid_soap_body}
    end
  end

  defp validate_operation_params(params, operation_info) do
    # Use the service module's validation if available
    with :ok <- Lather.Server.validate_required_params(params, operation_info),
         {:ok, validated_params} <- Lather.Server.validate_param_types(params, operation_info) do
      {:ok, validated_params}
    else
      {:error, reason} -> {:error, {:soap_fault, %{fault_code: "Client", fault_string: reason}}}
    end
  end

  # Decode JSON body
  defp decode_json_body(body) do
    case decode_json(body) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  # JSON encoding with graceful fallback
  defp encode_json(data) do
    if @jason_available do
      apply(Jason, :encode!, [data])
    else
      # Fallback to basic JSON-like string representation
      inspect(data, pretty: true)
    end
  end

  # JSON decoding with graceful fallback
  defp decode_json(body) do
    if @jason_available do
      apply(Jason, :decode, [body])
    else
      {:error, :jason_not_available}
    end
  end

  defp validate_json_params(params, operation_info, config) do
    if config.validate_params do
      validate_operation_params(params, operation_info)
    else
      {:ok, params}
    end
  end

  defp call_operation_cached(%{result_cache: nil} = config, operation_name, params) do
    call_operation(config.service, operation_name, params)
  end

  defp call_operation_cached(config, operation_name, params) do
    case ResultCache.get(config.result_cache, config.service, operation_name, params) do
      {:hit, result} ->
        {:ok, result}

      :miss ->
        case call_operation(config.service, operation_name, params) do
          {:ok, result} ->
            ResultCache.put(config.result_cache, config.service, operation_name, params, result)
            {:ok, result}

          error ->
            error
        end
    end
  end

  defp call_operation(service_module, operation_name, params) do
    function_name = String.to_atom(Macro.underscore(operation_name))
    operation = service_module.__soap_operation__(operation_name) || %{}

    case check_operation_condition(operation, params) do
      :ok ->
        if function_exported?(service_module, function_name, 1) do
          try do
            normalize_operation_result(
              apply(service_module, function_name, [params]),
              operation
            )
          rescue
            error ->
              {:error,
               {:soap_fault,
                %{fault_code: "Server", fault_string: "Operation failed: #{inspect(error)}"}}}
          end
        else
          {:error,
           {:soap_fault,
            %{fault_code: "Client", fault_string: "Operation '#{operation_name}' not implemented"}}}
        end

      {:error, fault} ->
        {:error, fault}
    end
  end

  defp check_operation_condition(operation, params) do
    case operation[:condition] do
      nil ->
        :ok

      condition when is_function(condition, 1) ->
        if condition.(params) do
          :ok
        else
          {:error,
           {:soap_fault,
            %{
              fault_code: "Client",
              subcode: "BadRequest",
              fault_string: "Precondition failed for operation #{operation[:name]}"
            }}}
        end

      _ ->
        :ok
    end
  end

  defp normalize_operation_result(raw, operation) do
    mapping =
      Enum.find(operation[:errors] || [], fn error_def ->
        error_def[:match] == raw || error_def[:match] == :any
      end)

    if mapping do
      {:error,
       {:soap_fault,
        %{
          fault_code: mapping[:code],
          subcode: mapping[:subcode],
          fault_string: mapping[:message]
        }}}
    else
      case raw do
        {:ok, result} ->
          {:ok, result}

        {:soap_fault, fault} ->
          {:error, {:soap_fault, fault}}

        {:error, reason} ->
          {:error, {:soap_fault, %{fault_code: "Server", fault_string: to_string(reason)}}}

        result ->
          {:ok, result}
      end
    end
  end

  defp format_json_response(result, _operation_info) do
    case result do
      {:ok, data} -> %{success: true, data: data}
      {:error, reason} -> %{success: false, error: reason}
      data -> %{success: true, data: data}
    end
  end

  defp soap_fault_xml(fault_code, fault_string, version \\ :v1_1) do
    ResponseBuilder.build_fault(%{fault_code: fault_code, fault_string: fault_string},
      soap_version: version
    )
  end

  defp generate_error_page(message) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Error</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 50px; }
            .error { background: #ffebee; border: 1px solid #f44336; padding: 20px; border-radius: 4px; }
        </style>
    </head>
    <body>
        <div class="error">
            <h2>Error</h2>
            <p>#{message}</p>
            <p><a href="?wsdl">View WSDL</a></p>
        </div>
    </body>
    </html>
    """
  end

  defp accessible_html(title, body_html, lang) do
    """
    <!DOCTYPE html>
    <html lang="#{lang}">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{title}</title>
        <style>
          body { font-family: system-ui, Arial, sans-serif; margin: 2rem; }
          a:focus, button:focus { outline: 3px solid #1a73e8; }
          .skip-link { display: none; }
          .skip-link:focus { display: block; }
          table { border-collapse: collapse; }
          th, td { border: 1px solid #ccc; padding: 8px; }
          @media (prefers-contrast: high) {
            body { color: #000; background: #fff; }
            th, td { border: 2px solid #000; }
          }
          @media (max-width: 600px) {
            body { margin: 1rem; }
            table { width: 100%; }
          }
        </style>
      </head>
      <body>
        <a class="skip-link" href="#main">Skip to main content</a>
        <main id="main">
          #{body_html}
        </main>
      </body>
    </html>
    """
  end

  defp redirect_to_wsdl(conn) do
    conn
    |> put_resp_header("location", "?wsdl")
    |> send_content(302, "")
  end
end
