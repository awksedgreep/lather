# Lather SOAP Library Usage Guide

Lather is a comprehensive SOAP library for Elixir that provides both client and server capabilities with modern web interfaces. It can work with any SOAP service without requiring service-specific implementations, using dynamic WSDL analysis and runtime operation building.

## Quick Start

```elixir
# Add to your mix.exs dependencies
{:lather, "~> 1.0"}

# Start the application
{:ok, _} = Application.ensure_all_started(:lather)

# Create a dynamic client from any WSDL
{:ok, client} = Lather.DynamicClient.new("http://example.com/service?wsdl")

# Call any operation defined in the WSDL
{:ok, response} = Lather.DynamicClient.call(client, "GetUser", %{
  "userId" => "12345"
})
```

## Core Concepts

### 1. Dynamic WSDL Analysis

Lather automatically parses WSDL files to understand:
- Available operations and their parameters
- Input/output message structures
- Data types and validation rules
- Endpoint URLs and binding styles
- Security requirements
- SOAP version support (1.1 and 1.2)

```elixir
# List all available operations
operations = Lather.DynamicClient.list_operations(client)
IO.inspect(operations)
# => [
#   %{name: "GetUser", required_parameters: ["userId"], ...},
#   %{name: "CreateUser", required_parameters: ["userData"], ...}
# ]

# Get detailed operation information
{:ok, op_info} = Lather.DynamicClient.get_operation_info(client, "GetUser")
IO.inspect(op_info)
# => %{
#   name: "GetUser",
#   input_parts: [%{name: "userId", type: "string", required: true}],
#   output_parts: [%{name: "user", type: "User"}],
#   soap_action: "http://example.com/GetUser",
#   soap_version: :v1_1
# }
```

### 2. Multi-Protocol Support (v1.0.0)

Lather v1.0.0 supports multiple SOAP versions and protocols:

```elixir
# Automatic version detection
{:ok, client} = Lather.DynamicClient.new("http://example.com/service?wsdl")

# Explicit SOAP version specification
{:ok, client_v12} = Lather.DynamicClient.new(
  "http://example.com/service?wsdl",
  soap_version: :v1_2
)

# Both clients will use appropriate headers and envelope formats
{:ok, response} = Lather.DynamicClient.call(client_v12, "GetUser", %{"userId" => "123"})
```

### 3. Generic Operation Calls

Lather can call any SOAP operation without requiring predefined method signatures:

```elixir
# Simple parameter passing
{:ok, response} = Lather.DynamicClient.call(client, "GetUser", %{
  "userId" => "12345"
})

# Complex parameter structures
{:ok, response} = Lather.DynamicClient.call(client, "CreateUser", %{
  "user" => %{
    "name" => "John Doe",
    "email" => "john@example.com",
    "address" => %{
      "street" => "123 Main St",
      "city" => "Anytown",
      "zip" => "12345"
    }
  }
})

# Array parameters
{:ok, response} = Lather.DynamicClient.call(client, "GetUsers", %{
  "userIds" => ["123", "456", "789"]
})
```

## SOAP Client Examples

### Example 1: Weather Service (SOAP 1.1)

```elixir
# Connect to a weather SOAP service
{:ok, weather_client} = Lather.DynamicClient.new(
  "http://www.webservicex.net/globalweather.asmx?WSDL",
  timeout: 30_000
)

# Get weather for a specific location
{:ok, weather} = Lather.DynamicClient.call(weather_client, "GetWeather", %{
  "CityName" => "New York",
  "CountryName" => "United States"
})

IO.inspect(weather.body)
```

### Example 2: Country Information Service (SOAP 1.2)

```elixir
# Connect to country info service with SOAP 1.2
{:ok, country_client} = Lather.DynamicClient.new(
  "http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso?WSDL",
  soap_version: :v1_2,
  timeout: 15_000
)

# Get full country information
{:ok, country_info} = Lather.DynamicClient.call(country_client, "FullCountryInfo", %{
  "parameters" => %{"sCountryISOCode" => "US"}
})

IO.inspect(country_info.body)
```

### Example 3: Enterprise Service with Authentication

