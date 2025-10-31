# MTOM/Binary Attachments Implementation Plan

**Project**: Lather SOAP Library - MTOM/XOP Binary Attachments Support  
**Target Version**: v1.1.0  
**Estimated Total Effort**: 4-5 days (32-40 hours)  
**Status**: Ready to begin  
**Created**: January 2025

---

## Overview

This document outlines the implementation plan to add MTOM (Message Transmission Optimization Mechanism) and XOP (XML-binary Optimized Packaging) support to the Lather SOAP library, enabling efficient binary data transmission in SOAP messages.

### What is MTOM/XOP?

**MTOM** is a W3C specification that optimizes the transmission of binary data in SOAP messages by:
- **Avoiding Base64 encoding** (which adds 33% overhead)
- **Using multipart/related MIME** packaging 
- **Referencing binary parts** via XOP includes in the SOAP envelope
- **Maintaining XML schema compatibility**

### Current Problem

```elixir
# Current approach (inefficient)
large_pdf = File.read!("document.pdf")  # 1MB binary
encoded = Base.encode64(large_pdf)      # 1.33MB string + processing overhead

soap_params = %{
  "document" => encoded  # Embedded in SOAP XML
}
```

### MTOM Solution

```elixir
# MTOM approach (efficient)
large_pdf = File.read!("document.pdf")  # 1MB binary

soap_params = %{
  "document" => {:attachment, large_pdf, "application/pdf"}  # Referenced, not embedded
}
```

---

## Technical Specifications

### Standards Compliance
- **W3C MTOM 1.0** (Message Transmission Optimization Mechanism)
- **W3C XOP 1.0** (XML-binary Optimized Packaging)  
- **RFC 2387** (multipart/related MIME type)
- **SOAP 1.1 and 1.2** compatibility

### MIME Structure
```
Content-Type: multipart/related; boundary="uuid:123"; type="application/xop+xml"

--uuid:123
Content-Type: application/xop+xml; charset=UTF-8; type="text/xml"
Content-Transfer-Encoding: binary

<?xml version="1.0"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <UploadDocument>
      <filename>report.pdf</filename>
      <content>
        <xop:Include href="cid:content123" xmlns:xop="http://www.w3.org/2004/08/xop/include"/>
      </content>
    </UploadDocument>
  </soap:Body>
</soap:Envelope>

--uuid:123
Content-Type: application/pdf
Content-Transfer-Encoding: binary
Content-ID: <content123>

%PDF-1.4 [binary data]...
--uuid:123--
```

---

## Implementation Phases

### Phase 1: Core MTOM Infrastructure (Day 1-2)
**Effort**: 12-16 hours  
**Priority**: High  
**Dependencies**: None

#### Objectives
- Create MTOM message building infrastructure
- Handle multipart/related MIME packaging
- Implement XOP Include references
- Basic attachment handling

#### Tasks

##### 1.1 Create MTOM Module Structure
**Files to Create:**
- `lib/lather/mtom/builder.ex` - MTOM message construction
- `lib/lather/mtom/parser.ex` - MTOM message parsing  
- `lib/lather/mtom/attachment.ex` - Attachment handling
- `lib/lather/mtom/mime.ex` - MIME utilities

##### 1.2 Attachment Data Structure
```elixir
defmodule Lather.Mtom.Attachment do
  @type t :: %__MODULE__{
    id: String.t(),
    content_type: String.t(),
    content_transfer_encoding: String.t(),
    data: binary(),
    content_id: String.t()
  }

  defstruct [
    :id,
    :content_type, 
    :content_transfer_encoding,
    :data,
    :content_id
  ]
end
```

##### 1.3 MTOM Message Builder
```elixir
defmodule Lather.Mtom.Builder do
  @doc """
  Builds an MTOM-encoded SOAP message with binary attachments.
  
  ## Parameters
  - operation: SOAP operation name
  - parameters: Parameters with potential {:attachment, data, type} tuples
  - options: SOAP envelope options
  
  ## Returns
  {:ok, {content_type_header, multipart_body}} | {:error, reason}
  """
  @spec build_mtom_message(atom(), map(), keyword()) :: 
    {:ok, {String.t(), binary()}} | {:error, term()}
end
```

