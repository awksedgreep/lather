# Lather Examples

This directory contains practical examples demonstrating how to use the Lather SOAP library with different types of SOAP services and scenarios.

## Example Files

### Basic Examples

#### Weather Service (`weather_service.ex`)

A simple example using a public weather SOAP service that demonstrates:

- **Basic SOAP Operations**: Connecting to a public service and making simple calls
- **Error Handling**: Handling SOAP faults and network errors gracefully
- **Response Processing**: Parsing and displaying different response formats
- **Async Operations**: Making multiple SOAP calls concurrently

**Run the example:**
```elixir
cd examples
elixir weather_service.ex
```

**Key Features Demonstrated:**
- Basic client creation
- Simple parameter passing
- Response handling
- Error recovery
- Concurrent operations

### Advanced Examples

#### Enterprise Service (`enterprise_service.ex`)

A comprehensive example for enterprise SOAP services that demonstrates:

- **Authentication**: Basic Auth and WS-Security implementations
- **SSL/TLS Configuration**: Secure connections with certificate validation
- **Complex Parameters**: Nested structures and arrays
- **Error Recovery**: Automatic retry with exponential backoff
- **Connection Management**: Custom connection pooling

**Run the example:**
```elixir
# Set environment variables for authentication
export SOAP_USERNAME="your_username"
export SOAP_PASSWORD="your_password"

cd examples
elixir enterprise_service.ex
```

**Key Features Demonstrated:**
- Enterprise authentication patterns
- Complex nested parameter structures
- Comprehensive error handling
- Retry logic with backoff
- SSL/TLS security configuration
- Custom headers and options

#### Type Mapping (`type_mapping.ex`)

An advanced example focusing on type conversion and validation:

- **Dynamic Struct Generation**: Creating Elixir structs from WSDL types
- **Type Validation**: Validating parameters against WSDL schemas
- **Custom Type Mappers**: Converting special XML formats
- **Complex Data Structures**: Working with deeply nested enterprise data

**Run the example:**
```elixir
cd examples
elixir type_mapping.ex
```

**Key Features Demonstrated:**
- Automatic struct generation
- Type validation and conversion
- Custom type parsing functions
- XML round-trip conversion
- Complex nested data handling

#### MTOM Client (`mtom_client.ex`)

An example demonstrating MTOM (Message Transmission Optimization Mechanism) for handling binary attachments in SOAP messages:

- **Binary Attachments**: Sending and receiving files via SOAP
- **MTOM Encoding**: Efficient binary data transmission using XOP
- **Multipart MIME**: Working with multipart/related messages
- **File Upload/Download**: Practical file transfer patterns

**Run the example:**
```elixir
cd examples
elixir mtom_client.ex
```

**Key Features Demonstrated:**
- MTOM-enabled SOAP requests
- Binary attachment handling
- File upload and download operations
- Content-Type negotiation
- Large file streaming

## Server Examples

See the [servers/](servers/) directory for examples of building SOAP servers with Lather, including:

- Basic service definitions
- Calculator and user management services
- Phoenix and Plug integration
- WS-Security authentication

## Running Examples

### Prerequisites

1. **Start the Lather application:**
   ```elixir
   # In your application or IEx
   {:ok, _} = Application.ensure_all_started(:lather)
   ```

2. **Configure HTTP client:**
   ```elixir
   # The examples expect Finch to be running
   children = [
     {Finch, name: Lather.Finch}
   ]
   {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
   ```

### Interactive Examples

You can also run examples interactively in IEx:

```elixir
# Start IEx with the project
iex -S mix

# Load an example
c "examples/weather_service.ex"

# Run specific functions
WeatherServiceExample.run()
WeatherServiceExample.show_operation_details("GetWeather")

# Try async operations
cities = [
  {"New York", "United States"},
  {"London", "United Kingdom"},
  {"Tokyo", "Japan"}
]
WeatherServiceExample.get_weather_async(cities)
```

## Example Scenarios

### Basic SOAP Service Integration

**Scenario**: Integrating with a simple web service

```elixir
# Connect to service
{:ok, client} = Lather.DynamicClient.new("http://service.wsdl")

# List available operations
operations = Lather.DynamicClient.list_operations(client)

# Call an operation
{:ok, response} = Lather.DynamicClient.call(client, "GetData", %{
  "id" => "12345"
})
```