```elixir
# Connect to an enterprise service with authentication
{:ok, enterprise_client} = Lather.DynamicClient.new(
  "https://enterprise.example.com/services/UserService?wsdl",
  authentication: {:basic, "username", "password"},
  ssl_options: [verify: :verify_peer],
  timeout: 60_000,
  soap_version: :v1_2
)

# Call authenticated operation
{:ok, users} = Lather.DynamicClient.call(enterprise_client, "ListUsers", %{
  "department" => "Engineering",
  "active" => true
})
```

## SOAP Server Development

### Basic Server Definition

```elixir
defmodule MyApp.UserService do
  use Lather.Server
  
  @namespace "http://myapp.com/users"
  @service_name "UserManagementService"
  
  # Define a SOAP operation
  soap_operation "GetUser" do
    description "Retrieve user information by ID"
    
    input do
      parameter "userId", :string, required: true, description: "User identifier"
      parameter "includeProfile", :boolean, required: false, description: "Include full profile"
    end
    
    output do
      parameter "user", "tns:User", description: "User information"
    end
    
    soap_action "#{@namespace}/GetUser"
  end

  # Implement the operation
  def get_user(%{"userId" => user_id} = params) do
    include_profile = Map.get(params, "includeProfile", false)
    
    # Your business logic here
    user = MyApp.Users.get!(user_id)
    
    {:ok, %{
      "user" => %{
        "id" => user.id,
        "name" => user.name,
        "email" => user.email
      }
    }}
  end
end
```

### Enhanced Multi-Protocol Server (v1.0.0)

```elixir
# Phoenix router configuration for multi-protocol support
scope "/api/users" do
  pipe_through :api
  
  # Multi-protocol endpoints - supports SOAP 1.1, SOAP 1.2, and JSON/REST
  match :*, "/", Lather.Server.EnhancedPlug, service: MyApp.UserService
  match :*, "/*path", Lather.Server.EnhancedPlug, service: MyApp.UserService
end

# This automatically exposes:
# GET  /api/users              → Interactive web interface
# GET  /api/users?wsdl         → Standard WSDL (SOAP 1.1)
# GET  /api/users?wsdl&enhanced=true → Enhanced multi-protocol WSDL
# GET  /api/users?op=GetUser   → Interactive operation form
# POST /api/users              → SOAP 1.1 endpoint
# POST /api/users/v1.2         → SOAP 1.2 endpoint  
# POST /api/users/api          → JSON/REST endpoint
```

### WSDL Generation

```elixir
# Generate standard WSDL
service_info = MyApp.UserService.__service_info__()
wsdl = Lather.Server.WsdlGenerator.generate(service_info, "https://myapp.com/api/users")

# Generate enhanced multi-protocol WSDL
enhanced_wsdl = Lather.Server.EnhancedWSDLGenerator.generate(service_info, "https://myapp.com/api/users")

# Generate interactive web forms
overview_page = Lather.Server.FormGenerator.generate_service_overview(service_info, "https://myapp.com/api/users")
```

## Configuration Options

### Client Configuration

```elixir
{:ok, client} = Lather.DynamicClient.new(wsdl_url, [
  # SOAP version (auto-detected if not specified)
  soap_version: :v1_2,  # or :v1_1
  
  # HTTP authentication
  authentication: {:basic, "username", "password"},
  
  # SSL/TLS configuration
  ssl_options: [
    verify: :verify_peer,
    cacerts: :public_key.cacerts_get(),
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ],
  
  # Timeout settings
  timeout: 30_000,
  pool_timeout: 5_000,
  
  # Custom headers
  default_headers: [
    {"X-API-Key", "your-api-key"},
    {"User-Agent", "MyApp/1.0"}
  ],
  
  # Service selection (if WSDL contains multiple services)
  service_name: "UserService",
  
  # Endpoint override
  endpoint_override: "https://custom-endpoint.com/soap"
])
```

### Operation Call Options

```elixir
{:ok, response} = Lather.DynamicClient.call(client, "OperationName", parameters, [
  # Override SOAPAction header
  soap_action: "http://custom.com/action",
  
  # Custom timeout for this call
  timeout: 60_000,
  
  # Additional headers for this request
  headers: [{"X-Request-ID", "12345"}],
  
  # Force specific SOAP version for this call
  soap_version: :v1_2
])
```