##### 1.4 XOP Include Processing
```elixir
defmodule Lather.Mtom.XopProcessor do
  @doc "Replaces {:attachment, data, type} with XOP includes"
  def process_parameters(params) do
    # Transform attachment tuples to XOP Include elements
    # Generate Content-IDs
    # Return {processed_params, attachments_list}
  end
end
```

#### Deliverables
- [ ] Core MTOM module structure
- [ ] Attachment data structures 
- [ ] Basic MTOM message building
- [ ] XOP Include generation
- [ ] Unit tests for core functions

#### Acceptance Criteria
- [ ] Can build multipart/related MIME messages
- [ ] Generates valid XOP Include references
- [ ] Handles single and multiple attachments
- [ ] Maintains SOAP envelope validity
- [ ] All unit tests pass

---

### Phase 2: MTOM Integration (Day 2-3)
**Effort**: 8-12 hours  
**Priority**: High  
**Dependencies**: Phase 1 complete

#### Objectives
- Integrate MTOM with existing envelope building
- Update HTTP transport for multipart content
- Modify DynamicClient to support attachments
- Handle Content-Type negotiation

#### Tasks

##### 2.1 Update Envelope Builder
**File**: `lib/lather/soap/envelope.ex`

```elixir
# Add MTOM support to existing build function
def build(operation, params, options \\ []) do
  enable_mtom = Keyword.get(options, :enable_mtom, false)
  
  if enable_mtom and has_attachments?(params) do
    Lather.Mtom.Builder.build_mtom_message(operation, params, options)
  else
    # Existing SOAP envelope building
    build_standard_envelope(operation, params, options)
  end
end

defp has_attachments?(params) do
  # Check if any parameter values contain {:attachment, _, _} tuples
end
```

##### 2.2 HTTP Transport Updates
**File**: `lib/lather/http/transport.ex`

```elixir
# Update post function to handle MTOM content
def post(url, body, options \\ []) do
  case body do
    {content_type_header, multipart_body} ->
      # Handle MTOM multipart message
      headers = build_mtom_headers(options, content_type_header)
      send_multipart_request(url, multipart_body, headers, options)
      
    soap_envelope when is_binary(soap_envelope) ->
      # Existing SOAP message handling
      send_soap_request(url, soap_envelope, options)
  end
end

defp build_mtom_headers(options, content_type) do
  # Build headers for MTOM request (no SOAPAction in Content-Type for MTOM)
end
```

##### 2.3 DynamicClient Integration
**File**: `lib/lather/dynamic_client.ex`

```elixir
# Update build_request to detect and enable MTOM
defp build_request(operation_info, parameters, service_info, options) do
  # Detect if parameters contain attachments
  enable_mtom = has_binary_attachments?(parameters) || 
                Keyword.get(options, :enable_mtom, false)
  
  request_options = [
    namespace: service_info.target_namespace,
    headers: headers,
    style: get_operation_style(operation_info),
    use: get_operation_use(operation_info),
    version: soap_version,
    enable_mtom: enable_mtom  # Add MTOM flag
  ]

  Builder.build_request(operation_info, parameters, request_options)
end
```

#### Deliverables
- [ ] MTOM-enabled envelope building
- [ ] HTTP transport multipart support
- [ ] DynamicClient attachment detection
- [ ] Content-Type header handling
- [ ] Integration tests

#### Acceptance Criteria
- [ ] DynamicClient automatically enables MTOM for attachments
- [ ] HTTP requests use correct multipart Content-Type
- [ ] SOAP envelope contains XOP includes instead of binary data
- [ ] Backward compatibility maintained for non-MTOM messages
- [ ] Integration tests pass

---

### Phase 3: MTOM Response Parsing (Day 3-4)
**Effort**: 8-12 hours  
**Priority**: High  
**Dependencies**: Phase 2 complete

#### Objectives
- Parse incoming MTOM responses  
- Extract binary attachments from multipart responses
- Reconstruct complete response data
- Handle various MTOM response formats

#### Tasks

##### 3.1 MTOM Response Parser
**File**: `lib/lather/mtom/parser.ex`