**See**: `weather_service.ex` for a complete implementation

### Enterprise Service with Authentication

**Scenario**: Connecting to a corporate SOAP service with security

```elixir
# Configure authentication and SSL
{:ok, client} = Lather.DynamicClient.new(
  "https://enterprise.company.com/service?wsdl",
  basic_auth: {"username", "password"},
  ssl_options: [verify: :verify_peer],
  timeout: 60_000
)

# Make authenticated calls
{:ok, response} = Lather.DynamicClient.call(client, "GetUserData", %{
  "userId" => "employee123",
  "includeDetails" => true
})
```

**See**: `enterprise_service.ex` for advanced authentication patterns

### Complex Data Structures

**Scenario**: Working with complex nested enterprise data

```elixir
# Complex parameter structure
params = %{
  "request" => %{
    "searchCriteria" => %{
      "filters" => [
        %{"field" => "department", "value" => "Engineering"},
        %{"field" => "active", "value" => true}
      ],
      "sorting" => [%{"field" => "lastName", "direction" => "asc"}],
      "pagination" => %{"pageSize" => 25, "pageNumber" => 1}
    },
    "options" => %{
      "includeMetadata" => true,
      "format" => "detailed"
    }
  }
}

{:ok, response} = Lather.DynamicClient.call(client, "SearchEmployees", params)
```

**See**: `type_mapping.ex` for type validation and conversion

## Testing with Examples

### Mock Services

Use the examples as a basis for testing your SOAP integrations:

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  
  test "SOAP service integration" do
    # Use patterns from weather_service.ex
    {:ok, client} = Lather.DynamicClient.new("http://mock.service.wsdl")
    
    assert {:ok, _response} = Lather.DynamicClient.call(client, "TestOp", %{})
  end
end
```

### Error Simulation

Test error handling using patterns from the examples:

```elixir
# Test retry logic (from enterprise_service.ex)
defp execute_with_retry(client, operation, params, retry_count \\ 0) do
  case Lather.DynamicClient.call(client, operation, params) do
    {:ok, response} ->
      {:ok, response}
    {:error, error} ->
      if retry_count < 3 and Lather.Error.recoverable?(error) do
        :timer.sleep(1000 * (retry_count + 1))
        execute_with_retry(client, operation, params, retry_count + 1)
      else
        {:error, error}
      end
  end
end
```

## Best Practices from Examples

### 1. Connection Management

```elixir
# Reuse clients (from enterprise_service.ex)
defmodule MyApp.SOAPClients do
  def get_client do
    case :persistent_term.get(:soap_client, nil) do
      nil ->
        {:ok, client} = Lather.DynamicClient.new(wsdl_url(), client_options())
        :persistent_term.put(:soap_client, client)
        client
      client ->
        client
    end
  end
end
```

### 2. Error Handling

```elixir
# Comprehensive error handling (from enterprise_service.ex)
case Lather.DynamicClient.call(client, operation, params) do
  {:ok, response} ->
    handle_success(response)
    
  {:error, %{type: :soap_fault} = fault} ->
    handle_soap_fault(fault)
    
  {:error, %{type: :http_error} = error} ->
    handle_http_error(error)
    
  {:error, %{type: :transport_error} = error} ->
    if Lather.Error.recoverable?(error) do
      retry_operation()
    else
      handle_transport_error(error)
    end
end
```

### 3. Configuration

```elixir
# Environment-based configuration
defp client_options do
  [
    basic_auth: {get_env("SOAP_USER"), get_env("SOAP_PASS")},
    timeout: get_env("SOAP_TIMEOUT", 30_000),
    ssl_options: ssl_config(),
    headers: custom_headers()
  ]
end
```

## Customizing Examples

### Add Your Own Service

1. Copy an existing example
2. Update the WSDL URL and credentials
3. Modify the operations and parameters
4. Add service-specific error handling

### Custom Type Handling

Add custom type parsers for your service's specific data formats:

```elixir
custom_mappers = %{
  "CustomDate" => &parse_custom_date/1,
  "SpecialFormat" => &parse_special_format/1
}

options = [custom_parsers: custom_mappers]
```

## Contributing Examples

To add new examples:

1. Follow the existing naming pattern
2. Include comprehensive documentation
3. Demonstrate specific features
4. Add error handling examples
5. Include both simple and complex scenarios

Contributions are welcome! Please open an issue or pull request on GitHub.