### Global Configuration

```elixir
# config/config.exs
config :lather,
  default_timeout: 30_000,
  ssl_verify: :verify_peer,
  finch_pools: %{
    default: [size: 25, count: 1]
  }

# Configure Finch for optimal performance
config :lather, :finch,
  pools: %{
    "https://api.example.com" => [
      size: 25,
      protocols: [:http2, :http1]
    ]
  }
```

## Error Handling

Lather provides comprehensive structured error handling:

```elixir
case Lather.DynamicClient.call(client, "GetUser", %{"userId" => "123"}) do
  {:ok, response} ->
    # Handle successful response
    IO.inspect(response.body)
    
  {:error, %{type: :soap_fault} = fault} ->
    # Handle SOAP fault (both v1.1 and v1.2)
    IO.puts("SOAP Fault: #{fault.fault_string}")
    IO.puts("Fault Code: #{fault.fault_code}")
    
  {:error, %{type: :http_error} = error} ->
    # Handle HTTP error
    IO.puts("HTTP Error #{error.status}: #{error.body}")
    
  {:error, %{type: :transport_error} = error} ->
    # Handle network/transport error
    IO.puts("Transport Error: #{error.reason}")
    
  {:error, %{type: :validation_error} = error} ->
    # Handle validation error
    IO.puts("Validation Error: #{error.reason}")
    
  {:error, %{type: :wsdl_parse_error} = error} ->
    # Handle WSDL parsing error
    IO.puts("WSDL Parse Error: #{error.reason}")
end
```

### Error Recovery and Retry

```elixir
defmodule SOAPClient.RetryLogic do
  def call_with_retry(client, operation, params, max_retries \\ 3) do
    call_with_retry(client, operation, params, max_retries, 0)
  end
  
  defp call_with_retry(client, operation, params, max_retries, attempt) do
    case Lather.DynamicClient.call(client, operation, params) do
      {:ok, response} ->
        {:ok, response}
        
      {:error, error} when attempt < max_retries ->
        if Lather.Error.recoverable?(error) do
          backoff_ms = :math.pow(2, attempt) * 1000
          Process.sleep(trunc(backoff_ms))
          call_with_retry(client, operation, params, max_retries, attempt + 1)
        else
          {:error, error}
        end
        
      {:error, error} ->
        {:error, error}
    end
  end
end
```

## Advanced Features

### WS-Security Authentication

```elixir
# Username token with password digest
username_token = Lather.Auth.WSSecurity.username_token("user", "pass", :digest)
security_header = Lather.Auth.WSSecurity.security_header(username_token)

{:ok, client} = Lather.DynamicClient.new(wsdl_url,
  soap_headers: [security_header],
  ssl_options: [verify: :verify_peer]
)
```

### Custom XML Processing

```elixir
# Build custom XML structures
xml_content = Lather.Xml.Builder.build(%{
  "CustomElement" => %{
    "@xmlns" => "http://custom.namespace",
    "#content" => [
      %{"SubElement" => "value"}
    ]
  }
})

# Parse XML responses with custom logic
{:ok, parsed} = Lather.Xml.Parser.parse(xml_response, 
  namespace_aware: true,
  custom_parsers: %{"CustomType" => &my_custom_parser/1}
)
```

### Connection Management

```elixir
# Configure connection pools in your application
children = [
  {Finch, 
   name: Lather.Finch,
   pools: %{
     "https://api.example.com" => [
       size: 25,
       protocols: [:http2, :http1]
     ]
   }
  }
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Interactive Web Testing

With Lather v1.0.0, your SOAP services automatically include interactive web interfaces:

```elixir
# Visit your service endpoint in a browser
# GET https://yourapp.com/api/users
# 
# This shows:
# - Service overview and documentation
# - Interactive forms for testing operations
# - Multi-protocol examples (SOAP 1.1, SOAP 1.2, JSON)
# - Dark mode support
# - Mobile-friendly responsive design
```

## Performance Optimization

### Connection Reuse

```elixir
# Create clients once and reuse them
defmodule MyApp.SOAPClients do
  def get_user_service_client do
    case :persistent_term.get(:user_service_client, nil) do
      nil ->
        {:ok, client} = Lather.DynamicClient.new("http://user.service.wsdl")
        :persistent_term.put(:user_service_client, client)
        client
      client ->
        client
    end
  end
