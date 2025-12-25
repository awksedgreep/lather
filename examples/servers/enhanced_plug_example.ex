defmodule Examples.Servers.EnhancedPlugExample do
  @moduledoc """
  Comprehensive example demonstrating Lather.Server.EnhancedPlug multi-protocol support.

  This example shows how to:
  1. Define a SOAP service with multiple operations
  2. Configure the EnhancedPlug in Phoenix Router
  3. Configure the EnhancedPlug in standalone Plug.Router
  4. Access all supported URL patterns and protocols

  ## Multi-Protocol Support

  EnhancedPlug provides a unified endpoint that supports multiple protocols:

  - **SOAP 1.1** - Traditional SOAP protocol (POST to base path)
  - **SOAP 1.2** - Modern SOAP protocol (POST to /v1.2)
  - **JSON/REST** - RESTful JSON API (POST to /api)
  - **Web Interface** - Interactive testing forms (GET requests)
  - **WSDL** - Service description (GET with ?wsdl)

  ## URL Patterns Summary

  | Method | Path             | Description                    |
  |--------|------------------|--------------------------------|
  | GET    | /service         | Web interface (service overview)|
  | GET    | /service?wsdl    | Standard WSDL download         |
  | GET    | /service?op=Name | Interactive operation form     |
  | POST   | /service         | SOAP 1.1 endpoint              |
  | POST   | /service/v1.2    | SOAP 1.2 endpoint              |
  | POST   | /service/api     | JSON/REST endpoint             |

  ## Example curl Commands

  See the bottom of this file for complete curl examples for each endpoint.
  """
end

# =============================================================================
# STEP 1: Define your SOAP Service
# =============================================================================

defmodule Examples.Servers.CalculatorService do
  @moduledoc """
  A simple calculator SOAP service demonstrating multi-protocol support.

  This service exposes basic arithmetic operations that can be accessed via:
  - SOAP 1.1 (text/xml)
  - SOAP 1.2 (application/soap+xml)
  - JSON/REST (application/json)
  - Interactive web forms
  """

  use Lather.Server

  @namespace "http://examples.com/calculator"
  @service_name "CalculatorService"

  # Define the operations

  soap_operation "Add" do
    description "Adds two numbers together"

    input do
      parameter "a", :decimal, required: true, description: "First number"
      parameter "b", :decimal, required: true, description: "Second number"
    end

    output do
      parameter "result", :decimal, description: "Sum of a and b"
    end

    soap_action "http://examples.com/calculator/Add"
  end

  def add(%{"a" => a, "b" => b}) do
    result = parse_number(a) + parse_number(b)
    {:ok, %{"result" => result}}
  end

  soap_operation "Subtract" do
    description "Subtracts the second number from the first"

    input do
      parameter "a", :decimal, required: true, description: "Number to subtract from"
      parameter "b", :decimal, required: true, description: "Number to subtract"
    end

    output do
      parameter "result", :decimal, description: "Difference of a minus b"
    end

    soap_action "http://examples.com/calculator/Subtract"
  end

  def subtract(%{"a" => a, "b" => b}) do
    result = parse_number(a) - parse_number(b)
    {:ok, %{"result" => result}}
  end

  soap_operation "Multiply" do
    description "Multiplies two numbers"

    input do
      parameter "a", :decimal, required: true, description: "First factor"
      parameter "b", :decimal, required: true, description: "Second factor"
    end

    output do
      parameter "result", :decimal, description: "Product of a and b"
    end

    soap_action "http://examples.com/calculator/Multiply"
  end

  def multiply(%{"a" => a, "b" => b}) do
    result = parse_number(a) * parse_number(b)
    {:ok, %{"result" => result}}
  end

  soap_operation "Divide" do
    description "Divides the first number by the second"

    input do
      parameter "a", :decimal, required: true, description: "Dividend (number to divide)"
      parameter "b", :decimal, required: true, description: "Divisor (number to divide by)"
    end

    output do
      parameter "result", :decimal, description: "Quotient of a divided by b"
    end

    soap_action "http://examples.com/calculator/Divide"
  end

  def divide(%{"a" => _a, "b" => b}) when b == "0" or b == 0 do
    soap_fault("Client", "Division by zero is not allowed", %{divisor: b})
  end

  def divide(%{"a" => a, "b" => b}) do
    result = parse_number(a) / parse_number(b)
    {:ok, %{"result" => result}}
  end

  # Helper to parse string or number input
  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> 0.0
    end
  end

  defp parse_number(value) when is_number(value), do: value
  defp parse_number(_), do: 0.0
