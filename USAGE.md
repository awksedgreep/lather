# Lather SOAP Library Usage Guide

Lather is a generic SOAP library for Elixir that can work with any SOAP service without requiring service-specific implementations. It dynamically analyzes WSDL files and builds SOAP requests at runtime.

## Quick Start

```elixir
# Add to your mix.exs dependencies
{:lather, "~> 0.1.0"}

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

```elixir
# List all available operations
operations = Lather.DynamicClient.list_operations(client)
IO.inspect(operations)
# => ["GetUser", "CreateUser", "UpdateUser", "DeleteUser"]

# Get detailed operation information
{:ok, op_info} = Lather.DynamicClient.get_operation_info(client, "GetUser")
IO.inspect(op_info)
# => %{
#   name: "GetUser",
#   input_parts: [%{name: "userId", type: "string", required: true}],
#   output_parts: [%{name: "user", type: "User"}],
#   soap_action: "http://example.com/GetUser"
# }
```

### 2. Generic Operation Calls

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

## Real-World Examples

### Example 1: Weather Service

```elixir
# Connect to a weather SOAP service
{:ok, weather_client} = Lather.DynamicClient.new(
  "http://www.webservicex.net/globalweather.asmx?WSDL"
)

# Get weather for a specific location
{:ok, weather} = Lather.DynamicClient.call(weather_client, "GetWeather", %{
  "CityName" => "New York",
  "CountryName" => "United States"
})

IO.inspect(weather)
```

### Example 2: Currency Conversion Service

```elixir
# Connect to currency conversion service
{:ok, currency_client} = Lather.DynamicClient.new(
  "http://www.webservicex.net/CurrencyConvertor.asmx?WSDL"
)

# Convert between currencies
{:ok, rate} = Lather.DynamicClient.call(currency_client, "ConversionRate", %{
  "FromCurrency" => "USD",
  "ToCurrency" => "EUR"
})

IO.inspect(rate)
```

### Example 3: Enterprise Service with Authentication

```elixir
# Connect to an enterprise service with authentication
{:ok, enterprise_client} = Lather.DynamicClient.new(
  "https://enterprise.example.com/services/UserService?wsdl",
  basic_auth: {"username", "password"},
  ssl_options: [verify: :verify_peer],
  timeout: 60_000
)

# Call authenticated operation
{:ok, users} = Lather.DynamicClient.call(enterprise_client, "ListUsers", %{
  "department" => "Engineering",
  "active" => true
})
```

## Configuration Options

### Client Options

```elixir
{:ok, client} = Lather.DynamicClient.new(wsdl_url, [
  # HTTP authentication
  basic_auth: {"username", "password"},
  
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
  headers: [
    {"X-API-Key", "your-api-key"},
    {"User-Agent", "MyApp/1.0"}
  ],
  
  # WSDL parsing options
  namespace_aware: true,
  strict_validation: false
])
```

### Operation Call Options

```elixir
{:ok, response} = Lather.DynamicClient.call(client, "OperationName", parameters, [
  # Override SOAPAction header
  soap_action: "http://custom.com/action",
  
  # Disable parameter validation
  validate: false,
  
  # Custom timeout for this call
  timeout: 60_000,
  
  # Additional headers for this request
  headers: [{"X-Request-ID", "12345"}]
])
```

## Error Handling

Lather provides comprehensive structured error handling:

```elixir
case Lather.DynamicClient.call(client, "GetUser", %{"userId" => "123"}) do
  {:ok, response} ->
    # Handle successful response
    IO.inspect(response)
    
  {:error, %{type: :soap_fault} = fault} ->
    # Handle SOAP fault
    IO.puts("SOAP Fault: #{fault.fault_string}")
    
  {:error, %{type: :http_error} = error} ->
    # Handle HTTP error
    IO.puts("HTTP Error #{error.status}: #{error.body}")
    
  {:error, %{type: :transport_error} = error} ->
    # Handle network/transport error
    IO.puts("Transport Error: #{error.reason}")
    
  {:error, %{type: :validation_error} = error} ->
    # Handle validation error
    IO.puts("Validation Error: #{error.reason}")