end
```

### Async Operations

```elixir
# Make multiple SOAP calls concurrently
tasks = Enum.map(user_ids, fn user_id ->
  Task.async(fn ->
    Lather.DynamicClient.call(client, "GetUser", %{"userId" => user_id})
  end)
end)

results = Task.await_many(tasks, 30_000)
```

### Streaming Large Responses

```elixir
# For large data sets, consider pagination
def fetch_all_users(client, page_size \\ 100) do
  fetch_users_page(client, 1, page_size, [])
end

defp fetch_users_page(client, page, page_size, acc) do
  case Lather.DynamicClient.call(client, "GetUsers", %{
    "page" => page,
    "pageSize" => page_size
  }) do
    {:ok, %{body: %{"users" => users}}} when length(users) < page_size ->
      acc ++ users
    {:ok, %{body: %{"users" => users}}} ->
      fetch_users_page(client, page + 1, page_size, acc ++ users)
    {:error, error} ->
      {:error, error}
  end
end
```

## Testing

### Unit Testing SOAP Clients

```elixir
defmodule MyApp.SOAPClientTest do
  use ExUnit.Case
  
  test "handles successful SOAP responses" do
    # Mock WSDL content
    mock_wsdl = """
    <?xml version="1.0"?>
    <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                 targetNamespace="http://test.example.com">
      <!-- WSDL content -->
    </definitions>
    """
    
    # Test with mock service
    with_mock_http(mock_wsdl, fn ->
      {:ok, client} = Lather.DynamicClient.new("http://mock.service.wsdl")
      {:ok, response} = Lather.DynamicClient.call(client, "TestOperation", %{})
      
      assert response.status == 200
      assert is_map(response.body)
    end)
  end
end
```

### Integration Testing with Real Services

```elixir
# Use tags to control which tests run
@tag :external_api
test "integrates with real weather service" do
  {:ok, client} = Lather.DynamicClient.new(
    "http://www.webservicex.net/globalweather.asmx?WSDL",
    timeout: 30_000
  )
  
  {:ok, response} = Lather.DynamicClient.call(client, "GetCitiesByCountry", %{
    "CountryName" => "United States"
  })
  
  assert response.status == 200
  # Be respectful of external APIs - limit these tests
end

# Run only unit tests by default
# mix test
# 
# Run with external API tests (use sparingly!)
# mix test --include external_api
```

### Testing SOAP Servers

```elixir
defmodule MyApp.UserServiceTest do
  use ExUnit.Case
  use Plug.Test
  
  test "generates valid WSDL" do
    service_info = MyApp.UserService.__service_info__()
    wsdl = Lather.Server.WsdlGenerator.generate(service_info, "http://test.com")
    
    # Validate WSDL structure
    assert wsdl =~ "definitions"
    assert wsdl =~ "UserManagementService"
    assert wsdl =~ "GetUser"
  end
  
  test "handles SOAP 1.1 requests" do
    soap_request = """
    <?xml version="1.0"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <GetUser xmlns="http://myapp.com/users">
          <userId>123</userId>
        </GetUser>
      </soap:Body>
    </soap:Envelope>
    """
    
    conn = 
      :post
      |> conn("/api/users", soap_request)
      |> put_req_header("content-type", "text/xml; charset=utf-8")
      |> put_req_header("soapaction", "http://myapp.com/users/GetUser")
      |> Lather.Server.EnhancedPlug.call(service: MyApp.UserService)
    
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/xml; charset=utf-8"]
  end
end
```

## Troubleshooting

### Debug Logging

```elixir
# Enable debug logging
Logger.configure(level: :debug)

# Or configure in config.exs
config :logger, level: :debug

# Lather will log detailed information about:
# - WSDL parsing steps
# - SOAP envelope construction  
# - HTTP request/response details
# - Error context and stack traces
```

### Common Issues and Solutions

#### 1. WSDL Parsing Errors
```elixir
# Problem: Cannot parse WSDL
# Solution: Check WSDL accessibility and validity
case Lather.DynamicClient.new(wsdl_url) do
  {:error, %{type: :wsdl_parse_error, reason: reason}} ->
    IO.puts("WSDL Parse Error: #{reason}")
    # Check if WSDL URL is accessible
    # Verify WSDL syntax is valid
    # Ensure all imports/includes are available