```elixir
defmodule Lather.Mtom.Parser do
  @doc """
  Parses an MTOM response and reconstructs the complete message.
  
  ## Parameters
  - response: HTTP response with multipart/related body
  
  ## Returns  
  {:ok, reconstructed_soap_response} | {:error, reason}
  """
  def parse_mtom_response(%{headers: headers, body: body}) do
    with {:ok, boundary} <- extract_boundary(headers),
         {:ok, parts} <- parse_multipart_body(body, boundary),
         {:ok, {soap_part, attachment_parts}} <- separate_parts(parts),
         {:ok, soap_doc} <- parse_soap_envelope(soap_part),
         {:ok, complete_doc} <- reconstruct_with_attachments(soap_doc, attachment_parts) do
      {:ok, complete_doc}
    end
  end

  defp extract_boundary(headers) do
    # Extract boundary from Content-Type header
  end

  defp parse_multipart_body(body, boundary) do
    # Split multipart body into individual parts
  end

  defp separate_parts(parts) do
    # Separate SOAP envelope part from attachment parts
  end

  defp reconstruct_with_attachments(soap_doc, attachments) do
    # Replace XOP includes with actual binary data or attachment references
  end
end
```

##### 3.2 Multipart MIME Parser
```elixir
defmodule Lather.Mtom.Mime.Parser do
  def parse_multipart(body, boundary) do
    # Split on boundary markers
    # Parse headers for each part  
    # Extract content based on Content-Transfer-Encoding
  end
  
  def parse_part_headers(header_section) do
    # Parse MIME headers like Content-Type, Content-ID, etc.
  end
  
  def decode_part_content(content, encoding) do
    case encoding do
      "binary" -> content
      "base64" -> Base.decode64!(content)
      "quoted-printable" -> decode_quoted_printable(content)
    end
  end
end
```

##### 3.3 Update Envelope Parser
**File**: `lib/lather/soap/envelope.ex`

```elixir
def parse_response(%{headers: headers} = response) do
  content_type = get_content_type(headers)
  
  cond do
    String.starts_with?(content_type, "multipart/related") ->
      # Handle MTOM response
      Lather.Mtom.Parser.parse_mtom_response(response)
      
    String.contains?(content_type, "xml") ->
      # Handle regular SOAP response  
      parse_soap_response(response)
      
    true ->
      {:error, {:unsupported_content_type, content_type}}
  end
end
```

#### Deliverables
- [ ] MTOM response parsing
- [ ] Multipart MIME parsing utilities
- [ ] XOP Include reconstruction  
- [ ] Integration with existing response parsing
- [ ] Comprehensive test coverage

#### Acceptance Criteria
- [ ] Can parse multipart/related MTOM responses
- [ ] Correctly extracts binary attachments
- [ ] Reconstructs complete response data
- [ ] Handles various Content-Transfer-Encoding types
- [ ] Maintains compatibility with regular SOAP responses

---

### Phase 4: Advanced Features & Polish (Day 4-5)
**Effort**: 8-12 hours  
**Priority**: Medium  
**Dependencies**: Phase 3 complete

#### Objectives
- Performance optimizations
- Advanced MTOM features
- Comprehensive documentation
- Production-ready error handling

#### Tasks

##### 4.1 Performance Optimizations
- **Streaming Support**: Handle large attachments without loading into memory
- **Compression**: Optional gzip compression for attachments
- **Memory Management**: Efficient binary data handling

```elixir
# Streaming attachment support
soap_params = %{
  "document" => {:attachment_stream, file_stream, "application/pdf", file_size}
}
```

##### 4.2 Advanced MTOM Features
- **Multiple Attachments**: Handle arrays of attachments
- **Nested Attachments**: Attachments within complex structures
- **Content-ID Management**: Automatic and manual Content-ID handling

```elixir
# Multiple attachments
soap_params = %{
  "documents" => [
    {:attachment, pdf_data, "application/pdf"},
    {:attachment, excel_data, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}
  ]
}

# Nested attachments
soap_params = %{
  "report" => %{
    "metadata" => %{"title" => "Q4 Report"},
    "attachments" => %{
      "summary" => {:attachment, summary_pdf, "application/pdf"},
      "details" => {:attachment, details_xlsx, "application/vnd.ms-excel"}
    }
  }
}
```

##### 4.3 Error Handling
- **Attachment Validation**: File type, size limits
- **MTOM Format Validation**: Proper multipart structure
- **Recovery Strategies**: Fallback to Base64 encoding

##### 4.4 Documentation
- **API Documentation**: Complete function documentation
- **Usage Examples**: Real-world scenarios
- **Performance Guide**: Best practices for large files
- **Troubleshooting**: Common issues and solutions

