# Lather 🧼

[![Hex.pm](https://img.shields.io/hexpm/v/lather.svg)](https://hex.pm/packages/lather)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/lather)
[![License](https://img.shields.io/hexpm/l/lather.svg)](https://github.com/awksedgreep/lather/blob/main/LICENSE)

**A comprehensive SOAP library for Elixir** that provides both client and server capabilities with modern web interfaces. Lather can work with any SOAP service without requiring service-specific implementations, using dynamic WSDL analysis and runtime operation building.

## ✨ Key Features

- 🌐 **Universal SOAP Client**: Works with any SOAP service using WSDL analysis
- 🖥️ **Complete SOAP Server**: Build SOAP services with a clean DSL
- 🔄 **Dynamic Operations**: Automatically discovers and builds requests for any SOAP operation  
- 🛡️ **Enterprise Security**: WS-Security, Basic Auth, SSL/TLS support
- ⚡ **High Performance**: Built on Finch with connection pooling and async support
- 🔧 **Phoenix Integration**: Seamless integration with Phoenix applications
- 📝 **Type Safety**: Dynamic type mapping and validation with struct generation
- 🚨 **Robust Error Handling**: Structured error types with SOAP fault parsing

## 🌟 Enhanced Features (v1.0.0)

### Multi-Protocol SOAP & REST Support

Lather v1.0.0 features a **three-layer API architecture** that serves multiple protocol types from a single service:

```
┌─ SOAP 1.1 (Top - Maximum Compatibility)    │ Legacy systems, .NET Framework
├─ SOAP 1.2 (Middle - Enhanced Features)     │ Modern SOAP, better error handling  
└─ REST/JSON (Bottom - Modern Applications)  │ Web apps, mobile, JavaScript
```

### Interactive Web Interface

Professional HTML5 testing interface similar to .NET Web Services:

- 📝 **Interactive Forms**: Test operations directly in your browser
- 🌐 **Multi-Protocol Examples**: See SOAP 1.1, SOAP 1.2, and JSON formats
- 📱 **Responsive Design**: Works on desktop and mobile
- 🌙 **Dark Mode Support**: Automatically respects browser dark mode preference
- ⚡ **Real-time Validation**: Type-aware parameter validation

### Enhanced WSDL Generation

Generate comprehensive WSDL documents with multiple protocol bindings:

```elixir
# Standard WSDL (SOAP 1.1 only)  
wsdl = Lather.Server.WSDLGenerator.generate(service_info, base_url)

# Enhanced WSDL (multi-protocol)
enhanced_wsdl = Lather.Server.EnhancedWSDLGenerator.generate(service_info, base_url)

# Interactive web forms
forms = Lather.Server.FormGenerator.generate_service_overview(service_info, base_url)
```

### Flexible URL Structure

- `GET  /service` → Interactive service overview with testing forms
- `GET  /service?wsdl` → Standard WSDL download
- `GET  /service?wsdl&enhanced=true` → Multi-protocol WSDL  
- `GET  /service?op=OperationName` → Interactive operation testing form
- `POST /service` → SOAP 1.1 endpoint (maximum compatibility)
- `POST /service/v1.2` → SOAP 1.2 endpoint (enhanced features)
- `POST /service/api` → JSON/REST endpoint (modern applications)

## 🚀 Quick Start

### Installation

Add `lather` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:lather, "~> 1.0"},
    # Optional: for JSON/REST endpoints in enhanced features
    {:jason, "~> 1.4"}
  ]
end
```

### SOAP Client

Connect to any SOAP service and start making calls:

```elixir
# Create a dynamic client from any WSDL
{:ok, client} = Lather.DynamicClient.new("http://example.com/service?wsdl")

# Call any operation defined in the WSDL  
{:ok, response} = Lather.DynamicClient.call(client, "GetUser", %{
  "userId" => "12345"
})

# With authentication
{:ok, client} = Lather.DynamicClient.new(wsdl_url, [
  basic_auth: {"username", "password"},
  timeout: 30_000
])
```

### SOAP Server

Define SOAP services with a clean, macro-based DSL:

```elixir
defmodule MyApp.UserService do
  use Lather.Server

  @namespace "http://myapp.com/users"
  @service_name "UserService"

  soap_operation "GetUser" do
    description "Retrieve user information by ID"

    input do
      parameter "userId", :string, required: true
    end

    output do
      parameter "user", "tns:User"
    end

    soap_action "http://myapp.com/users/GetUser"
  end

  def get_user(%{"userId" => user_id}) do
    user = MyApp.Users.get!(user_id)
    {:ok, %{"user" => %{"name" => user.name, "email" => user.email}}}
  end
end

# Add to your Phoenix router
scope "/soap" do
  pipe_through :api
  post "/users", Lather.Server.Plug, service: MyApp.UserService
end
```

### Enhanced Multi-Protocol Server

```elixir
# Define a service that supports SOAP 1.1, SOAP 1.2, and JSON/REST
defmodule MyApp.UserService do
  use Lather.Server

  @namespace "http://myapp.com/users"
  @service_name "UserManagementService"

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

  def get_user(%{"userId" => user_id} = params) do
    include_profile = Map.get(params, "includeProfile", false)
    # Your business logic here
    {:ok, %{"user" => %{"id" => user_id, "name" => "John Doe"}}}
  end
end

# Phoenix router with enhanced features
scope "/api/users" do
  pipe_through :api
  
  # Multi-protocol endpoints
  match :*, "/", Lather.Server.EnhancedPlug, service: MyApp.UserService
  match :*, "/*path", Lather.Server.EnhancedPlug, service: MyApp.UserService
end

# Generate enhanced WSDL with multiple protocols
service_info = MyApp.UserService.__service_info__()
enhanced_wsdl = Lather.Server.EnhancedWSDLGenerator.generate(service_info, "https://myapp.com/api/users")

# Generate interactive web forms
overview_page = Lather.Server.FormGenerator.generate_service_overview(service_info, "https://myapp.com/api/users")
```

### Access Multiple Protocol Endpoints

Your service automatically exposes multiple endpoints:

```bash
# Interactive web interface
curl -X GET "https://myapp.com/api/users"

# Standard WSDL (SOAP 1.1)
curl -X GET "https://myapp.com/api/users?wsdl"

# Enhanced WSDL (multi-protocol)
curl -X GET "https://myapp.com/api/users?wsdl&enhanced=true"

# Interactive operation form
curl -X GET "https://myapp.com/api/users?op=GetUser"

# SOAP 1.1 request
curl -X POST "https://myapp.com/api/users" \
  -H "Content-Type: text/xml; charset=utf-8" \
  -H "SOAPAction: http://myapp.com/users/GetUser" \
  -d '<soap:Envelope>...</soap:Envelope>'

# SOAP 1.2 request
curl -X POST "https://myapp.com/api/users/v1.2" \
  -H "Content-Type: application/soap+xml; charset=utf-8; action=\"http://myapp.com/users/GetUser\"" \
  -d '<soap:Envelope>...</soap:Envelope>'

# JSON/REST request
curl -X POST "https://myapp.com/api/users/api" \
  -H "Content-Type: application/json" \
  -d '{"operation": "GetUser", "parameters": {"userId": "123"}}'
```

## 📚 Interactive Learning with Livebooks

Lather includes comprehensive interactive documentation via **Livebooks** that you can run directly in your development environment. These tutorials provide hands-on experience with real SOAP services and practical examples.

### Available Livebooks

#### 🌱 **Getting Started** (`livebooks/getting_started.livemd`)
Perfect introduction to Lather with step-by-step examples:
- Creating your first SOAP client
- Making basic SOAP calls
- Handling responses and errors
- Authentication basics

#### 🌤️ **Weather Service Example** (`livebooks/weather_service_example.livemd`)
Real-world example using the National Weather Service API:
- Working with document/encoded SOAP services
- Complex parameter handling
- Response parsing and data extraction
- Error handling with external services

#### 🌍 **Country Info Service Example** (`livebooks/country_info_service_example.livemd`)
Demonstrates document/literal SOAP style:
- Different SOAP encoding styles
- Namespace handling
- Complex data structures
- Service discovery

#### 🔄 **SOAP 1.2 Client** (`livebooks/soap12_client.livemd`)
Working with SOAP 1.2 protocol:
- SOAP 1.2 vs 1.1 differences
- Content-Type and namespace changes
- SOAP 1.2 fault handling
- Version detection and selection

#### 🖥️ **SOAP Server Development** (`livebooks/soap_server_development.livemd`)
Complete server development tutorial:
- Building SOAP services with Lather.Server
- Multi-protocol endpoint configuration
- Interactive web interfaces
- Testing your services

#### 🔧 **Advanced Types** (`livebooks/advanced_types.livemd`)
Master complex data structures:
- Working with complex types
- Arrays and nested objects
- Type validation and conversion
- Custom type mappings

#### 📎 **MTOM Attachments** (`livebooks/mtom_attachments.livemd`)
Binary data transmission with MTOM/XOP:
- Creating and sending attachments
- MIME multipart handling
- XOP package structure
- Performance considerations

#### 🏢 **Enterprise Integration** (`livebooks/enterprise_integration.livemd`)
Production-ready patterns and practices:
- WS-Security implementation
- SSL/TLS configuration
- Performance optimization
- Monitoring and logging

#### 📊 **Production Monitoring** (`livebooks/production_monitoring.livemd`)
Observability and monitoring in production:
- Telemetry integration
- Key metrics and health checks
- Alerting patterns
- Interactive dashboards

#### 🧪 **Testing Strategies** (`livebooks/testing_strategies.livemd`)
Comprehensive testing approaches:
- Unit testing SOAP clients
- Mocking with Bypass
- Integration and contract testing
- Performance testing

#### 🐛 **Debugging & Troubleshooting** (`livebooks/debugging_troubleshooting.livemd`)
Essential debugging techniques:
- SOAP message inspection
- Common error patterns
- Network troubleshooting
- Performance analysis

### Running Livebooks

To use the interactive tutorials:

```bash
# Install Livebook if you haven't already
mix escript.install hex livebook

# Navigate to your project directory
cd your_project

# Start Livebook
livebook server

# Open any of the tutorial files from the livebooks/ directory
```

Or run individual livebooks directly:

```bash
# Run a specific livebook
livebook server livebooks/getting_started.livemd
```

The livebooks are self-contained and include all necessary dependencies. They're perfect for:
- **Learning**: Step-by-step tutorials with explanations
- **Testing**: Try different SOAP services interactively  
- **Development**: Use as templates for your own implementations
- **Troubleshooting**: Debug issues with real examples

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Application   │    │   Lather.Server  │    │  Phoenix/Plug   │
│                 │    │                  │    │                 │
│ DynamicClient   │◄──►│ Service DSL      │◄──►│ HTTP Integration│
│ WSDL Analysis   │    │ WSDL Generation  │    │ Request Routing │
│ Type Mapping    │    │ Operation Dispatch│    │ Middleware     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Core Infrastructure                          │
│                                                                 │
│  HTTP Transport  │  XML Processing  │  Error Handling  │  Auth  │
│  (Finch)        │  (SweetXML)     │  (Structured)    │  (WS-*) │
└─────────────────────────────────────────────────────────────────┘
```

## 🔧 Advanced Usage

### Enterprise Authentication

```elixir
# WS-Security with UsernameToken
username_token = Lather.Auth.WSSecurity.username_token("user", "pass", :digest)
security_header = Lather.Auth.WSSecurity.security_header(username_token)

{:ok, client} = Lather.DynamicClient.new(wsdl_url,
  soap_headers: [security_header],
  ssl_options: [verify: :verify_peer]
)
```

### Complex Data Structures

```elixir
{:ok, response} = Lather.DynamicClient.call(client, "CreateOrder", %{
  "order" => %{
    "customer" => %{
      "name" => "John Doe",
      "email" => "john@example.com"
    },
    "items" => [
      %{"sku" => "ITEM001", "quantity" => 2},
      %{"sku" => "ITEM002", "quantity" => 1}
    ],
    "shipping" => %{
      "method" => "express",
      "address" => %{
        "street" => "123 Main St",
        "city" => "Portland",
        "state" => "OR",
        "zip" => "97201"
      }
    }
  }
})
```

### Error Handling

```elixir
case Lather.DynamicClient.call(client, "Operation", params) do
  {:ok, response} ->
    handle_success(response)
    
  {:error, %{type: :soap_fault} = fault} ->
    Logger.error("SOAP Fault: #{fault.fault_string}")
    handle_soap_fault(fault)
    
  {:error, %{type: :http_error} = error} ->
    Logger.error("HTTP Error #{error.status}")
    handle_http_error(error)
    
  {:error, %{type: :transport_error} = error} ->
    if Lather.Error.recoverable?(error) do
      schedule_retry()
    else
      handle_fatal_error(error)
    end
end
```

## 🧪 Testing

```bash
# Run all tests (excludes external API tests by default)
mix test

# Run with external API tests (hits real SOAP services - use sparingly!)
mix test --include external_api

# Run with coverage
mix test --cover

# Run specific test files
mix test test/lather/xml/parser_test.exs
```

### External API Tests

By default, tests that call external SOAP services are excluded to avoid:
- Overloading public APIs
- Network-dependent test failures  
- Slow test runs

External API tests validate the library against real-world services like:
- National Weather Service (document/encoded style)
- Country Info Service (document/literal style)

**Use external API tests responsibly:**
- Only when making significant SOAP-related changes
- Before releases
- When investigating service-specific issues

```bash
# Enable external API tests (be considerate!)
mix test --include external_api
```

## 🔧 Configuration

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

## 🤝 Contributing

We welcome contributions!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`mix test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file in the repository for details.

## 🙏 Acknowledgments

- Built with [Finch](https://hex.pm/packages/finch) for HTTP transport
- XML parsing powered by [SweetXml](https://hex.pm/packages/sweet_xml)
- Inspired by the SOAP libraries of other ecosystems

## 📞 Support

- 📖 [Documentation](https://hexdocs.pm/lather)
- 🐛 [Issues](https://github.com/awksedgreep/lather/issues)
- 💬 [Discussions](https://github.com/awksedgreep/lather/discussions)

## 🗺️ Roadmap

### v1.1.0 (Next Release)
- [ ] MTOM/XOP binary attachments
- [ ] Enhanced WS-Security features (XML Signature, Encryption)
- [ ] Performance optimizations and benchmarking
- [ ] Additional server examples and templates

### v1.2.0 
- [ ] WS-Addressing and WS-ReliableMessaging
- [ ] OpenAPI 3.0 SOAP extension support
- [ ] GraphQL-style query interface for SOAP
- [ ] Advanced caching strategies

### Future Releases  
- [ ] Service mesh integration patterns
- [ ] gRPC interoperability layer
- [ ] Kubernetes-native deployment tools
- [ ] Advanced monitoring and observability

---

**Lather v1.0.4** - Making SOAP integration in Elixir as smooth as possible! 🧼✨

*Released December 2025 with complete SOAP 1.2 support and multi-protocol capabilities.*