end

# =============================================================================
# STEP 2: Phoenix Router Configuration
# =============================================================================

defmodule Examples.Servers.PhoenixRouterExample do
  @moduledoc """
  Example Phoenix Router configuration for EnhancedPlug.

  This demonstrates how to integrate the multi-protocol SOAP service
  into a Phoenix application.

  ## Key Points

  1. Use `match :*` to handle all HTTP methods (GET, POST)
  2. Include both the base path and wildcard path for sub-routes
  3. The wildcard path captures /v1.2 and /api sub-paths

  ## Router Configuration

  ```elixir
  defmodule MyAppWeb.Router do
    use Phoenix.Router

    pipeline :api do
      plug :accepts, ["xml", "json", "html"]
    end

    scope "/soap" do
      pipe_through :api

      # Calculator service - handles all URL patterns
      match :*, "/calculator", Lather.Server.EnhancedPlug,
        service: Examples.Servers.CalculatorService,
        base_path: "/soap/calculator"

      # Wildcard path for /v1.2 and /api sub-routes
      match :*, "/calculator/*path", Lather.Server.EnhancedPlug,
        service: Examples.Servers.CalculatorService,
        base_path: "/soap/calculator"
    end
  end
  ```

  ## Resulting Endpoints

  With the above configuration, these endpoints are available:

  - GET  http://localhost:4000/soap/calculator           -> Service overview
  - GET  http://localhost:4000/soap/calculator?wsdl      -> WSDL document
  - GET  http://localhost:4000/soap/calculator?op=Add    -> Add operation form
  - POST http://localhost:4000/soap/calculator           -> SOAP 1.1
  - POST http://localhost:4000/soap/calculator/v1.2      -> SOAP 1.2
  - POST http://localhost:4000/soap/calculator/api       -> JSON/REST
  """

  # This is a documentation-only module showing the router pattern
  # See the @moduledoc for the actual router code
end

# =============================================================================
# STEP 3: Standalone Plug.Router Configuration
# =============================================================================

defmodule Examples.Servers.StandalonePlugRouterExample do
  @moduledoc """
  Example standalone Plug.Router configuration for EnhancedPlug.

  This demonstrates how to use EnhancedPlug in a standalone Plug application
  without Phoenix, useful for lightweight microservices.

  ## Usage

  To run this example standalone:

  ```elixir
  # In your application supervision tree
  children = [
    {Plug.Cowboy, scheme: :http, plug: Examples.Servers.StandalonePlugRouterExample, options: [port: 4000]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
  ```

  Or from IEx:

  ```elixir
  iex> {:ok, _} = Plug.Cowboy.http(Examples.Servers.StandalonePlugRouterExample, [], port: 4000)
  ```
  """

  use Plug.Router

  plug :match
  plug :dispatch

  # Forward all calculator requests to EnhancedPlug
  # The forward macro handles both base path and sub-paths automatically
  forward "/calculator",
    to: Lather.Server.EnhancedPlug,
    init_opts: [
      service: Examples.Servers.CalculatorService,
      base_path: "/calculator",
      enable_forms: true,
      enable_json: true
    ]

  # Alternative: Using match for more control
  # match _ do
  #   opts = Lather.Server.EnhancedPlug.init(
  #     service: Examples.Servers.CalculatorService,
  #     base_path: "/calculator"
  #   )
  #   Lather.Server.EnhancedPlug.call(conn, opts)
  # end

  # Catch-all for unmatched routes
  match _ do
    send_resp(conn, 404, "Not found")
  end
end

# =============================================================================
# STEP 4: EnhancedPlug Configuration Options
# =============================================================================

