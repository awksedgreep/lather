# Lather Test Gap Analysis

## Overview
This document identifies gaps in the current test coverage for the Lather SOAP library and recommends additional tests to improve reliability and robustness.

---

## Current Test Coverage Summary

### Existing Tests
- **lather_test.exs** - Basic version function test (1 test)
- **client_test.exs** - Client creation and envelope building (6 tests)
- **transport_test.exs** - HTTP transport headers, URL validation, SSL options (9 tests)
- **Integration tests** - Multiple integration test files with real SOAP service calls
  - simple_integration_test.exs
  - integration_test.exs
  - phoenix_integration_test.exs
  - focused_integration_test.exs
  - debug_integration_test.exs

### Module Coverage Analysis

| Module | Covered | Gap |
|--------|---------|-----|
| Lather.Client | Partial | Client.call/4 method not tested |
| Lather.Soap.Envelope | Partial | parse_response/1 not tested, various fault scenarios missing |
| Lather.Http.Transport | Good | Basic coverage exists |
| Lather.Auth.Basic | None | No tests for encode/decode functionality |
| Lather.Auth.WSSecurity | None | No tests for username token, timestamp generation |
| Lather.Error | None | No tests for error formatting, recovery checks |
| Lather.Xml.Builder | None | No tests for XML building, attribute handling, escaping |
| Lather.Xml.Parser | None | No tests for XML parsing |
| Lather.DynamicClient | None | No unit tests (only integration tests exist) |
| Lather.Wsdl.Analyzer | None | No tests for WSDL analysis |
| Lather.Server | None | No tests for server-side functionality |
| Lather.Operation.Builder | None | No tests for operation building |
| Lather.Types.Mapper | None | No tests for type mapping |
| Lather.Types.Generator | None | No tests for type generation |
| Lather.Server.* | None | No tests for server components |

---

## Detailed Test Gaps by Module

### 1. Lather.Auth.Basic Module
**Current Coverage:** 0%

**Missing Tests:**
- `header/2` - Basic auth header generation with various credential formats
  - Standard username and password
  - Special characters in credentials (: @ space)
  - Empty credentials edge cases
  - Non-ASCII characters
- `header_value/2` - Header value generation
  - Verification of Base64 encoding correctness
  - Various credential combinations
- `decode/1` - Decoding and parsing
  - Valid encoded credentials
  - Invalid format (missing "Basic " prefix)
  - Invalid Base64 encoding
  - Missing colon separator
  - Multiple colons in credentials (username:pass:extra)
- `validate/2` - Validation with custom validator
  - Successful validation
  - Failed validation
  - Validator function exceptions
  - Malformed input handling

**Recommended Tests:**
```
defmodule Lather.Auth.BasicTest do
  use ExUnit.Case
  
  describe "header/2" do
    test "generates valid basic auth header"
    test "handles special characters in credentials"
    test "encodes credentials in Base64"
  end
  
  describe "decode/1" do
    test "decodes valid basic auth header"
    test "handles invalid format"
    test "handles invalid base64"
  end
  
  describe "validate/2" do
    test "validates against validator function"
    test "handles validation failure"
  end
end
```

### 2. Lather.Auth.WSSecurity Module
**Current Coverage:** 0%

**Missing Tests:**
- `username_token/3` - Username token generation
  - Text password type
  - Digest password type with nonce
  - Timestamp creation
  - Nonce generation and encoding
  - Namespace attributes
  - Various option combinations
- `timestamp/1` - Timestamp generation
  - Default TTL (300 seconds)
  - Custom TTL
  - Created and Expires fields format
  - Namespace attributes
- `username_token_with_timestamp/3` - Combined token creation
  - Both username token and timestamp present
  - ID generation uniqueness
  - Correct namespace usage
- Password digest generation
  - SHA1 hash correctness
  - Nonce + Created + Password concatenation
  - Base64 encoding of result

