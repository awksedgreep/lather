# Lather API Documentation

This document provides detailed API reference for the Lather SOAP library.

## Modules Overview

**Core Modules:**
- `Lather` - Main module and entry point for the library
- `Lather.Application` - OTP application supervision and startup
- `Lather.Client` - Low-level SOAP client for custom implementations
- `Lather.DynamicClient` - High-level client for any SOAP service
- `Lather.Error` - Comprehensive error handling and SOAP fault parsing

**Server Modules:**
- `Lather.Server` - SOAP server implementation and configuration
- `Lather.Server.DSL` - Domain-specific language for defining SOAP services
- `Lather.Server.Plug` - Plug integration for hosting SOAP endpoints
- `Lather.Server.EnhancedPlug` - Advanced Plug with additional features
- `Lather.Server.WSDLGenerator` - Generates WSDL documents from service definitions
- `Lather.Server.EnhancedWSDLGenerator` - Extended WSDL generation with complex types
- `Lather.Server.FormGenerator` - Generates HTML forms for testing SOAP operations
- `Lather.Server.Handler` - Request handling and operation dispatching
- `Lather.Server.RequestParser` - Parses incoming SOAP requests
- `Lather.Server.ResponseBuilder` - Builds SOAP responses from handler results

**SOAP Processing:**
- `Lather.Soap.Envelope` - SOAP envelope construction and manipulation
- `Lather.Soap.Body` - SOAP body element handling
- `Lather.Soap.Header` - SOAP header element handling
- `Lather.Operation.Builder` - Dynamic SOAP request building
- `Lather.Wsdl.Analyzer` - WSDL parsing and analysis utilities

**HTTP & Transport:**
- `Lather.Http.Transport` - HTTP transport layer for SOAP requests
- `Lather.Http.Pool` - Connection pool management via Finch

**Authentication:**
- `Lather.Auth.Basic` - Basic HTTP authentication
- `Lather.Auth.WSSecurity` - WS-Security authentication with username tokens

**XML Processing:**
- `Lather.Xml.Builder` - XML document construction from Elixir data
- `Lather.Xml.Parser` - XML document parsing to Elixir structures

**Types:**
- `Lather.Types.Mapper` - Type conversion between XML and Elixir
- `Lather.Types.Generator` - Dynamic struct generation from WSDL types

**MTOM/Attachments:**
- `Lather.Mtom.Attachment` - Binary attachment handling for SOAP messages
- `Lather.Mtom.Builder` - Builds MTOM-encoded multipart messages
- `Lather.Mtom.Mime` - MIME type handling and multipart parsing

## Lather.Application

OTP application supervisor for Lather. Starts and manages the Finch HTTP client pool used for SOAP requests.

### Supervision Tree

The application starts a supervision tree with the following children:

- `Finch` - HTTP client pool (named `Lather.Finch`)

The supervisor uses a `:one_for_one` strategy, meaning if the Finch pool crashes, only it will be restarted.

### Automatic Startup

Lather is configured as an OTP application, so the supervision tree starts automatically when your application starts. No manual intervention is required.

### Manual Startup

If you need to start Lather manually (e.g., in a script or test):

```elixir
{:ok, _pid} = Application.ensure_all_started(:lather)
```

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

## Lather.Soap.Body

SOAP body utilities for creating and managing SOAP body content, including parameter serialization and response parsing.

### Functions

#### create/3

Creates a SOAP body element for the given operation and parameters.

```elixir
@spec create(atom() | String.t(), map(), keyword()) :: map()
```

**Parameters:**
- `operation` - Operation name (atom or string)
- `params` - Operation parameters (map)
- `options` - Body options

**Options:**
- `:namespace` - Target namespace for the operation
- `:namespace_prefix` - Prefix for the target namespace

**Example:**
```elixir
Lather.Soap.Body.create(:get_user, %{id: 123}, namespace: "http://example.com")
# => %{
#   "get_user" => %{
#     "@xmlns" => "http://example.com",
#     "id" => 123
#   }
# }
```

#### serialize_params/1

Serializes Elixir data structures to XML-compatible format.

```elixir
@spec serialize_params(any()) :: any()
```

Handles various Elixir types including maps, lists, atoms, booleans, DateTime, Date, Time, and strings, converting them to XML-safe representations.