defmodule Examples.Servers.EnhancedPlugOptions do
  @moduledoc """
  Documentation of all EnhancedPlug configuration options.

  ## Available Options

  | Option           | Type      | Default    | Description                              |
  |------------------|-----------|------------|------------------------------------------|
  | `:service`       | module    | (required) | The SOAP service module                  |
  | `:base_path`     | string    | "/soap"    | Base URL path for the service            |
  | `:enable_forms`  | boolean   | true       | Enable interactive web form interface    |
  | `:enable_json`   | boolean   | true       | Enable JSON/REST endpoint                |
  | `:auth_handler`  | function  | nil        | Custom authentication handler            |
  | `:validate_params` | boolean | true       | Enable parameter validation              |

  ## Examples

  ### Minimal configuration:

  ```elixir
  plug Lather.Server.EnhancedPlug,
    service: MyApp.CalculatorService
  ```

  ### Full configuration with all options:

  ```elixir
  plug Lather.Server.EnhancedPlug,
    service: MyApp.CalculatorService,
    base_path: "/api/soap/calculator",
    enable_forms: true,
    enable_json: true,
    validate_params: true,
    auth_handler: &MyApp.Auth.verify_soap_request/1
  ```

  ### Production configuration (forms disabled):

  ```elixir
  plug Lather.Server.EnhancedPlug,
    service: MyApp.CalculatorService,
    base_path: "/soap/calculator",
    enable_forms: false,  # Disable for production
    enable_json: true,
    validate_params: true
  ```

  ### SOAP-only configuration (no JSON):

  ```elixir
  plug Lather.Server.EnhancedPlug,
    service: MyApp.CalculatorService,
    base_path: "/soap/calculator",
    enable_json: false  # Disable JSON/REST endpoint
  ```
  """
end

# =============================================================================
# CURL EXAMPLES FOR ALL ENDPOINTS
# =============================================================================