#### Deliverables
- [ ] Performance optimizations
- [ ] Advanced attachment features
- [ ] Comprehensive error handling
- [ ] Complete documentation
- [ ] Example applications

#### Acceptance Criteria
- [ ] Handles large files efficiently (>100MB)
- [ ] Supports all common attachment scenarios
- [ ] Provides clear error messages
- [ ] Documentation is complete and accurate
- [ ] Example code works correctly

---

## API Design

### Client Usage Examples

#### Basic File Attachment
```elixir
# Upload a single document
file_data = File.read!("report.pdf")

{:ok, response} = DynamicClient.call(client, "UploadDocument", %{
  "filename" => "quarterly-report.pdf",
  "document" => {:attachment, file_data, "application/pdf"}
})
```

#### Multiple Attachments
```elixir
# Upload multiple files
{:ok, response} = DynamicClient.call(client, "SubmitApplication", %{
  "applicant_id" => "12345",
  "documents" => [
    {:attachment, resume_pdf, "application/pdf"},
    {:attachment, cover_letter_doc, "application/msword"},
    {:attachment, portfolio_zip, "application/zip"}
  ]
})
```

#### Mixed Data with Attachments
```elixir
# Complex structure with embedded attachments
{:ok, response} = DynamicClient.call(client, "ProcessInsuranceClaim", %{
  "claim" => %{
    "claim_id" => "CLM-2025-001",
    "incident_date" => "2025-01-15",
    "description" => "Vehicle accident claim",
    "supporting_documents" => %{
      "police_report" => {:attachment, police_pdf, "application/pdf"},
      "photos" => [
        {:attachment, photo1_jpg, "image/jpeg"},
        {:attachment, photo2_jpg, "image/jpeg"}
      ],
      "estimates" => {:attachment, estimate_xlsx, "application/vnd.ms-excel"}
    }
  }
})
```

#### Large File Streaming
```elixir
# Handle large files efficiently
large_file_stream = File.stream!("large-video.mp4", [], 64_000)
file_size = File.stat!("large-video.mp4").size

{:ok, response} = DynamicClient.call(client, "UploadVideo", %{
  "video" => {:attachment_stream, large_file_stream, "video/mp4", file_size}
})
```

### Server Support (Future)
```elixir
defmodule MyApp.FileService do
  use Lather.Server
  
  @service_name "FileService"
  
  defoperation upload_document,
    input: [
      filename: :string,
      document: :attachment  # New attachment type
    ],
    output: [
      document_id: :string,
      size: :integer
    ] do
    
    # Access attachment data
    {:attachment, binary_data, content_type} = document
    
    # Process the file
    document_id = store_document(binary_data, filename, content_type)
    size = byte_size(binary_data)
    
    {:ok, %{document_id: document_id, size: size}}
  end
end
```

---

## Integration Strategy

### Backward Compatibility
- **Zero Breaking Changes**: Existing code continues to work
- **Automatic Detection**: MTOM enabled when attachments detected
- **Explicit Control**: `enable_mtom: true/false` option override

### Configuration
```elixir
# Global MTOM configuration
config :lather, :mtom,
  enabled: true,
  max_attachment_size: 100_000_000,  # 100MB
  supported_types: ["application/pdf", "image/jpeg", "image/png", "application/zip"],
  fallback_to_base64: true  # Fallback if MTOM fails

# Per-client configuration
{:ok, client} = DynamicClient.new(wsdl_url, [
  mtom_enabled: true,
  max_attachment_size: 50_000_000
])
```

### Error Handling
```elixir
# MTOM-specific errors
{:error, {:mtom_error, :attachment_too_large}} = 
  DynamicClient.call(client, "Upload", %{"file" => {:attachment, huge_file, "video/mp4"}})

{:error, {:mtom_error, :unsupported_content_type}} =
  DynamicClient.call(client, "Upload", %{"file" => {:attachment, data, "application/virus"}})

{:error, {:mtom_parse_error, :invalid_multipart_boundary}} = 
  # Server returned malformed MTOM response
```

---

## Testing Strategy

### Unit Tests
- **MTOM Builder**: Message construction, XOP includes
- **MTOM Parser**: Multipart parsing, attachment extraction  
- **MIME Utilities**: Boundary parsing, header processing
- **Attachment Handling**: Various content types and encodings