**Recommended Tests:**
```
defmodule Lather.Auth.WSSecurityTest do
  use ExUnit.Case
  
  describe "username_token/3" do
    test "generates text password token"
    test "generates digest password token"
    test "includes nonce in digest mode"
    test "creates proper XML structure"
  end
  
  describe "timestamp/1" do
    test "generates valid timestamp"
    test "uses custom TTL"
  end
  
  describe "password digest generation" do
    test "produces correct SHA1 digest"
    test "base64 encodes digest"
  end
end
```

### 3. Lather.Error Module
**Current Coverage:** 0%

**Missing Tests:**
- `parse_soap_fault/2` - SOAP fault parsing
  - SOAP 1.1 fault structure
  - SOAP 1.2 fault structure
  - Missing fault elements
  - Nested detail structures
  - Empty fault elements
  - Malformed XML
- `format_error/2` - Error formatting
  - SOAP faults in different formats (:string, :map, :json)
  - Transport errors with/without details
  - HTTP errors with status codes
  - WSDL errors
  - Validation errors
  - Include/exclude details option
- `recoverable?/1` - Recoverability check
  - Timeout errors (recoverable)
  - Connection refused (recoverable)
  - Client faults (not recoverable)
  - Server faults (recoverable)
  - 500/503 HTTP status (recoverable)
  - 400/401 HTTP status (not recoverable)
- `extract_debug_context/1` - Debug context extraction
  - Timestamp inclusion
  - Error type detection
  - Details extraction
  - Fault code/string for SOAP faults

**Recommended Tests:**
```
defmodule Lather.ErrorTest do
  use ExUnit.Case
  
  describe "parse_soap_fault/2" do
    test "parses SOAP 1.1 faults"
    test "parses SOAP 1.2 faults"
    test "handles missing fault elements"
    test "extracts detail information"
  end
  
  describe "format_error/2" do
    test "formats as string"
    test "formats as map"
    test "includes/excludes details"
  end
  
  describe "recoverable?/1" do
    test "identifies recoverable errors"
    test "identifies non-recoverable errors"
  end
  
  describe "extract_debug_context/1" do
    test "includes timestamp"
    test "includes error type"
    test "extracts details"
  end
end
```

### 4. Lather.Xml.Builder Module
**Current Coverage:** 0%