defmodule Examples.Servers.CurlExamples do
  @moduledoc """
  Complete curl command examples for testing all EnhancedPlug endpoints.

  Assuming the service is running at http://localhost:4000/soap/calculator

  ## 1. GET /service - Web Interface (Service Overview)

  Opens the interactive service overview page with links to all operations.

  ```bash
  curl -X GET "http://localhost:4000/soap/calculator"
  ```

  Response: HTML page with service documentation and operation links.

  ---

  ## 2. GET /service?wsdl - WSDL Document

  Downloads the WSDL (Web Services Description Language) document.

  ```bash
  # Standard WSDL
  curl -X GET "http://localhost:4000/soap/calculator?wsdl"

  # Enhanced multi-protocol WSDL (includes SOAP 1.1, 1.2, and HTTP bindings)
  curl -X GET "http://localhost:4000/soap/calculator?wsdl&enhanced=true"

  # Save WSDL to file
  curl -X GET "http://localhost:4000/soap/calculator?wsdl" -o calculator.wsdl
  ```

  Response: XML WSDL document describing the service.

  ---

  ## 3. GET /service?op=OperationName - Operation Form

  Opens an interactive form for testing a specific operation.

  ```bash
  # View Add operation form
  curl -X GET "http://localhost:4000/soap/calculator?op=Add"

  # View Divide operation form
  curl -X GET "http://localhost:4000/soap/calculator?op=Divide"
  ```

  Response: HTML form for testing the operation.

  ---

  ## 4. POST /service - SOAP 1.1 Endpoint

  Sends a SOAP 1.1 request (Content-Type: text/xml).

  ```bash
  # Add operation via SOAP 1.1
  curl -X POST "http://localhost:4000/soap/calculator" \\
    -H "Content-Type: text/xml; charset=utf-8" \\
    -H "SOAPAction: http://examples.com/calculator/Add" \\
    -d '<?xml version="1.0" encoding="utf-8"?>
  <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                 xmlns:calc="http://examples.com/calculator">
    <soap:Body>
      <calc:Add>
        <calc:a>10</calc:a>
        <calc:b>5</calc:b>
      </calc:Add>
    </soap:Body>
  </soap:Envelope>'

  # Multiply operation via SOAP 1.1
  curl -X POST "http://localhost:4000/soap/calculator" \\
    -H "Content-Type: text/xml; charset=utf-8" \\
    -H "SOAPAction: http://examples.com/calculator/Multiply" \\
    -d '<?xml version="1.0" encoding="utf-8"?>
  <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                 xmlns:calc="http://examples.com/calculator">
    <soap:Body>
      <calc:Multiply>
        <calc:a>7</calc:a>
        <calc:b>6</calc:b>
      </calc:Multiply>
    </soap:Body>
  </soap:Envelope>'
  ```

  Response: SOAP 1.1 XML response with Content-Type: text/xml.

  ---

  ## 5. POST /service/v1.2 - SOAP 1.2 Endpoint

  Sends a SOAP 1.2 request (Content-Type: application/soap+xml).

  ```bash
  # Subtract operation via SOAP 1.2
  curl -X POST "http://localhost:4000/soap/calculator/v1.2" \\
    -H "Content-Type: application/soap+xml; charset=utf-8; action=http://examples.com/calculator/Subtract" \\
    -d '<?xml version="1.0" encoding="utf-8"?>
  <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
                 xmlns:calc="http://examples.com/calculator">
    <soap:Body>
      <calc:Subtract>
        <calc:a>100</calc:a>
        <calc:b>42</calc:b>
      </calc:Subtract>
    </soap:Body>
  </soap:Envelope>'

  # Divide operation via SOAP 1.2
  curl -X POST "http://localhost:4000/soap/calculator/v1.2" \\
    -H "Content-Type: application/soap+xml; charset=utf-8; action=http://examples.com/calculator/Divide" \\
    -d '<?xml version="1.0" encoding="utf-8"?>
  <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope"
                 xmlns:calc="http://examples.com/calculator">
    <soap:Body>
      <calc:Divide>
        <calc:a>100</calc:a>
        <calc:b>4</calc:b>
      </calc:Divide>
    </soap:Body>
  </soap:Envelope>'
  ```

  Response: SOAP 1.2 XML response with Content-Type: application/soap+xml.

  Note: SOAP 1.2 uses different namespace and content type than SOAP 1.1.

  ---

  ## 6. POST /service/api - JSON/REST Endpoint

  Sends a JSON request for RESTful access to SOAP operations.

  ```bash
  # Add operation via JSON
  curl -X POST "http://localhost:4000/soap/calculator/api/Add" \\
    -H "Content-Type: application/json" \\
    -d '{"a": 10, "b": 5}'

  # Multiply operation via JSON
  curl -X POST "http://localhost:4000/soap/calculator/api/Multiply" \\
    -H "Content-Type: application/json" \\
    -d '{"a": 7, "b": 6}'

  # Divide operation via JSON (with pretty output)
  curl -X POST "http://localhost:4000/soap/calculator/api/Divide" \\
    -H "Content-Type: application/json" \\
    -d '{"a": 100, "b": 4}' | jq .

  # Error case: Division by zero
  curl -X POST "http://localhost:4000/soap/calculator/api/Divide" \\
    -H "Content-Type: application/json" \\
    -d '{"a": 10, "b": 0}'
  ```

  Response: JSON object with structure:
  ```json
  {
    "success": true,
    "data": {
      "result": 15
    }
  }
  ```

  Or for errors:
  ```json
  {
    "error": {
      "code": "Client",
      "message": "Division by zero is not allowed",
      "detail": {"divisor": 0}
    }
  }
  ```

  ---

  ## Protocol Comparison

  | Protocol  | Endpoint      | Content-Type           | Use Case                    |
  |-----------|---------------|------------------------|-----------------------------|
  | SOAP 1.1  | /service      | text/xml               | Legacy systems, WS-*        |
  | SOAP 1.2  | /service/v1.2 | application/soap+xml   | Modern SOAP, better errors  |
  | JSON/REST | /service/api  | application/json       | Web/mobile apps, simplicity |

  ## Testing Tips

  1. Use `-v` flag for verbose output to see headers
  2. Use `-o /dev/null` to suppress response body
  3. Use `| xmllint --format -` to pretty-print XML responses
  4. Use `| jq .` to pretty-print JSON responses
  """
end