### Integration Tests
- **End-to-End MTOM**: Complete request/response cycle
- **Mixed Messages**: MTOM and regular SOAP in same session
- **Large Files**: Performance and memory usage
- **Error Scenarios**: Malformed MTOM, unsupported types

### Performance Tests
- **Memory Usage**: Large attachment handling
- **Throughput**: Multiple concurrent MTOM requests
- **Streaming**: Large file streaming performance

### Compatibility Tests
- **SOAP 1.1/1.2**: MTOM with both SOAP versions
- **Various Servers**: Different MTOM implementations
- **Content Types**: Wide range of binary formats

---

## Dependencies

### New Dependencies
```elixir
# mix.exs additions
defp deps do
  [
    # Existing dependencies...
    {:mime, "~> 2.0"},  # MIME type detection
    # Consider: {:multipart, "~> 0.3"} if needed for advanced parsing
  ]
end
```

### Optional Dependencies
- **{:multipart, "~> 0.3"}**: Advanced multipart parsing (if needed)
- **{:mime, "~> 2.0"}**: MIME type detection and validation

---

## Performance Considerations

### Memory Management
- **Streaming**: Process large attachments without loading into memory
- **Chunked Processing**: Handle multipart data in chunks
- **Lazy Loading**: Parse attachments only when accessed

### Network Efficiency
- **Compression**: Optional gzip compression for text attachments
- **Connection Reuse**: Efficient HTTP connection handling
- **Parallel Processing**: Multiple attachments in parallel

### Benchmarks Target
- **Small Attachments (<1MB)**: <10ms overhead vs regular SOAP
- **Large Attachments (>10MB)**: <2x memory usage vs file size
- **Multiple Attachments**: Linear performance scaling

---

## Risk Assessment & Mitigation

### Technical Risks

**Risk**: Complex multipart parsing  
**Probability**: Medium  
**Impact**: High  
**Mitigation**: Use established MIME parsing libraries, extensive testing

**Risk**: Memory usage with large files  
**Probability**: High  
**Impact**: Medium  
**Mitigation**: Implement streaming, chunked processing

**Risk**: Server compatibility issues  
**Probability**: Medium  
**Impact**: Medium  
**Mitigation**: Test with multiple SOAP server implementations

### Mitigation Strategies
- **Fallback Mechanism**: Automatic fallback to Base64 encoding
- **Incremental Rollout**: Feature flag for gradual deployment
- **Comprehensive Testing**: Wide range of scenarios and edge cases

---

## Timeline & Milestones

### Week 1
- **Days 1-2**: Phase 1 & 2 - Core MTOM infrastructure and integration
- **Days 3-4**: Phase 3 - Response parsing
- **Day 5**: Phase 4 - Advanced features and documentation

### Success Metrics
- [ ] Can send MTOM requests with attachments
- [ ] Can parse MTOM responses with attachments  
- [ ] Performance within 2x of Base64 for small files, significantly better for large files
- [ ] Zero breaking changes to existing API
- [ ] Comprehensive test coverage (>90%)

### Release Strategy
- **v1.1.0-alpha**: Core MTOM functionality
- **v1.1.0-beta**: Full feature set with documentation
- **v1.1.0**: Production release

---

## Future Enhancements

### v1.2+ Potential Features
- **SwA (SOAP with Attachments)**: Alternative to MTOM
- **Attachment Encryption**: Encrypted binary attachments
- **Cloud Storage Integration**: Direct upload to S3, Azure Blob, etc.
- **Attachment Validation**: Virus scanning, content validation
- **Streaming Server Support**: Server-side streaming attachments

---

## Getting Started

### Prerequisites
- Current Lather codebase (SOAP 1.2 support complete)
- Understanding of MIME multipart format
- Knowledge of XOP/MTOM specifications

### First Implementation Task
1. **Create base module structure** (`lib/lather/mtom/`)
2. **Implement simple attachment detection** in parameters
3. **Build basic XOP Include generation**
4. **Create first unit test** for attachment processing

**Ready to revolutionize SOAP file handling in Elixir!** 🚀📎

This implementation will make Lather the most capable SOAP library in the Elixir ecosystem, enabling efficient handling of documents, images, and any binary content in SOAP services.