**Missing Tests:**
- `build/1` - XML building with declaration
  - Simple maps
  - Nested structures
  - Attributes (@ prefixed keys)
  - Text content (#text key)
  - Empty elements
  - List content
  - Invalid input types
  - XML declaration presence
- `build_fragment/1` - Fragment building without declaration
  - Various data structures
  - Proper fragment format
  - No XML declaration
- Attribute handling
  - Multiple attributes
  - Special characters in attributes
  - Namespace prefixes
- Text escaping
  - XML special characters (&, <, >, ")
  - Attribute value escaping
  - Mixed content with nested elements
- Edge cases
  - Deeply nested structures
  - Very large documents
  - Empty maps/lists
  - Null values

**Recommended Tests:**
```
defmodule Lather.Xml.BuilderTest do
  use ExUnit.Case
  
  describe "build/1" do
    test "builds simple XML"
    test "includes XML declaration"
    test "builds nested structures"
    test "handles attributes"
    test "handles text content"
  end
  
  describe "escape_text/1" do
    test "escapes special characters"
    test "handles all XML entities"
  end
  
  describe "attribute handling" do
    test "escapes attribute values"
    test "handles multiple attributes"
  end
end
```

### 5. Lather.Xml.Parser Module
**Current Coverage:** 0%

**Missing Tests:**
- `parse/1` - XML parsing
  - Valid SOAP envelopes
  - Various XML structures
  - Namespaced elements
  - Attributes and text content
  - CDATA sections (if supported)
  - XML with declaration
  - Comments handling
  - Malformed XML
  - Invalid UTF-8
  - Empty input
- Namespace handling
  - Default namespaces
  - Prefixed namespaces
  - Multiple namespace declarations
  - Namespace resolution in nested elements
- Edge cases
  - Very large documents
  - Deeply nested structures
  - Special characters in content
  - Mixed content (text + elements)

**Recommended Tests:**
```
defmodule Lather.Xml.ParserTest do
  use ExUnit.Case
  
  describe "parse/1" do
    test "parses valid XML"
    test "parses SOAP envelopes"
    test "handles namespaces"
    test "handles attributes"
    test "rejects malformed XML"
  end
  
  describe "namespace handling" do
    test "resolves prefixed namespaces"
    test "handles default namespaces"
  end
end
```

### 6. Lather.Soap.Envelope Module
**Current Coverage:** Partial (build tested, parse_response not tested)

**Missing Tests:**
- `parse_response/1` - Response parsing (NOT TESTED)
  - Successful 200-299 responses with valid SOAP body
  - SOAP faults in 200 responses
  - SOAP faults in error status responses
  - Parsing errors (invalid XML)
  - HTTP errors (non-2xx status)
  - Envelope with vs without namespaces
  - Multiple response elements
  - Response without SOAP wrapper (edge case)
- Fault extraction scenarios
  - SOAP 1.1 fault format
  - SOAP 1.2 fault format
  - Fault with actor element
  - Fault with detailed description
  - Fault without all standard fields
- SOAP 1.2 envelope building (currently v1_1 default)
  - Version-specific namespace
  - Version-specific fault structure
  - Mixed version scenarios

**Recommended Tests:**
```
defmodule Lather.Soap.EnvelopeTest do
  use ExUnit.Case
  
  describe "parse_response/1" do
    test "parses successful response"
    test "handles SOAP faults"
    test "handles HTTP errors"
    test "handles parse errors"
  end
  
  describe "build/3 with SOAP 1.2" do
    test "builds SOAP 1.2 envelope"
    test "uses correct namespace"
  end
end
```

### 7. Lather.Client Module
**Current Coverage:** Partial (new/2 and envelope building tested, call/4 not tested)

**Missing Tests:**
- `call/4` - SOAP operation calls (NOT TESTED)
  - Successful calls
  - Network errors
  - SOAP faults in response
  - HTTP errors
  - Timeout handling
  - Request building with various parameter types
  - Response parsing validation
  - Header application
  - Option merging and propagation

**Recommended Tests:**
```
defmodule Lather.ClientCallTest do
  use ExUnit.Case
  
  describe "call/4" do
    test "makes successful SOAP call"
    test "handles network errors"
    test "handles SOAP faults"
    test "applies timeout options"
    test "merges default and call-specific options"
  end
end
```

### 8. Lather.DynamicClient Module
**Current Coverage:** 0% (only integration tests exist)

**Missing Unit Tests:**
- `new/2` - Client creation from WSDL
  - WSDL loading and parsing
  - Service info extraction
  - Endpoint determination
  - Authentication application (basic, wssecurity)
  - Invalid WSDL handling
- `list_operations/1` - Operation listing
  - Correct operation extraction
  - Metadata formatting
- `get_operation_info/2` - Operation information
  - Found operations
  - Non-existent operations
  - Required vs optional parameters
- `call/4` - Operation calls
  - Successful calls
  - Parameter validation
  - Request building
  - Response parsing
  - Error handling
- `validate_parameters/3` - Parameter validation
  - Required parameters present/missing
  - Type validation
  - Optional parameters
- `generate_service_report/1` - Report generation
  - Report formatting
  - Complete information inclusion

**Recommended Tests:**
```
defmodule Lather.DynamicClientTest do
  use ExUnit.Case
  
  setup do
    # Create mock/test WSDL data
    %{test_wsdl: "..."}
  end
  
  describe "new/2" do
    test "creates client from WSDL"
    test "applies authentication"
    test "handles invalid WSDL"
  end
  
  describe "call/4" do
    test "makes operation call"
    test "validates parameters"
    test "handles errors"
  end
end
```

### 9. Lather.Http.Transport Module
**Current Coverage:** Good (9 tests exist)

**Missing Tests:**
- `post/3` - POST requests (tested implicitly in integration tests but no unit tests)
  - Successful requests
  - Network timeouts
  - Connection refused
  - HTTP error status codes
  - Response header parsing
  - SSL/TLS options application
  - Basic auth integration
  - Connection pooling
  - Large request/response bodies
- Error handling edge cases
  - Finch.Error handling
  - Mint.TransportError handling
  - Timeout edge cases
  - Pool exhaustion

**Recommended Tests:**
```
defmodule Lather.Http.TransportPostTest do
  use ExUnit.Case
  
  describe "post/3" do
    test "sends successful POST"
    test "handles timeout"
    test "handles connection errors"
    test "applies SSL options"
    test "includes basic auth header"
  end
end
```

### 10. Lather.Wsdl.Analyzer Module
**Current Coverage:** 0%

**Missing Tests:**
- `analyze/2` - WSDL analysis
  - Valid WSDL parsing
  - Service extraction
  - Operation extraction
  - Type extraction
  - Endpoint extraction
  - Namespace handling
  - Invalid WSDL handling
  - Multiple services
  - Multiple ports/bindings
- `load_and_analyze/2` - WSDL loading and analysis
  - WSDL from URL
  - WSDL from file path
  - Network errors
  - Invalid URLs
  - Large WSDL files
- Service information extraction
  - Service names
  - Target namespaces
  - SOAP actions
  - Port types
  - Bindings
  - Message structures

**Recommended Tests:**
```
defmodule Lather.Wsdl.AnalyzerTest do
  use ExUnit.Case
  
  describe "analyze/2" do
    test "analyzes valid WSDL"
    test "extracts services"
    test "extracts operations"
    test "extracts types"
  end
  
  describe "load_and_analyze/2" do
    test "loads WSDL from URL"
    test "handles network errors"
  end
end
```

### 11. Lather.Operation.Builder Module
**Current Coverage:** 0%

**Missing Tests:**
- `build_request/3` - Request building
  - SOAP envelope generation
  - Parameter mapping
  - Type conversion
  - Namespace application
  - Style application (document, rpc)
  - Use application (literal, encoded)
- `parse_response/3` - Response parsing
  - Success case parsing
  - Fault handling
  - Type conversion of response
- `validate_parameters/2` - Parameter validation
  - Required parameters
  - Type checking
  - Optional parameters
- `get_operation_metadata/1` - Metadata extraction
  - Name extraction
  - Parameter information
  - Return type information
  - SOAP action

### 12. Lather.Types.Mapper and Generator Modules
**Current Coverage:** 0%

**Missing Tests:**
- Type mapping
  - XML Schema simple types to Elixir types
  - Complex types to maps/structs
  - Arrays/lists
  - Nested types
  - Optional types (minOccurs=0)
  - Restricted types (enumerations)
  - Union types
- Type generation
  - Module generation from schema
  - Struct definition
  - Validation functions
  - Serialization functions

### 13. Lather.Server Module and Server Components
**Current Coverage:** 0%

**Missing Tests:**
- Server DSL functionality
  - Operation definition
  - Type definition
  - Namespace configuration
  - Service name configuration
- Server request handling
  - WSDL generation
  - SOAP request parsing
  - Operation routing
  - Response building
- Server authentication
  - Basic auth validation
  - WS-Security validation
- Plug integration
  - Request routing
  - WSDL generation endpoint
  - SOAP call endpoint
  - Error responses
- WSDL generation
  - Service metadata inclusion
  - Operation metadata
  - Type definitions
  - Correct namespace usage

**Recommended Tests:**
```
defmodule Lather.ServerTest do
  use ExUnit.Case
  
  describe "SOAP service definition" do
    test "defines operations"
    test "validates parameters"
    test "formats responses"
  end
end

defmodule Lather.Server.PlugTest do
  use ExUnit.Case
  
  describe "Plug integration" do
    test "routes WSDL requests"
    test "routes SOAP requests"
    test "handles errors"
  end
end
```

---

## Test Organization Recommendations

### Create New Test Files

1. **lather/test/lather/auth/basic_test.exs** - Basic auth tests
2. **lather/test/lather/auth/ws_security_test.exs** - WS-Security tests
3. **lather/test/lather/error_test.exs** - Error handling tests
4. **lather/test/lather/xml/builder_test.exs** - XML builder tests
5. **lather/test/lather/xml/parser_test.exs** - XML parser tests
6. **lather/test/lather/soap/envelope_test.exs** - Envelope parsing tests
7. **lather/test/lather/dynamic_client_test.exs** - Dynamic client unit tests
8. **lather/test/lather/wsdl/analyzer_test.exs** - WSDL analyzer tests
9. **lather/test/lather/operation/builder_test.exs** - Operation builder tests
10. **lather/test/lather/http/transport_post_test.exs** - POST request tests
11. **lather/test/lather/types/mapper_test.exs** - Type mapper tests
12. **lather/test/lather/types/generator_test.exs** - Type generator tests
13. **lather/test/lather/server/dsl_test.exs** - Server DSL tests
14. **lather/test/lather/server/plug_test.exs** - Server Plug tests
15. **lather/test/lather/server/wsdl_generator_test.exs** - WSDL generation tests

### Test Infrastructure Needs

1. **Test fixtures** - Sample WSDL, SOAP envelopes, error responses
2. **Mock HTTP server** - For testing without external dependencies
3. **Test helpers** - Common assertions and utility functions
4. **Test data generators** - Property-based testing for edge cases

---

## Priority Ranking

### High Priority (Core Functionality)
1. Lather.Xml.Builder - Essential for all SOAP operations
2. Lather.Xml.Parser - Essential for all SOAP operations
3. Lather.Soap.Envelope.parse_response - Critical for response handling
4. Lather.Auth.Basic - Common authentication method
5. Lather.Http.Transport.post - Core HTTP functionality
6. Lather.Error - Error handling is used everywhere

### Medium Priority (Important Features)
7. Lather.Auth.WSSecurity - Advanced authentication
8. Lather.DynamicClient - Dynamic operation calling
9. Lather.Wsdl.Analyzer - WSDL parsing and analysis
10. Lather.Operation.Builder - Operation building

### Lower Priority (Specialized)
11. Lather.Server - Server-side features
12. Lather.Types.Mapper - Type system
13. Lather.Types.Generator - Type generation

---

## Test Coverage Metrics

| Category | Current | Target | Gap |
|----------|---------|--------|-----|
| Total Modules | 24 | 24 | 0 |
| Covered Modules | 4 | 24 | 20 |
| Test Files | 4 | ~19 | 15 |
| Unit Test Count | ~20 | ~150+ | 130+ |
| Integration Tests | 5 | 5 | 0 |

---

## Recommended Testing Approach

### 1. Mock vs. Integration Testing
- **Unit tests**: Use mocks for HTTP calls, file I/O
- **Integration tests**: Use real external services (already in place)
- **Hybrid approach**: Test layer boundaries with both real and mocked components

### 2. Edge Cases to Cover
- Empty/null inputs
- Very large inputs
- Special characters and encoding issues
- Concurrent requests
- Timeout conditions
- Partial/malformed responses

### 3. Error Scenarios to Test
- Network connectivity issues
- Timeouts at various stages
- Invalid XML/WSDL
- SOAP faults with different structures
- Authentication failures
- Authorization failures
- Rate limiting/throttling

### 4. Performance Considerations
- Large SOAP messages
- Complex nested types
- Bulk operation handling
- Memory leak tests
- Connection pool exhaustion

---

## Quick Start for Adding Tests

### Template for New Test File
```elixir
defmodule Lather.SampleModuleTest do
  use ExUnit.Case
  doctest Lather.SampleModule

  alias Lather.SampleModule

  setup do
    # Setup test data
    :ok
  end

  describe "function_name/arity" do
    test "specific behavior" do
      # Arrange
      
      # Act
      
      # Assert
    end
  end
end
```

### Running Tests
```bash
# Run all tests
mix test

# Run specific test file
mix test test/lather/sample_test.exs

# Run with coverage
mix test --cover

# Run integration tests only
mix test --only integration

# Run excluding integration tests
mix test --exclude integration
```

---

## Conclusion

The Lather library has solid integration test coverage but significant gaps in unit test coverage. Priority should be given to testing core XML processing and authentication modules, followed by higher-level features like dynamic client and WSDL analysis. Following this test gap analysis should improve reliability, catch regressions earlier, and provide better documentation of expected behavior.

**Total Estimated Additional Tests Needed: 150+**
**Estimated Implementation Time: 40-60 hours**