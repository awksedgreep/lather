# Lather 🧼

[![Hex.pm](https://img.shields.io/hexpm/v/lather.svg)](https://hex.pm/packages/lather)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/lather)
[![License](https://img.shields.io/hexpm/l/lather.svg)](https://github.com/markcotner/lather/blob/main/LICENSE)

**A comprehensive SOAP library for Elixir** that provides both client and server capabilities. Lather can work with any SOAP service without requiring service-specific implementations, using dynamic WSDL analysis and runtime operation building.

## ✨ Key Features

- 🌐 **Universal SOAP Client**: Works with any SOAP service using WSDL analysis
- 🖥️ **Complete SOAP Server**: Build SOAP services with a clean DSL
- 🔄 **Dynamic Operations**: Automatically discovers and builds requests for any SOAP operation  
- 🛡️ **Enterprise Security**: WS-Security, Basic Auth, SSL/TLS support
- ⚡ **High Performance**: Built on Finch with connection pooling and async support
- 🔧 **Phoenix Integration**: Seamless integration with Phoenix applications
- 📝 **Type Safety**: Dynamic type mapping and validation with struct generation
- 🚨 **Robust Error Handling**: Structured error types with SOAP fault parsing

## 🚀 Quick Start

### Installation

Add `lather` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:lather, "~> 0.9.0"}
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
  
  @service_name "UserService"
  @target_namespace "http://myapp.com/user"
  
  defoperation get_user,
    input: [user_id: :string],
    output: [user: %{name: :string, email: :string}] do
    
    user = MyApp.Users.get!(user_id)
    {:ok, %{user: %{name: user.name, email: user.email}}}
  end
end

# Add to your Phoenix router
pipe_through :api
post "/soap/user", Lather.Server.Plug, service: MyApp.UserService
```

## 📚 Documentation & Examples

Lather includes comprehensive interactive documentation via Livebooks:

- **Client Tutorial** - Complete guide to using SOAP clients
- **Server Tutorial** - Building SOAP services step-by-step  
- **Type System Guide** - Working with complex types and validation
- **Debugging Guide** - Troubleshooting SOAP integration issues
- **Enterprise Patterns** - Authentication, error handling, monitoring

[View all tutorials →](examples/)

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

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`mix test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Finch](https://hex.pm/packages/finch) for HTTP transport
- XML parsing powered by [SweetXml](https://hex.pm/packages/sweet_xml)
- Inspired by the SOAP libraries of other ecosystems

## 📞 Support

- 📖 [Documentation](https://hexdocs.pm/lather)
- 🐛 [Issues](https://github.com/markcotner/lather/issues)
- 💬 [Discussions](https://github.com/markcotner/lather/discussions)

## 🗺️ Roadmap

### v1.0.0 (Next Release)
- [ ] SOAP 1.2 support  
- [ ] Performance optimizations and benchmarking
- [ ] Enhanced WS-Security features (XML Signature, Encryption)
- [ ] Additional server examples and templates

### Future Releases  
- [ ] MTOM/XOP binary attachments
- [ ] WS-Addressing and WS-ReliableMessaging
- [ ] OpenAPI 3.0 SOAP extension support
- [ ] GraphQL-style query interface for SOAP
- [ ] Service mesh integration patterns

---

**Lather** - Making SOAP integration in Elixir as smooth as possible! 🧼✨

