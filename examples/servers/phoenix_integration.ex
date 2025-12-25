defmodule Examples.Servers.PhoenixIntegration do
  @moduledoc """
  Comprehensive Phoenix integration examples for Lather SOAP services.

  This file demonstrates multiple approaches to integrating Lather SOAP services
  with Phoenix applications, including:

  1. Basic Plug integration - Simple, direct SOAP endpoint
  2. Enhanced Plug integration - Multi-protocol with web forms
  3. Phoenix Controller approach - Full control over request handling
  4. Application supervision - Proper startup configuration

  ## When to Use Each Approach

  ### Basic Plug (Lather.Server.Plug)
  - Simple SOAP-only services
  - Legacy system integration
  - When you need minimal overhead
  - Single-protocol (SOAP 1.1) endpoints

  ### Enhanced Plug (Lather.Server.EnhancedPlug)
  - Modern services needing multiple protocols (SOAP 1.1, 1.2, JSON)
  - When you want built-in web forms for testing
  - Services with interactive documentation needs
  - .NET Web Service-style interfaces

  ### Phoenix Controller
  - Maximum control over request/response handling
  - Custom authentication/authorization logic
  - Complex middleware requirements
  - When integrating with existing Phoenix pipelines

  ## Quick Start

  1. Add Lather to your dependencies in mix.exs
  2. Create your SOAP service module (see OrderService below)
  3. Add routes to your Phoenix router
  4. Configure application supervision for HTTP client
  5. Add any necessary config settings

  """

  # ===========================================================================
  # SECTION 1: SOAP Service Module
  # ===========================================================================

  defmodule OrderService do
    @moduledoc """
    Example SOAP service for order management.

    This service demonstrates a complete SOAP service implementation with:
    - Multiple operations
    - Complex types
    - Input validation
    - Error handling with SOAP faults
    """

    use Lather.Server

    @namespace "http://example.com/orders"
    @service_name "OrderService"

    # Define complex types
    soap_type "Order" do
      description "Order information"

      element "orderId", :string, required: true, description: "Unique order identifier"
      element "customerId", :string, required: true, description: "Customer ID"
      element "items", "OrderItem", max_occurs: "unbounded", description: "Order items"
      element "totalAmount", :decimal, required: true, description: "Total order amount"
      element "status", :string, required: true, description: "Order status"
      element "createdAt", :dateTime, required: true, description: "Order creation timestamp"
    end

    soap_type "OrderItem" do
      description "Individual order item"

      element "productId", :string, required: true, description: "Product ID"
      element "productName", :string, required: true, description: "Product name"
      element "quantity", :int, required: true, description: "Quantity ordered"
      element "unitPrice", :decimal, required: true, description: "Price per unit"
    end

    soap_type "CreateOrderRequest" do
      description "Request to create a new order"

      element "customerId", :string, required: true, description: "Customer placing the order"
      element "items", "OrderItem", max_occurs: "unbounded", description: "Items to order"
    end

    # GetOrder operation
    soap_operation "GetOrder" do
      description "Retrieves an order by its ID"

      input do
        parameter "orderId", :string, required: true, description: "Order ID to retrieve"
      end

      output do
        parameter "order", "Order", description: "Order information"
      end

      soap_action "http://example.com/orders/GetOrder"
    end

    def get_order(%{"orderId" => order_id}) do
      # In a real application, this would query a database
      case fetch_order_from_database(order_id) do
        {:ok, order} ->
          {:ok, %{"order" => order}}

        {:error, :not_found} ->
          soap_fault("Client", "Order not found", %{orderId: order_id})

        {:error, reason} ->
          soap_fault("Server", "Failed to retrieve order: #{reason}")
      end
    end

    # CreateOrder operation
    soap_operation "CreateOrder" do
      description "Creates a new order"

      input do
        parameter "request", "CreateOrderRequest", required: true, description: "Order details"
      end

      output do
        parameter "orderId", :string, description: "ID of the created order"
        parameter "order", "Order", description: "Created order details"
      end

      soap_action "http://example.com/orders/CreateOrder"
    end

    def create_order(%{"request" => request}) do
      with {:ok, validated_request} <- validate_order_request(request),
           {:ok, order} <- persist_order(validated_request) do
        {:ok, %{
          "orderId" => order["orderId"],
          "order" => order
        }}
      else
        {:error, validation_errors} when is_list(validation_errors) ->
          soap_fault("Client", "Validation failed", %{errors: validation_errors})

        {:error, reason} ->
          soap_fault("Server", "Failed to create order: #{reason}")
      end
    end

    # UpdateOrderStatus operation
    soap_operation "UpdateOrderStatus" do
      description "Updates the status of an existing order"

      input do
        parameter "orderId", :string, required: true, description: "Order ID"
        parameter "status", :string, required: true, description: "New status"
      end

      output do
        parameter "success", :boolean, description: "Whether update succeeded"
        parameter "order", "Order", description: "Updated order details"
      end

      soap_action "http://example.com/orders/UpdateOrderStatus"
    end

    def update_order_status(%{"orderId" => order_id, "status" => status}) do
      valid_statuses = ["pending", "processing", "shipped", "delivered", "cancelled"]

      if status in valid_statuses do
        case update_order_in_database(order_id, status) do
          {:ok, order} ->
            {:ok, %{"success" => true, "order" => order}}

          {:error, :not_found} ->
            soap_fault("Client", "Order not found", %{orderId: order_id})

          {:error, reason} ->
            soap_fault("Server", "Failed to update order: #{reason}")
        end
      else
        soap_fault("Client", "Invalid status", %{
          provided: status,
          valid_statuses: valid_statuses
        })
      end
    end

    # ListOrders operation
    soap_operation "ListOrders" do
      description "Lists orders with optional filtering"

      input do
        parameter "customerId", :string, required: false, description: "Filter by customer"
        parameter "status", :string, required: false, description: "Filter by status"
        parameter "page", :int, required: false, description: "Page number (default: 1)"
        parameter "pageSize", :int, required: false, description: "Items per page (default: 20)"
      end

      output do
        parameter "orders", "Order", max_occurs: "unbounded", description: "List of orders"
        parameter "totalCount", :int, description: "Total matching orders"
        parameter "page", :int, description: "Current page"
        parameter "pageSize", :int, description: "Items per page"
      end

      soap_action "http://example.com/orders/ListOrders"
    end

    def list_orders(params) do
      page = parse_int(params["page"], 1)
      page_size = parse_int(params["pageSize"], 20)
      filters = Map.take(params, ["customerId", "status"])

      case query_orders(filters, page, page_size) do
        {:ok, orders, total_count} ->
          {:ok, %{
            "orders" => orders,
            "totalCount" => total_count,
            "page" => page,
            "pageSize" => page_size
          }}

        {:error, reason} ->
          soap_fault("Server", "Failed to list orders: #{reason}")
      end
    end

    # Helper functions (mock implementations for demonstration)

    defp fetch_order_from_database("ORD-123") do
      {:ok, %{
        "orderId" => "ORD-123",
        "customerId" => "CUST-001",
        "items" => [
          %{
            "productId" => "PROD-001",
            "productName" => "Widget",
            "quantity" => 5,
            "unitPrice" => "19.99"
          }
        ],
        "totalAmount" => "99.95",
        "status" => "processing",
        "createdAt" => "2024-10-30T10:00:00Z"
      }}
    end
    defp fetch_order_from_database(_), do: {:error, :not_found}

    defp validate_order_request(request) do
      errors = []
      errors = if request["customerId"], do: errors, else: ["customerId is required" | errors]
      errors = if request["items"] && length(request["items"]) > 0, do: errors, else: ["at least one item is required" | errors]

      case errors do
        [] -> {:ok, request}
        _ -> {:error, errors}
      end
    end

    defp persist_order(request) do
      order_id = "ORD-#{:rand.uniform(99999)}"
      {:ok, %{
        "orderId" => order_id,
        "customerId" => request["customerId"],
        "items" => request["items"],
        "totalAmount" => calculate_total(request["items"]),
        "status" => "pending",
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      }}
    end

    defp update_order_in_database(order_id, status) do
      case fetch_order_from_database(order_id) do
        {:ok, order} -> {:ok, Map.put(order, "status", status)}
        error -> error
      end
    end

    defp query_orders(_filters, _page, _page_size) do
      # Mock implementation
      {:ok, [], 0}
    end

    defp calculate_total(items) when is_list(items) do
      Enum.reduce(items, Decimal.new("0"), fn item, acc ->
        quantity = item["quantity"] || 0
        unit_price = Decimal.new(item["unitPrice"] || "0")
        Decimal.add(acc, Decimal.mult(unit_price, quantity))
      end)
      |> Decimal.to_string()
    end
    defp calculate_total(_), do: "0"

    defp parse_int(nil, default), do: default
    defp parse_int(value, default) when is_binary(value) do
      case Integer.parse(value) do
        {int, _} -> int
        :error -> default
      end
    end
    defp parse_int(value, _default) when is_integer(value), do: value
  end

  # ===========================================================================
  # SECTION 2: Phoenix Router Configuration
  # ===========================================================================

  defmodule MyAppWeb.Router do
    @moduledoc """
    Example Phoenix router configuration showing all integration approaches.

    This demonstrates how to set up routes for:
    - Basic Plug integration
    - Enhanced Plug integration
    - Controller-based integration
    """

    use Phoenix.Router

    import Plug.Conn
    import Phoenix.Controller

    # Pipeline for SOAP endpoints - minimal processing
    pipeline :soap do
      plug :accepts, ["xml"]
      # Note: Don't use :fetch_session or CSRF protection for SOAP
    end

    # Pipeline for API endpoints (used with Enhanced Plug JSON support)
    pipeline :api do
      plug :accepts, ["json", "xml"]
    end

    # Pipeline for web forms (Enhanced Plug service overview)
    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :protect_from_forgery
      plug :put_secure_browser_headers
    end

    # =========================================================================
    # Approach 1: Basic Plug Integration
    # =========================================================================
    # Use this for simple SOAP-only services with minimal configuration.
    #
    # Features:
    # - WSDL generation at GET /soap/orders?wsdl
    # - SOAP requests at POST /soap/orders
    # - Parameter validation
    # - Standard SOAP fault responses

    scope "/soap", MyAppWeb do
      pipe_through :soap

      # Basic SOAP endpoint - simple and direct
      post "/orders", Lather.Server.Plug, service: Examples.Servers.PhoenixIntegration.OrderService

      # You can also handle GET for WSDL requests
      get "/orders", Lather.Server.Plug, service: Examples.Servers.PhoenixIntegration.OrderService

      # Multiple services can be mounted at different paths
      # post "/users", Lather.Server.Plug, service: MyApp.UserService
      # post "/inventory", Lather.Server.Plug, service: MyApp.InventoryService
    end

    # =========================================================================
    # Approach 2: Enhanced Plug Integration
    # =========================================================================
    # Use this for services that need:
    # - Multi-protocol support (SOAP 1.1, 1.2, JSON)
    # - Interactive web forms for testing
    # - Service documentation pages
    #
    # URL Patterns:
    # - GET /api/orders          -> Service overview with operations list
    # - GET /api/orders?wsdl     -> Standard WSDL
    # - GET /api/orders?wsdl&enhanced=true -> Multi-protocol WSDL
    # - GET /api/orders?op=GetOrder -> Interactive form for GetOrder
    # - POST /api/orders         -> SOAP 1.1 endpoint
    # - POST /api/orders/v1.2    -> SOAP 1.2 endpoint
    # - POST /api/orders/api/*   -> JSON/REST endpoint

    scope "/api", MyAppWeb do
      # Note: We use match :* to handle both GET (forms, WSDL) and POST (SOAP)
      pipe_through :api

      # Enhanced endpoint with all features
      match :*, "/orders", Lather.Server.EnhancedPlug,
        service: Examples.Servers.PhoenixIntegration.OrderService,
        base_path: "/api/orders",
        enable_forms: true,
        enable_json: true

      # Wildcard route for sub-paths (v1.2, api, etc.)
      match :*, "/orders/*path", Lather.Server.EnhancedPlug,
        service: Examples.Servers.PhoenixIntegration.OrderService,
        base_path: "/api/orders",
        enable_forms: true,
        enable_json: true
    end

    # =========================================================================
    # Approach 3: Phoenix Controller Integration
    # =========================================================================
    # Use this when you need:
    # - Custom authentication/authorization
    # - Request logging or metrics
    # - Complex error handling
    # - Integration with existing Phoenix pipelines
    # - Access to Phoenix assigns and session

    scope "/services", MyAppWeb do
      pipe_through :soap

      # Route to a dedicated SOAP controller
      post "/orders", SOAPController, :handle_orders
      get "/orders", SOAPController, :handle_orders_wsdl

      # With path parameters for operation routing
      post "/orders/:operation", SOAPController, :handle_orders
    end
  end

  # ===========================================================================
  # SECTION 3: Phoenix Controller Implementation
  # ===========================================================================

  defmodule MyAppWeb.SOAPController do
    @moduledoc """
    Phoenix controller for handling SOAP requests with full control.

    This approach gives you maximum flexibility for:
    - Custom authentication (API keys, OAuth, etc.)
    - Request/response logging
    - Metrics collection
    - Error handling customization
    - Integration with Phoenix assigns

    Use Lather.Server.Handler.handle_request/6 for the actual SOAP processing.
    """

    use Phoenix.Controller

    require Logger

    # Import the service module
    alias Examples.Servers.PhoenixIntegration.OrderService

    @doc """
    Handles SOAP requests for the Order service.

    This action demonstrates:
    - Reading raw request body
    - Custom authentication
    - Request logging
    - Using Lather.Server.Handler for SOAP processing
    - Custom response formatting
    """
    def handle_orders(conn, _params) do
      # Step 1: Read the raw request body
      # Note: You may need a custom Plug to cache the raw body
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      # Step 2: Perform custom authentication (optional)
      case authenticate_request(conn) do
        {:ok, user_context} ->
          # Step 3: Log the request (optional)
          log_soap_request(conn, body)

          # Step 4: Build options for the handler
          opts = [
            validate_params: true,
            generate_wsdl: true,
            base_url: build_base_url(conn)
          ]

          # Step 5: Process the SOAP request using Lather.Server.Handler
          result = Lather.Server.Handler.handle_request(
            conn.method,
            conn.request_path,
            format_headers(conn.req_headers),
            body,
            OrderService,
            opts
          )

          # Step 6: Send the response
          case result do
            {:ok, status, headers, response_body} ->
              conn
              |> put_status(status)
              |> put_response_headers(headers)
              |> put_resp_content_type("text/xml")
              |> text(response_body)

            {:error, status, headers, response_body} ->
              # Log errors for monitoring
              Logger.warning("SOAP request failed with status #{status}")

              conn
              |> put_status(status)
              |> put_response_headers(headers)
              |> put_resp_content_type("text/xml")
              |> text(response_body)
          end

        {:error, :unauthorized} ->
          conn
          |> put_status(401)
          |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
          |> put_resp_content_type("text/xml")
          |> text(soap_unauthorized_fault())
      end
    end

    @doc """
    Handles WSDL requests for the Order service.
    """
    def handle_orders_wsdl(conn, _params) do
      opts = [
        validate_params: true,
        generate_wsdl: true,
        base_url: build_base_url(conn)
      ]

      # Use "GET" method and append ?wsdl to trigger WSDL generation
      result = Lather.Server.Handler.handle_request(
        "GET",
        conn.request_path <> "?wsdl",
        format_headers(conn.req_headers),
        "",
        OrderService,
        opts
      )

      case result do
        {:ok, status, headers, response_body} ->
          conn
          |> put_status(status)
          |> put_response_headers(headers)
          |> put_resp_content_type("text/xml")
          |> text(response_body)

        {:error, status, headers, response_body} ->
          conn
          |> put_status(status)
          |> put_response_headers(headers)
          |> put_resp_content_type("text/xml")
          |> text(response_body)
      end
    end

    # Private helper functions

    defp authenticate_request(conn) do
      # Example: Check for API key in header
      case get_req_header(conn, "x-api-key") do
        [api_key] ->
          if valid_api_key?(api_key) do
            {:ok, %{api_key: api_key}}
          else
            {:error, :unauthorized}
          end

        [] ->
          # Check for Basic Auth as fallback
          case get_req_header(conn, "authorization") do
            ["Basic " <> credentials] ->
              validate_basic_auth(credentials)

            _ ->
              # Allow unauthenticated requests (adjust based on requirements)
              {:ok, %{anonymous: true}}
          end
      end
    end

    defp valid_api_key?(api_key) do
      # In production, validate against database or config
      api_key == Application.get_env(:my_app, :soap_api_key, "demo-key")
    end

    defp validate_basic_auth(credentials) do
      case Base.decode64(credentials) do
        {:ok, decoded} ->
          case String.split(decoded, ":", parts: 2) do
            [username, password] ->
              if valid_credentials?(username, password) do
                {:ok, %{username: username}}
              else
                {:error, :unauthorized}
              end

            _ ->
              {:error, :unauthorized}
          end

        :error ->
          {:error, :unauthorized}
      end
    end

    defp valid_credentials?(username, password) do
      # In production, validate against database
      username == "soap_user" && password == "soap_password"
    end

    defp log_soap_request(conn, body) do
      # Extract SOAPAction header for logging
      soap_action = get_req_header(conn, "soapaction") |> List.first() || "unknown"

      Logger.info("SOAP Request",
        path: conn.request_path,
        soap_action: soap_action,
        content_length: byte_size(body),
        remote_ip: format_ip(conn.remote_ip)
      )
    end

    defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
    defp format_ip(ip), do: inspect(ip)

    defp build_base_url(conn) do
      scheme = if conn.scheme == :https, do: "https", else: "http"
      port = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
      "#{scheme}://#{conn.host}#{port}#{conn.request_path}"
    end

    defp format_headers(headers) do
      # Headers are already in the correct format for Handler
      headers
    end

    defp put_response_headers(conn, headers) do
      Enum.reduce(headers, conn, fn {key, value}, acc ->
        put_resp_header(acc, key, value)
      end)
    end

    defp soap_unauthorized_fault do
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Client</faultcode>
            <faultstring>Authentication required</faultstring>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """
    end
  end

  # ===========================================================================
  # SECTION 4: Body Reader Plug (Required for Controller Approach)
  # ===========================================================================

  defmodule MyAppWeb.Plugs.CacheRawBody do
    @moduledoc """
    Plug to cache the raw request body for SOAP processing.

    Phoenix's body readers consume the body stream, so we need to cache it
    if we want to read it multiple times or access the raw XML.

    ## Usage

    Add to your endpoint.ex before the Phoenix router:

        plug MyAppWeb.Plugs.CacheRawBody
        plug MyAppWeb.Router

    Or add to a specific pipeline in your router.
    """

    @behaviour Plug

    def init(opts), do: opts

    def call(conn, _opts) do
      case Plug.Conn.read_body(conn) do
        {:ok, body, conn} ->
          Plug.Conn.assign(conn, :raw_body, body)

        {:more, _partial_body, conn} ->
          # Handle chunked requests by reading all chunks
          {:ok, full_body, conn} = read_full_body(conn, "")
          Plug.Conn.assign(conn, :raw_body, full_body)

        {:error, _reason} ->
          conn
      end
    end

    defp read_full_body(conn, acc) do
      case Plug.Conn.read_body(conn) do
        {:ok, body, conn} -> {:ok, acc <> body, conn}
        {:more, body, conn} -> read_full_body(conn, acc <> body)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # ===========================================================================
  # SECTION 5: Application Supervision Setup
  # ===========================================================================

  defmodule MyApp.Application do
    @moduledoc """
    Example application module showing proper supervision tree setup.

    If your SOAP service acts as both a server AND client (calling other services),
    you need to start the Finch HTTP client pool.
    """

    use Application

    @impl true
    def start(_type, _args) do
      children = [
        # Start the Ecto repository (if using database)
        # MyApp.Repo,

        # Start the Telemetry supervisor
        MyAppWeb.Telemetry,

        # Start the PubSub system
        {Phoenix.PubSub, name: MyApp.PubSub},

        # Start Finch HTTP client for Lather SOAP client functionality
        # This is required if your service calls other SOAP services
        {Finch,
         name: MyApp.Finch,
         pools: %{
           # Default pool for general HTTP requests
           :default => [size: 10, count: 1],

           # Dedicated pool for specific SOAP endpoints (optional)
           "https://api.example.com" => [size: 25, count: 2, protocol: :http1],

           # Pool with custom timeouts for slow services
           "https://slow-service.example.com" => [
             size: 5,
             count: 1,
             conn_opts: [
               transport_opts: [timeout: 30_000]
             ]
           ]
         }},

        # Start the Phoenix endpoint (starts HTTP server)
        MyAppWeb.Endpoint
      ]

      opts = [strategy: :one_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)
    end

    @impl true
    def config_change(changed, _new, removed) do
      MyAppWeb.Endpoint.config_change(changed, removed)
      :ok
    end
  end

  # ===========================================================================
  # SECTION 6: Example config.exs Settings
  # ===========================================================================

  defmodule MyApp.Config do
    @moduledoc """
    Example configuration settings for config/config.exs and environment configs.

    Copy these settings to your appropriate config files.

    ## config/config.exs

        # Lather SOAP library configuration
        config :lather,
          # Default HTTP client (uses Finch)
          http_client: Lather.HTTP.FinchClient,
          finch_name: MyApp.Finch,

          # Default timeout for SOAP requests (milliseconds)
          request_timeout: 30_000,

          # Enable request/response logging (disable in production)
          debug_logging: false

        # SOAP service configuration
        config :my_app, :soap_services,
          # API key for authenticated endpoints
          api_key: System.get_env("SOAP_API_KEY"),

          # Basic auth credentials
          basic_auth: [
            username: System.get_env("SOAP_USERNAME"),
            password: System.get_env("SOAP_PASSWORD")
          ],

          # External service endpoints
          external_services: %{
            payment: "https://payment.example.com/soap",
            inventory: "https://inventory.example.com/soap"
          }

    ## config/dev.exs

        config :lather,
          debug_logging: true,
          request_timeout: 60_000  # Longer timeout for debugging

        config :my_app, :soap_services,
          api_key: "dev-api-key",
          basic_auth: [username: "dev_user", password: "dev_password"]

    ## config/prod.exs

        config :lather,
          debug_logging: false,
          request_timeout: 30_000

        config :my_app, :soap_services,
          # Use environment variables in production
          api_key: System.get_env("SOAP_API_KEY"),
          basic_auth: [
            username: System.get_env("SOAP_USERNAME"),
            password: System.get_env("SOAP_PASSWORD")
          ]

    ## config/runtime.exs (recommended for production secrets)

        if config_env() == :prod do
          config :my_app, :soap_services,
            api_key: System.fetch_env!("SOAP_API_KEY"),
            basic_auth: [
              username: System.fetch_env!("SOAP_USERNAME"),
              password: System.fetch_env!("SOAP_PASSWORD")
            ]
        end

    """

    @doc """
    Gets the configured API key for SOAP authentication.
    """
    def soap_api_key do
      Application.get_env(:my_app, :soap_services, [])
      |> Keyword.get(:api_key)
    end

    @doc """
    Gets the configured basic auth credentials.
    """
    def soap_basic_auth do
      Application.get_env(:my_app, :soap_services, [])
      |> Keyword.get(:basic_auth, [])
    end

    @doc """
    Gets an external service endpoint URL.
    """
    def external_service_url(service_name) do
      Application.get_env(:my_app, :soap_services, [])
      |> Keyword.get(:external_services, %{})
      |> Map.get(service_name)
    end
  end

  # ===========================================================================
  # SECTION 7: Testing Examples
  # ===========================================================================

  defmodule MyAppWeb.SOAPControllerTest do
    @moduledoc """
    Example tests for SOAP endpoints.

    These examples show how to test your SOAP services using Phoenix.ConnTest.
    """

    # In actual test file, use:
    # use MyAppWeb.ConnCase

    @sample_get_order_request """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <GetOrder xmlns="http://example.com/orders">
          <orderId>ORD-123</orderId>
        </GetOrder>
      </soap:Body>
    </soap:Envelope>
    """

    @sample_create_order_request """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <CreateOrder xmlns="http://example.com/orders">
          <request>
            <customerId>CUST-001</customerId>
            <items>
              <item>
                <productId>PROD-001</productId>
                <productName>Widget</productName>
                <quantity>5</quantity>
                <unitPrice>19.99</unitPrice>
              </item>
            </items>
          </request>
        </CreateOrder>
      </soap:Body>
    </soap:Envelope>
    """

    @doc """
    Example test for retrieving WSDL.

        test "GET /soap/orders?wsdl returns WSDL document", %{conn: conn} do
          conn = get(conn, "/soap/orders?wsdl")

          assert conn.status == 200
          assert get_resp_header(conn, "content-type") |> List.first() =~ "text/xml"
          assert conn.resp_body =~ "wsdl:definitions"
          assert conn.resp_body =~ "OrderService"
        end
    """
    def example_wsdl_test, do: @sample_get_order_request

    @doc """
    Example test for SOAP operation.

        test "POST /soap/orders GetOrder returns order", %{conn: conn} do
          conn =
            conn
            |> put_req_header("content-type", "text/xml")
            |> put_req_header("soapaction", "http://example.com/orders/GetOrder")
            |> post("/soap/orders", @sample_get_order_request)

          assert conn.status == 200
          assert conn.resp_body =~ "GetOrderResponse"
          assert conn.resp_body =~ "ORD-123"
        end
    """
    def example_operation_test, do: @sample_get_order_request

    @doc """
    Example test for SOAP fault response.

        test "POST /soap/orders GetOrder returns fault for unknown order", %{conn: conn} do
          request = String.replace(@sample_get_order_request, "ORD-123", "UNKNOWN")

          conn =
            conn
            |> put_req_header("content-type", "text/xml")
            |> put_req_header("soapaction", "http://example.com/orders/GetOrder")
            |> post("/soap/orders", request)

          assert conn.status == 500
          assert conn.resp_body =~ "soap:Fault"
          assert conn.resp_body =~ "Order not found"
        end
    """
    def example_fault_test, do: @sample_get_order_request

    @doc """
    Returns sample create order request for testing.
    """
    def sample_create_order_request, do: @sample_create_order_request
  end
end
