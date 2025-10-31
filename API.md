# Lather API Documentation

This document provides detailed API reference for the Lather SOAP library.

## Modules Overview

- `Lather.DynamicClient` - High-level client for any SOAP service
- `Lather.Client` - Low-level SOAP client
- `Lather.Wsdl.Analyzer` - WSDL parsing and analysis
- `Lather.Operation.Builder` - Dynamic SOAP request building
- `Lather.Soap.Envelope` - SOAP envelope construction
- `Lather.Http.Transport` - HTTP transport layer
- `Lather.XML.Builder` - XML document building
- `Lather.XML.Parser` - XML document parsing
- `Lather.Types.Mapper` - Type conversion utilities
- `Lather.Types.Generator` - Dynamic struct generation
- `Lather.Auth.Basic` - Basic authentication
- `Lather.Auth.WSSecurity` - WS-Security authentication
- `Lather.Error` - Comprehensive error handling

## Lather.DynamicClient

The main interface for working with SOAP services dynamically.

### Functions

#### new/2

Creates a new dynamic client from a WSDL URL.

```elixir
@spec new(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
```

**Parameters:**
- `wsdl_url` - URL to the WSDL document
- `options` - Client configuration options

**Options:**
- `:basic_auth` - Basic authentication `{username, password}`
- `:ssl_options` - SSL/TLS configuration
- `:timeout` - Request timeout in milliseconds
- `:headers` - Additional HTTP headers
- `:namespace_aware` - Enable namespace-aware parsing

**Example:**
```elixir
{:ok, client} = Lather.DynamicClient.new(
  "https://example.com/service?wsdl",
  basic_auth: {"user", "pass"},
  timeout: 30_000
)
```

#### call/4

Calls a SOAP operation with the given parameters.

```elixir
@spec call(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
```

**Parameters:**
- `client` - The dynamic client instance
- `operation_name` - Name of the operation to call
- `parameters` - Map of operation parameters
- `options` - Call-specific options

**Options:**
- `:soap_action` - Override SOAPAction header
- `:validate` - Enable/disable parameter validation (default: true)
- `:timeout` - Override timeout for this call
- `:headers` - Additional headers for this request

**Example:**
```elixir
{:ok, response} = Lather.DynamicClient.call(
  client, 
  "GetUser", 
  %{"userId" => "12345"},
  timeout: 60_000
)
```

#### list_operations/1

Lists all available operations from the WSDL.

```elixir
@spec list_operations(t()) :: [String.t()]
```

**Example:**
```elixir
operations = Lather.DynamicClient.list_operations(client)
# => ["GetUser", "CreateUser", "UpdateUser", "DeleteUser"]
```

#### get_operation_info/2

Gets detailed information about a specific operation.

```elixir
@spec get_operation_info(t(), String.t()) :: {:ok, map()} | {:error, term()}
```

**Example:**
```elixir
{:ok, info} = Lather.DynamicClient.get_operation_info(client, "GetUser")
# => %{
#   name: "GetUser",
#   input_parts: [%{name: "userId", type: "string", required: true}],
#   output_parts: [%{name: "user", type: "User"}],
#   soap_action: "http://example.com/GetUser"
# }
```

#### validate_parameters/3

Validates parameters against operation requirements.

```elixir
@spec validate_parameters(t(), String.t(), map()) :: :ok | {:error, term()}
```

**Example:**
```elixir
case Lather.DynamicClient.validate_parameters(client, "GetUser", %{"userId" => "123"}) do
  :ok -> 
    # Parameters are valid
  {:error, error} -> 
    # Handle validation error
end
```

## Lather.Client

Low-level SOAP client for custom implementations.

### Functions

#### new/2

Creates a new SOAP client.

```elixir
@spec new(String.t(), keyword()) :: t()
```

#### post/3

Sends a SOAP request to the endpoint.