#### validate_params/2

Validates parameters against expected types and constraints.

```elixir
@spec validate_params(map(), map()) :: :ok | {:error, [String.t()]}
```

**Parameters:**
- `params` - Parameters to validate
- `schema` - Validation schema (map)

**Schema Format:**
```elixir
%{
  "id" => [:required, :integer],
  "name" => [:required, :string, {:max_length, 50}],
  "email" => [:optional, :string, :email]
}
```

## Lather.Soap.Header

SOAP header utilities for creating and managing SOAP headers, including authentication headers and custom header elements.

### Functions

#### username_token/3

Creates a WS-Security UsernameToken header.

```elixir
@spec username_token(String.t(), String.t(), keyword()) :: map()
```

**Parameters:**
- `username` - Username for authentication
- `password` - Password for authentication
- `options` - Header options

**Options:**
- `:password_type` - `:text` or `:digest` (default: `:text`)
- `:include_nonce` - Whether to include a nonce (default: `true` for digest)
- `:include_created` - Whether to include timestamp (default: `true`)

**Example:**
```elixir
Lather.Soap.Header.username_token("user", "pass")
# => %{
#   "wsse:Security" => %{
#     "@xmlns:wsse" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
#     "wsse:UsernameToken" => %{...}
#   }
# }
```

#### timestamp/1

Creates a WS-Security timestamp header.

```elixir
@spec timestamp(keyword()) :: map()
```

**Options:**
- `:ttl` - Time to live in seconds (default: 300)

#### username_token_with_timestamp/3

Creates a combined WS-Security header with both UsernameToken and Timestamp.

```elixir
@spec username_token_with_timestamp(String.t(), String.t(), keyword()) :: map()
```

**Parameters:**
- `username` - Username for authentication
- `password` - Password for authentication
- `options` - Combined options for both UsernameToken and Timestamp

#### session/2

Creates a session header for maintaining session state.

```elixir
@spec session(String.t(), keyword()) :: map()
```

**Parameters:**
- `session_id` - The session ID
- `options` - Additional options

**Options:**
- `:header_name` - Custom header name (default: "SessionId")
- `:namespace` - Custom namespace

**Example:**
```elixir
Lather.Soap.Header.session("session_12345")
# => %{"SessionId" => "session_12345"}
```

#### custom/3

Creates a custom header element.

```elixir
@spec custom(String.t(), map() | String.t(), map()) :: map()
```

**Parameters:**
- `name` - Header element name
- `content` - Header content (map or string)
- `attributes` - Element attributes

**Example:**
```elixir
Lather.Soap.Header.custom("MyHeader", %{"value" => "test"}, %{"xmlns" => "http://example.com"})
# => %{"MyHeader" => %{"@xmlns" => "http://example.com", "value" => "test"}}
```

#### merge_headers/1

Merges multiple header elements into a single header map.

```elixir
@spec merge_headers([map()]) :: map()
```