end
```

#### 2. SSL Certificate Issues
```elixir
# Problem: SSL verification failures
# Solution: Configure SSL options
{:ok, client} = Lather.DynamicClient.new(wsdl_url, [
  ssl_options: [
    verify: :verify_none,  # For development only!
    # For production, use proper certificates:
    # verify: :verify_peer,
    # cacerts: :public_key.cacerts_get()
  ]
])
```

#### 3. Timeout Errors
```elixir
# Problem: Requests timing out
# Solution: Increase timeout values
{:ok, client} = Lather.DynamicClient.new(wsdl_url, [
  timeout: 120_000,      # 2 minutes
  pool_timeout: 15_000   # 15 seconds
])
```

#### 4. Authentication Failures
```elixir
# Problem: Authentication not working
# Solution: Verify authentication method and credentials
{:ok, client} = Lather.DynamicClient.new(wsdl_url, [
  # For Basic Auth
  authentication: {:basic, "correct_username", "correct_password"},
  
  # For WS-Security
  soap_headers: [security_header]
])
```

#### 5. SOAP Version Conflicts
```elixir
# Problem: Service expects specific SOAP version
# Solution: Explicitly specify SOAP version
{:ok, client} = Lather.DynamicClient.new(wsdl_url, [
  soap_version: :v1_2  # Use SOAP 1.2 instead of auto-detected version
])
```

## Migration Guide

### From Other SOAP Libraries

#### From HTTPoison-based Solutions

```elixir
# Old approach with hardcoded requests
def get_user_old(user_id) do
  soap_body = """
  <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
    <soap:Body>
      <GetUser xmlns="http://example.com">
        <userId>#{user_id}</userId>
      </GetUser>
    </soap:Body>
  </soap:Envelope>
  """
  
  HTTPoison.post(url, soap_body, [
    {"Content-Type", "text/xml; charset=utf-8"},
    {"SOAPAction", "http://example.com/GetUser"}
  ])
end

# New approach with Lather
def get_user_new(user_id) do
  Lather.DynamicClient.call(client, "GetUser", %{"userId" => user_id})
end
```

#### From Detergent

```elixir
# Old Detergent approach
{:ok, wsdl} = Detergent.parse_wsdl("http://service.wsdl")
{:ok, response} = Detergent.call(wsdl, "GetUser", %{userId: "123"})

# New Lather approach
{:ok, client} = Lather.DynamicClient.new("http://service.wsdl")
{:ok, response} = Lather.DynamicClient.call(client, "GetUser", %{"userId" => "123"})
```

### Upgrading from Pre-1.0 Lather

```elixir
# Pre-1.0 (if you had early versions)
{:ok, client} = Lather.Client.new(wsdl_url)

# v1.0.0+
{:ok, client} = Lather.DynamicClient.new(wsdl_url)

# Server definitions are more structured now
defmodule MyService do
  use Lather.Server
  
  # Old style (if it existed)
  # operation :get_user, ...
  
  # New style
  soap_operation "GetUser" do
    description "Get user by ID"
    # ... detailed operation definition
  end
end
```

## Interactive Learning Resources

Lather includes comprehensive Livebook tutorials:

- **Getting Started** (`livebooks/getting_started.livemd`) - Basic concepts and first examples
- **Weather Service Example** (`livebooks/weather_service_example.livemd`) - Real-world document/encoded style
- **Country Info Service** (`livebooks/country_info_service_example.livemd`) - Document/literal examples  
- **SOAP Server Development** (`livebooks/soap_server_development.livemd`) - Building services
- **Advanced Types** (`livebooks/advanced_types.livemd`) - Complex data structures
- **Enterprise Integration** (`livebooks/enterprise_integration.livemd`) - Production patterns
- **Debugging & Troubleshooting** (`livebooks/debugging_troubleshooting.livemd`) - Problem solving

Run with: `livebook server livebooks/getting_started.livemd`

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.

## License

MIT License - see the LICENSE file in the repository for details.