```elixir
@spec post(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

## Lather.Wsdl.Analyzer

WSDL parsing and analysis utilities.

### Functions

#### analyze/2

Analyzes a WSDL document and extracts service information.

```elixir
@spec analyze(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

**Returns a map with:**
- `:operations` - List of available operations
- `:types` - Complex type definitions
- `:bindings` - SOAP binding information
- `:services` - Service endpoints
- `:namespaces` - Namespace declarations

#### extract_operations/1

Extracts operation definitions from parsed WSDL.

```elixir
@spec extract_operations(map()) :: [map()]
```

#### parse_complex_type/1

Parses complex type definitions.

```elixir
@spec parse_complex_type(map()) :: map()
```

## Lather.Operation.Builder

Dynamic SOAP request building.

### Functions

#### build_request/3

Builds a SOAP request for any operation.

```elixir
@spec build_request(map(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
```

#### validate_parameters/2

Validates operation parameters.

```elixir
@spec validate_parameters(map(), map()) :: :ok | {:error, term()}
```

#### parse_response/3

Parses SOAP response into Elixir data structures.

```elixir
@spec parse_response(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
```

## Lather.Soap.Envelope

SOAP envelope construction utilities.

### Functions

#### build/3

Builds a complete SOAP envelope.

```elixir
@spec build(map(), String.t(), keyword()) :: String.t()
```

**Parameters:**
- `body` - SOAP body content
- `namespace` - Target namespace
- `options` - Envelope options

**Options:**
- `:soap_version` - SOAP version (`:soap11` or `:soap12`)
- `:headers` - SOAP headers to include
- `:prefix` - Namespace prefix

#### wrap_body/2

Wraps content in a SOAP body.

```elixir
@spec wrap_body(map(), keyword()) :: map()
```

## Lather.Http.Transport

HTTP transport layer for SOAP requests.

### Functions

#### post/3

Sends an HTTP POST request.

```elixir
@spec post(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

**Parameters:**
- `url` - Request URL
- `body` - Request body
- `options` - HTTP options

**Options:**
- `:timeout` - Request timeout
- `:headers` - HTTP headers
- `:soap_action` - SOAPAction header
- `:ssl_options` - SSL configuration
- `:basic_auth` - Basic authentication

#### validate_url/1

Validates a URL for SOAP requests.

```elixir
@spec validate_url(String.t()) :: :ok | {:error, :invalid_url}
```

#### ssl_options/1

Creates SSL options for secure connections.

```elixir
@spec ssl_options(keyword()) :: keyword()
```

## Lather.XML.Builder

XML document construction.

### Functions

#### build/1

Builds an XML document from Elixir data structures.

```elixir
@spec build(map()) :: String.t()
```

**Example:**
```elixir
xml = Lather.XML.Builder.build(%{
  "GetUser" => %{
    "@xmlns" => "http://example.com",
    "userId" => "12345"
  }
})
# => "<GetUser xmlns=\"http://example.com\"><userId>12345</userId></GetUser>"
```

#### escape/1

Escapes XML content.

```elixir
@spec escape(String.t()) :: String.t()
```

## Lather.XML.Parser

XML document parsing.

### Functions

#### parse/2

Parses XML content into Elixir data structures.

```elixir
@spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

**Options:**
- `:namespace_aware` - Enable namespace handling
- `:custom_parsers` - Custom type parsers

#### extract_namespaces/1

Extracts namespace declarations from XML.

```elixir
@spec extract_namespaces(String.t()) :: map()
```

## Lather.Types.Mapper

Type conversion between XML and Elixir.

### Functions

#### xml_to_elixir/3

Converts XML data to Elixir types.

```elixir
@spec xml_to_elixir(map(), map(), keyword()) :: {:ok, term()} | {:error, term()}
```

#### elixir_to_xml/3

Converts Elixir data to XML representation.

```elixir
@spec elixir_to_xml(term(), map(), keyword()) :: {:ok, map()} | {:error, term()}
```

#### validate_type/3

Validates data against type definitions.

```elixir
@spec validate_type(term(), map(), keyword()) :: :ok | {:error, term()}
```

## Lather.Types.Generator

Dynamic struct generation from WSDL types.

### Functions

#### generate_structs/2

Generates Elixir struct modules from WSDL types.

```elixir
@spec generate_structs(map(), String.t()) :: {:ok, [module()]} | {:error, term()}
```

#### create_struct_instance/3

Creates a struct instance with type validation.

```elixir
@spec create_struct_instance(module(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
```

## Lather.Auth.Basic

Basic HTTP authentication.

### Functions

#### header/2

Creates a Basic authentication header.

```elixir
@spec header(String.t(), String.t()) :: {String.t(), String.t()}
```

## Lather.Auth.WSSecurity

WS-Security authentication.

### Functions

#### username_token/3

Creates a WS-Security username token.

```elixir
@spec username_token(String.t(), String.t(), keyword()) :: map()
```

#### security_header/2

Creates a WS-Security header.

```elixir
@spec security_header(map(), keyword()) :: map()
```

## Lather.Error

Comprehensive error handling.

### Types

#### soap_fault

SOAP fault information.

```elixir
@type soap_fault :: %{
  fault_code: String.t(),
  fault_string: String.t(),
  fault_actor: String.t() | nil,
  detail: map() | nil
}
```

#### transport_error

Transport layer errors.

```elixir
@type transport_error :: %{
  type: :transport_error,
  reason: atom() | String.t(),
  details: map()
}
```

#### http_error

HTTP-level errors.

```elixir
@type http_error :: %{
  type: :http_error,
  status: integer(),
  body: String.t(),
  headers: [{String.t(), String.t()}]
}
```

#### validation_error

Parameter validation errors.

```elixir
@type validation_error :: %{
  type: :validation_error,
  field: String.t(),
  reason: atom(),
  details: map()
}
```

### Functions

#### parse_soap_fault/2

Parses SOAP fault from response.

```elixir
@spec parse_soap_fault(String.t(), keyword()) :: {:ok, soap_fault()} | {:error, term()}
```

#### transport_error/2

Creates a transport error.

```elixir
@spec transport_error(term(), map()) :: transport_error()
```

#### http_error/3

Creates an HTTP error.

```elixir
@spec http_error(integer(), String.t(), [{String.t(), String.t()}]) :: http_error()
```

#### validation_error/3

Creates a validation error.

```elixir
@spec validation_error(String.t(), atom(), map()) :: validation_error()
```

#### format_error/2

Formats errors for display.

```elixir
@spec format_error(term(), keyword()) :: String.t()
```

#### recoverable?/1

Checks if an error is recoverable.

```elixir
@spec recoverable?(term()) :: boolean()
```

#### extract_debug_context/1

Extracts debugging information from errors.

```elixir
@spec extract_debug_context(term()) :: map()
```

## Configuration

### Application Configuration

```elixir
# config/config.exs
config :lather,
  # Default timeout for all requests
  default_timeout: 30_000,
  
  # SSL verification mode
  ssl_verify: :verify_peer,
  
  # Connection pool settings
  finch_pools: %{
    default: [size: 25, count: 1]
  },
  
  # WSDL caching
  cache_wsdl: true,
  cache_ttl: 3600,
  
  # Telemetry events
  telemetry_enabled: true
```

### Runtime Configuration

```elixir
# Override configuration at runtime
Application.put_env(:lather, :default_timeout, 60_000)
```

## Telemetry Events

Lather emits telemetry events for monitoring:

- `[:lather, :request, :start]` - SOAP request started
- `[:lather, :request, :stop]` - SOAP request completed
- `[:lather, :request, :error]` - SOAP request failed
- `[:lather, :wsdl, :parse, :start]` - WSDL parsing started
- `[:lather, :wsdl, :parse, :stop]` - WSDL parsing completed

### Telemetry Example

```elixir
:telemetry.attach_many(
  "lather-handler",
  [
    [:lather, :request, :start],
    [:lather, :request, :stop],
    [:lather, :request, :error]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)
```

## Error Codes

| Code | Type | Description |
|------|------|-------------|
| `operation_not_found` | validation | Operation not defined in WSDL |
| `missing_required_parameter` | validation | Required parameter not provided |
| `invalid_parameter_type` | validation | Parameter type mismatch |
| `unsupported_encoding` | validation | Unsupported SOAP encoding |
| `invalid_soap_response` | validation | Malformed SOAP response |
| `transport_error` | transport | Network/connection error |
| `http_error` | http | HTTP status error |
| `wsdl_error` | wsdl | WSDL parsing error |

## Best Practices

1. **Reuse Clients**: Create clients once and reuse them across requests
2. **Handle Errors**: Always handle different error types appropriately
3. **Set Timeouts**: Configure appropriate timeouts for your use case
4. **Use SSL**: Always use HTTPS in production environments
5. **Cache WSDL**: Enable WSDL caching for better performance
6. **Monitor Operations**: Use telemetry for monitoring and debugging
7. **Validate Parameters**: Use built-in validation to catch errors early
8. **Connection Pooling**: Configure Finch pools for optimal performance