**Example:**
```elixir
header1 = Lather.Soap.Header.session("session_123")
header2 = Lather.Soap.Header.custom("MyApp", "v1.0")
Lather.Soap.Header.merge_headers([header1, header2])
# => %{"SessionId" => "session_123", "MyApp" => "v1.0"}
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

## Lather.Http.Pool

Connection pool configuration for HTTP transport. Provides configuration and utilities for managing Finch connection pools optimized for SOAP requests.

### Functions

#### default_config/0

Returns the default pool configuration for SOAP clients.

```elixir
@spec default_config() :: keyword()
```

Optimized for typical SOAP usage patterns with reasonable defaults for connection pooling, timeouts, and SSL settings.

**Default Configuration:**
```elixir
[
  pool_timeout: 5_000,
  pool_max_idle_time: 30_000,
  http2_max_concurrent_streams: 1000,
  transport_opts: [
    verify: :verify_peer,
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ]
]
```

#### config_for_endpoint/2

Creates a pool configuration for a specific endpoint.

```elixir
@spec config_for_endpoint(String.t(), keyword()) :: keyword()
```

**Parameters:**
- `endpoint` - The SOAP endpoint URL
- `overrides` - Configuration overrides (optional)

Allows customization of pool settings per endpoint, useful for services with different performance characteristics.

**Example:**
```elixir
config = Lather.Http.Pool.config_for_endpoint(
  "https://api.example.com/soap",
  pool_timeout: 10_000
)
```

#### validate_config/1

Validates pool configuration options.

```elixir
@spec validate_config(keyword()) :: :ok | {:error, String.t()}
```

## Lather.Xml.Builder

XML document construction.

### Functions

#### build/1

Builds an XML document from Elixir data structures.

```elixir
@spec build(map()) :: {:ok, String.t()} | {:error, any()}
```

**Example:**
```elixir
xml = Lather.Xml.Builder.build(%{
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

## Lather.Xml.Parser

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

**Parameters:**
- `username` - The username for authentication
- `password` - The password for authentication
- `options` - Keyword options for token configuration

**Options:**
- `:password_type` - Password type (`:text` or `:digest`, default: `:text`)
- `:nonce` - Custom nonce value (auto-generated if not provided)
- `:created` - Custom created timestamp (auto-generated if not provided)

**Example:**
```elixir
# Username token with password digest
username_token = Lather.Auth.WSSecurity.username_token("user", "pass", password_type: :digest)
```

## MTOM Modules

MTOM (Message Transmission Optimization Mechanism) modules enable efficient binary data transmission in SOAP messages using XOP (XML-binary Optimized Packaging).

### Lather.Mtom.Attachment

Defines the structure for binary attachments in MTOM messages and provides utilities for creating, validating, and managing attachments.

#### Types

```elixir
@type t :: %Lather.Mtom.Attachment{
  id: String.t(),
  content_type: String.t(),
  content_transfer_encoding: String.t(),
  data: binary(),
  content_id: String.t(),
  size: non_neg_integer()
}
```

#### Functions

##### new/3

Creates a new attachment from binary data and content type.

```elixir
@spec new(binary(), String.t(), keyword()) :: t()
```

**Parameters:**
- `data` - Binary data for the attachment
- `content_type` - MIME content type (e.g., "application/pdf")
- `options` - Additional options

**Options:**
- `:content_id` - Custom Content-ID (auto-generated if not provided)
- `:content_transfer_encoding` - Transfer encoding (default: "binary")
- `:validate` - Whether to validate the attachment (default: true)

**Example:**
```elixir
attachment = Lather.Mtom.Attachment.new(pdf_data, "application/pdf")

attachment = Lather.Mtom.Attachment.new(image_data, "image/jpeg",
  content_id: "custom-id-123"
)
```

##### from_file/2

Creates an attachment from a file path.

```elixir
@spec from_file(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
```

**Example:**
```elixir
{:ok, attachment} = Lather.Mtom.Attachment.from_file("document.pdf")
{:ok, attachment} = Lather.Mtom.Attachment.from_file("image.jpg", content_type: "image/jpeg")
```

##### validate/1

Validates an attachment structure and content.

```elixir
@spec validate(t()) :: :ok | {:error, atom()}
```

**Example:**
```elixir
:ok = Lather.Mtom.Attachment.validate(attachment)
{:error, :attachment_too_large} = Lather.Mtom.Attachment.validate(huge_attachment)
```

##### content_id_header/1

Generates a Content-ID header value for the attachment.

```elixir
@spec content_id_header(t()) :: String.t()
```

##### cid_reference/1

Generates a CID reference for XOP includes.

```elixir
@spec cid_reference(t()) :: String.t()
```

**Example:**
```elixir
cid_ref = Lather.Mtom.Attachment.cid_reference(attachment)
# "cid:attachment123@lather.soap"
```

##### xop_include/1

Creates an XOP Include element for the attachment.

```elixir
@spec xop_include(t()) :: map()
```

##### is_attachment?/1

Checks if a parameter value represents an attachment.

```elixir
@spec is_attachment?(any()) :: boolean()
```

**Example:**
```elixir
Lather.Mtom.Attachment.is_attachment?({:attachment, data, "application/pdf"}) # true
Lather.Mtom.Attachment.is_attachment?("regular string") # false
```

##### from_tuple/1

Converts an attachment tuple to an Attachment struct.

```elixir
@spec from_tuple(tuple()) :: {:ok, t()} | {:error, term()}
```

**Example:**
```elixir
{:ok, attachment} = Lather.Mtom.Attachment.from_tuple({:attachment, data, "application/pdf"})
{:ok, attachment} = Lather.Mtom.Attachment.from_tuple({:attachment, data, "image/jpeg", [content_id: "img1"]})
```

### Lather.Mtom.Builder

Constructs MTOM multipart SOAP messages by extracting binary attachments from parameters, replacing them with XOP Include references, and packaging everything into a multipart/related MIME message.

#### Functions

##### build_mtom_message/3

Builds a complete MTOM message with SOAP envelope and binary attachments.

```elixir
@spec build_mtom_message(atom() | String.t(), map(), keyword()) ::
        {:ok, {String.t(), binary()}} | {:error, term()}
```

**Parameters:**
- `operation` - SOAP operation name (atom or string)
- `parameters` - Parameters map potentially containing attachment tuples
- `options` - SOAP envelope building options

**Options:**
- `:namespace` - Target namespace for the operation
- `:headers` - SOAP headers to include
- `:version` - SOAP version (`:v1_1` or `:v1_2`)
- `:boundary` - Custom MIME boundary (auto-generated if not provided)
- `:enable_mtom` - Force MTOM even without attachments (default: auto-detect)

**Example:**
```elixir
params = %{
  "document" => {:attachment, pdf_data, "application/pdf"},
  "metadata" => %{"title" => "Report"}
}

{:ok, {content_type, body}} = Lather.Mtom.Builder.build_mtom_message(
  :UploadDocument,
  params,
  namespace: "http://example.com/upload"
)
```

##### process_parameters/1

Processes parameters to extract attachments and replace with XOP includes.

```elixir
@spec process_parameters(map()) :: {:ok, {map(), [Attachment.t()]}} | {:error, term()}
```

**Example:**
```elixir
params = %{"file" => {:attachment, data, "application/pdf"}}
{:ok, {new_params, [attachment]}} = Lather.Mtom.Builder.process_parameters(params)
# new_params contains XOP Include reference instead of binary data
```

##### has_attachments?/1

Checks if parameters contain any attachment tuples.

```elixir
@spec has_attachments?(map()) :: boolean()
```

**Example:**
```elixir
Lather.Mtom.Builder.has_attachments?(%{"file" => {:attachment, data, "pdf"}}) # true
Lather.Mtom.Builder.has_attachments?(%{"name" => "John"}) # false
```

##### validate_attachments/1

Validates that all attachment tuples in parameters are properly formatted.

```elixir
@spec validate_attachments(map()) :: :ok | {:error, term()}
```

##### estimate_message_size/2

Estimates the total size of a message including all attachments.

```elixir
@spec estimate_message_size(map(), non_neg_integer()) :: non_neg_integer()
```

### Lather.Mtom.Mime

Provides functions for building and parsing multipart/related MIME messages used in MTOM.

#### Functions

##### generate_boundary/0

Generates a unique boundary string for multipart messages.

```elixir
@spec generate_boundary() :: String.t()
```

**Example:**
```elixir
boundary = Lather.Mtom.Mime.generate_boundary()
# "uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

##### build_multipart_message/3

Builds a complete multipart/related MIME message with SOAP envelope and attachments.

```elixir
@spec build_multipart_message(binary(), [Attachment.t()], keyword()) ::
        {String.t(), binary()}
```

**Parameters:**
- `soap_envelope` - The SOAP envelope XML as binary
- `attachments` - List of Attachment structs
- `options` - Additional options

**Options:**
- `:boundary` - Custom boundary (auto-generated if not provided)
- `:soap_content_type` - SOAP part content type (default: "application/xop+xml")
- `:soap_charset` - SOAP part charset (default: "UTF-8")

**Example:**
```elixir
{content_type, body} = Lather.Mtom.Mime.build_multipart_message(soap_xml, attachments)
```

##### parse_multipart_message/3

Parses a multipart/related MIME message.

```elixir
@spec parse_multipart_message(String.t(), binary(), keyword()) ::
        {:ok, {binary(), [map()]}} | {:error, term()}
```

**Example:**
```elixir
{:ok, {soap_xml, attachments}} = Lather.Mtom.Mime.parse_multipart_message(content_type, body)
```

##### extract_boundary/1

Extracts the boundary parameter from a Content-Type header.

```elixir
@spec extract_boundary(String.t()) :: {:ok, String.t()} | {:error, atom()}
```

**Example:**
```elixir
{:ok, boundary} = Lather.Mtom.Mime.extract_boundary("multipart/related; boundary=\"uuid:123\"")
```

##### parse_headers/1

Parses MIME headers from a header section.

```elixir
@spec parse_headers(binary()) :: map()
```

**Example:**
```elixir
headers = Lather.Mtom.Mime.parse_headers("Content-Type: application/pdf\r\nContent-ID: <att1>")
# %{"content-type" => "application/pdf", "content-id" => "<att1>"}
```

##### build_content_type_header/3

Builds a Content-Type header for multipart/related messages.

```elixir
@spec build_content_type_header(String.t(), String.t(), String.t()) :: String.t()
```

##### validate_content_type/1

Validates a multipart/related Content-Type header.

```elixir
@spec validate_content_type(String.t()) :: :ok | {:error, atom()}
```

## Server Modules

Lather provides a complete SOAP server implementation for building web services in Elixir.

### Lather.Server

The main module for creating SOAP service modules. Use `use Lather.Server` to define a SOAP service.

#### Macros

##### __using__/1

Sets up a module as a SOAP service with automatic WSDL generation.

```elixir
defmodule MyApp.UserService do
  use Lather.Server, namespace: "http://example.com/users", service_name: "UserService"

  # Define operations using @soap_operation attribute or DSL macros
end
```

#### Functions

##### soap_fault/3

Creates a SOAP fault response.

```elixir
@spec soap_fault(String.t(), String.t(), term() | nil) :: {:soap_fault, map()}
```

**Example:**
```elixir
soap_fault("Client", "User not found", %{user_id: "123"})
```

##### validate_required_params/2

Validates that required operation parameters are present.

```elixir
@spec validate_required_params(map(), map()) :: :ok | {:error, String.t()}
```

##### validate_param_types/2

Validates parameter types according to operation definition.

```elixir
@spec validate_param_types(map(), map()) :: :ok | {:error, String.t()}
```

##### format_response/2

Formats operation response according to SOAP conventions.

```elixir
@spec format_response(term(), map()) :: {:ok, map()} | {:soap_fault, map()}
```

---

### Lather.Server.DSL

Domain Specific Language for defining SOAP operations and types with a declarative syntax.

#### Macros

##### soap_operation/2

Defines a SOAP operation with metadata for WSDL generation.

```elixir
soap_operation "GetUser" do
  description "Retrieves a user by ID"

  input do
    parameter "userId", :string, required: true, description: "User identifier"
    parameter "includeDetails", :boolean, required: false, default: false
  end

  output do
    parameter "user", "User", description: "User information"
  end

  soap_action "http://example.com/GetUser"
end

def get_user(params) do
  # Implementation
end
```

##### soap_type/2

Defines a complex type for use in operations.

```elixir
soap_type "User" do
  type_description "User information"

  element "id", :string, required: true
  element "name", :string, required: true
  element "email", :string, required: false
  element "created_at", :dateTime, required: true
end
```

##### soap_auth/1

Defines authentication requirements for operations.

```elixir
soap_auth do
  basic_auth realm: "SOAP Service"
  # or
  ws_security required: true
  # or
  custom_auth handler: MyApp.CustomAuth
end
```

##### input/1, output/1

Defines input and output parameter blocks within an operation.

##### parameter/3

Defines a parameter within an input or output block.

```elixir
parameter "userId", :string, required: true, description: "User ID", min_occurs: 1, max_occurs: 1
```

##### element/3

Defines an element within a complex type.

```elixir
element "name", :string, required: true, description: "User name"
```

##### description/1, type_description/1

Sets descriptions for operations and types.

##### basic_auth/1, ws_security/1, custom_auth/1

Authentication configuration macros for use within `soap_auth` blocks.

---

### Lather.Server.Plug

Plug implementation for SOAP server endpoints. Requires the `:plug` dependency.

#### Usage

```elixir
# In Phoenix router
scope "/soap" do
  pipe_through :api
  post "/users", Lather.Server.Plug, service: MyApp.UserService
end

# As standalone Plug
plug Lather.Server.Plug, service: MyApp.UserService
```

#### Options

- `:service` - The SOAP service module (required)
- `:path` - Base path for WSDL generation (default: `"/"`)
- `:auth_handler` - Custom authentication handler module
- `:validate_params` - Enable parameter validation (default: `true`)
- `:generate_wsdl` - Enable WSDL generation endpoint (default: `true`)

#### Functions

##### init/1

Initializes the Plug with options.

```elixir
@spec init(keyword()) :: map()
```

##### call/2

Handles incoming HTTP requests (GET for WSDL, POST for SOAP operations).

```elixir
@spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
```

---

### Lather.Server.EnhancedPlug

Enhanced Plug implementation with web form interface and multi-protocol support.

#### Features

- Interactive web forms for testing operations
- SOAP 1.1, SOAP 1.2, and JSON protocol support
- Enhanced WSDL generation with multi-protocol bindings
- Service overview with complete operation documentation

#### URL Patterns

- `GET /service` - Service overview with operations list
- `GET /service?wsdl` - Standard WSDL download
- `GET /service?wsdl&enhanced=true` - Multi-protocol WSDL
- `GET /service?op=OperationName` - Interactive operation form
- `POST /service` - SOAP 1.1 endpoint
- `POST /service/v1.2` - SOAP 1.2 endpoint
- `POST /service/api` - JSON/REST endpoint

#### Usage

```elixir
# In Phoenix router
scope "/soap" do
  pipe_through :api
  match :*, "/users", Lather.Server.EnhancedPlug, service: MyApp.UserService
  match :*, "/users/*path", Lather.Server.EnhancedPlug, service: MyApp.UserService
end
```

#### Options

- `:service` - The SOAP service module (required)
- `:base_path` - Base path for service (default: `"/soap"`)
- `:enable_forms` - Enable web form interface (default: `true`)
- `:enable_json` - Enable JSON endpoints (default: `true`)
- `:auth_handler` - Custom authentication handler
- `:validate_params` - Enable parameter validation (default: `true`)

#### Functions

##### init/1

```elixir
@spec init(keyword()) :: map()
```

##### call/2

```elixir
@spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
```

---

### Lather.Server.Handler

Generic HTTP handler for SOAP server endpoints without requiring Plug. Works with any HTTP server.

#### Usage

```elixir
# In Phoenix controller
defmodule MyAppWeb.SOAPController do
  use MyAppWeb, :controller

  def handle_soap(conn, _params) do
    case Lather.Server.Handler.handle_request(
      conn.method,
      conn.request_path,
      conn.req_headers,
      conn.assigns.raw_body,
      MyApp.UserService
    ) do
      {:ok, status, headers, body} ->
        conn |> put_status(status) |> text(body)
      {:error, status, headers, body} ->
        conn |> put_status(status) |> text(body)
    end
  end
end
```

#### Functions

##### handle_request/6

Handles a SOAP HTTP request.

```elixir
@spec handle_request(String.t(), String.t(), [{String.t(), String.t()}], String.t(), module(), keyword()) ::
  {:ok, integer(), [{String.t(), String.t()}], String.t()} |
  {:error, integer(), [{String.t(), String.t()}], String.t()}
```

**Parameters:**
- `method` - HTTP method (`"GET"` or `"POST"`)
- `path` - Request path
- `headers` - Request headers
- `body` - Request body
- `service` - SOAP service module
- `opts` - Options (`:validate_params`, `:generate_wsdl`, `:base_url`)

---

### Lather.Server.RequestParser

Parses incoming SOAP requests and extracts operation details and parameters.

#### Functions

##### parse/1

Parses a SOAP request XML and extracts the operation name and parameters.

```elixir
@spec parse(String.t()) :: {:ok, %{operation: String.t(), params: map()}} | {:error, {:parse_error, String.t()}}
```

**Example:**
```elixir
{:ok, %{operation: "GetUser", params: %{"userId" => "123"}}} =
  Lather.Server.RequestParser.parse(soap_xml)
```

---

### Lather.Server.ResponseBuilder

Builds SOAP response XML from operation results.

#### Functions

##### build_response/2

Builds a SOAP response envelope containing the operation result.

```elixir
@spec build_response(term(), map()) :: String.t()
```

**Example:**
```elixir
xml = Lather.Server.ResponseBuilder.build_response(
  %{"user" => %{"id" => "123", "name" => "John"}},
  %{name: "GetUser"}
)
```

##### build_fault/1

Builds a SOAP fault response.

```elixir
@spec build_fault(map() | nil) :: String.t()
```

**Example:**
```elixir
xml = Lather.Server.ResponseBuilder.build_fault(%{
  fault_code: "Client",
  fault_string: "User not found",
  detail: %{user_id: "123"}
})
```

---

### Lather.Server.WSDLGenerator

Generates WSDL files from SOAP service definitions.

#### Functions

##### generate/2

Generates a complete WSDL document for a SOAP service.

```elixir
@spec generate(map(), String.t()) :: String.t()
```

**Parameters:**
- `service_info` - Service metadata from `__soap_service__/0`
- `base_url` - Base URL for the service endpoint

**Example:**
```elixir
service_info = MyApp.UserService.__soap_service__()
wsdl = Lather.Server.WSDLGenerator.generate(service_info, "http://example.com/soap")
```

---

### Lather.Server.EnhancedWSDLGenerator

Enhanced WSDL generator with multi-protocol support (SOAP 1.1, SOAP 1.2, HTTP/REST).

#### Functions

##### generate/3

Generates a comprehensive multi-protocol WSDL document.

```elixir
@spec generate(map(), String.t(), keyword()) :: String.t()
```

**Options:**
- `:protocols` - List of protocols to include (default: `[:soap_1_1, :soap_1_2, :http]`)
- `:base_path` - Base path for REST endpoints (default: `"/api"`)
- `:include_json` - Include JSON content type support (default: `true`)

**Example:**
```elixir
service_info = MyApp.UserService.__soap_service__()
wsdl = Lather.Server.EnhancedWSDLGenerator.generate(
  service_info,
  "http://example.com",
  protocols: [:soap_1_1, :soap_1_2]
)
```

---

### Lather.Server.FormGenerator

Generates HTML forms and documentation pages for SOAP operations, similar to .NET Web Services.

#### Functions

##### generate_operation_page/4

Generates a complete HTML page for an operation with testing forms and protocol examples.

```elixir
@spec generate_operation_page(map(), map(), String.t(), keyword()) :: String.t()
```

**Parameters:**
- `service_info` - Service metadata
- `operation` - Operation metadata
- `base_url` - Base URL for the service
- `options` - Additional options

##### generate_service_overview/3

Generates a service overview page with all operations listed.

```elixir
@spec generate_service_overview(map(), String.t(), keyword()) :: String.t()
```

**Example:**
```elixir
service_info = MyApp.UserService.__soap_service__()
html = Lather.Server.FormGenerator.generate_service_overview(
  service_info,
  "http://example.com/soap"
)
```

---

### Complete Server Example

```elixir
defmodule MyApp.CalculatorService do
  use Lather.Server,
    namespace: "http://example.com/calculator",
    service_name: "Calculator"

  # Define a complex type
  soap_type "CalculationResult" do
    type_description "Result of a calculation"
    element "value", :decimal, required: true
    element "operation", :string, required: true
    element "timestamp", :dateTime, required: true
  end

  # Define an operation
  soap_operation "Add" do
    description "Adds two numbers"

    input do
      parameter "a", :decimal, required: true, description: "First number"
      parameter "b", :decimal, required: true, description: "Second number"
    end

    output do
      parameter "result", "CalculationResult"
    end

    soap_action "http://example.com/calculator/Add"
  end

  def add(%{"a" => a, "b" => b}) do
    result = Decimal.add(Decimal.new(a), Decimal.new(b))
    {:ok, %{
      "result" => %{
        "value" => Decimal.to_string(result),
        "operation" => "add",
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }}
  end
end

# Mount in Phoenix router
scope "/soap" do
  pipe_through :api
  match :*, "/calculator", Lather.Server.EnhancedPlug, service: MyApp.CalculatorService
  match :*, "/calculator/*path", Lather.Server.EnhancedPlug, service: MyApp.CalculatorService
end
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