end
```

### Error Recovery

```elixir
# Check if an error is recoverable (e.g., network timeouts)
if Lather.Error.recoverable?(error) do
  # Retry the operation
  Process.sleep(1000)
  retry_operation()
else
  # Log error and fail
  Logger.error("Unrecoverable error: #{Lather.Error.format_error(error)}")
end
```

## Advanced Features

### Type Mapping and Validation

Lather automatically maps between XML and Elixir data types:

```elixir
# Generate Elixir structs from WSDL types
{:ok, types} = Lather.Types.Generator.generate_structs(wsdl_types, "MyApp.Types")

# Use generated structs for type safety
user = %MyApp.Types.User{
  name: "John Doe",
  email: "john@example.com"
}

{:ok, response} = Lather.DynamicClient.call(client, "CreateUser", %{
  "user" => user
})
```

### Custom XML Processing

```elixir
# Build custom XML structures
xml_content = Lather.XML.Builder.build(%{
  "CustomElement" => %{
    "@xmlns" => "http://custom.namespace",
    "#content" => [
      %{"SubElement" => "value"}
    ]
  }
})

# Parse XML responses with custom logic
{:ok, parsed} = Lather.XML.Parser.parse(xml_response, 
  namespace_aware: true,
  custom_parsers: %{"CustomType" => &my_custom_parser/1}
)
```

### Connection Management

Lather uses Finch for efficient HTTP connection management:

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

## Testing

### Mock SOAP Services

```elixir
# Use Lather for testing with mock SOAP services
defmodule MyAppTest do
  use ExUnit.Case
  
  test "handles SOAP service responses" do
    # Mock WSDL and responses
    mock_wsdl = """
    <?xml version="1.0"?>
    <definitions xmlns="http://schemas.xmlsoap.org/wsdl/">
      <!-- WSDL content -->
    </definitions>
    """
    
    # Test your service integration
    {:ok, client} = Lather.DynamicClient.new("http://mock.service.wsdl")
    assert {:ok, _response} = Lather.DynamicClient.call(client, "TestOperation", %{})
  end
end
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

## Troubleshooting

### Debug Logging

```elixir
# Enable debug logging
Logger.configure(level: :debug)

# Or use structured error information
{:error, error} = Lather.DynamicClient.call(client, "Operation", %{})
debug_info = Lather.Error.extract_debug_context(error)
IO.inspect(debug_info, label: "Debug Info")
```

### Common Issues

1. **WSDL Parsing Errors**: Ensure the WSDL URL is accessible and valid
2. **SSL Certificate Issues**: Configure SSL options for self-signed certificates
3. **Timeout Errors**: Increase timeout values for slow services
4. **Authentication Failures**: Verify credentials and authentication method
5. **Parameter Validation**: Check parameter names and types match WSDL

## Migration from Other SOAP Libraries

### From HTTPoison-based Solutions

```elixir
# Old approach with hardcoded requests
def get_user(user_id) do
  soap_body = """
  <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
    <soap:Body>
      <GetUser xmlns="http://example.com">
        <userId>#{user_id}</userId>
      </GetUser>
    </soap:Body>
  </soap:Envelope>
  """
  
  HTTPoison.post(url, soap_body, headers)
end

# New approach with Lather
def get_user(user_id) do
  Lather.DynamicClient.call(client, "GetUser", %{"userId" => user_id})
end
```

### From Detergent

```elixir
# Old Detergent approach
{:ok, wsdl} = Detergent.parse_wsdl("http://service.wsdl")
{:ok, response} = Detergent.call(wsdl, "GetUser", %{userId: "123"})

# New Lather approach
{:ok, client} = Lather.DynamicClient.new("http://service.wsdl")
{:ok, response} = Lather.DynamicClient.call(client, "GetUser", %{"userId" => "123"})
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to Lather.

## License

MIT License - see [LICENSE](LICENSE) for details.