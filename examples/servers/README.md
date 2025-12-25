# SOAP Server Examples

This directory contains comprehensive examples of building SOAP servers with Lather.

## Examples

### Basic Examples
- **[simple_service.ex](simple_service.ex)** - A minimal SOAP service with basic operations demonstrating core server concepts
- **[user_service.ex](user_service.ex)** - Complete user management SOAP service with CRUD operations
- **[calculator_service.ex](calculator_service.ex)** - Mathematical operations service demonstrating different data types and validation

### Advanced Examples
- **[enhanced_plug_example.ex](enhanced_plug_example.ex)** - Enhanced Plug-based SOAP server with middleware, logging, and request handling

### Integration Examples
- **[phoenix_integration.ex](phoenix_integration.ex)** - Seamless integration with Phoenix web framework including controllers and routing

### Authentication Examples
- **[ws_security_service.ex](ws_security_service.ex)** - Service with WS-Security authentication including UsernameToken and timestamp validation

## Quick Start

### 1. Define a SOAP Service

```elixir
defmodule MyApp.UserService do
  use Lather.Server
  
  @namespace "http://myapp.com/users"
  @service_name "UserService"
  
  soap_operation "GetUser" do
    description "Retrieves a user by ID"
    
    input do
      parameter "userId", :string, required: true
    end
    
    output do
      parameter "user", "User"
    end
    
    soap_action "http://myapp.com/GetUser"
  end
  
  def get_user(%{"userId" => user_id}) do
    case fetch_user_from_db(user_id) do
      {:ok, user} -> {:ok, %{"user" => user}}
      {:error, :not_found} -> soap_fault("Client", "User not found")
    end
  end
  
  defp fetch_user_from_db(id) do
    {:ok, %{"id" => id, "name" => "John Doe", "email" => "john@example.com"}}
  end
end
```

### 2. Set Up HTTP Handler

#### With Phoenix

```elixir
# In your router
scope "/soap" do
  pipe_through :api
  post "/users", MyAppWeb.SOAPController, :handle_users
  get "/users", MyAppWeb.SOAPController, :handle_users  # For WSDL
end

# In your controller
defmodule MyAppWeb.SOAPController do
  use MyAppWeb, :controller
  
  def handle_users(conn, _params) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    
    case Lather.Server.Handler.handle_request(
      conn.method, 
      conn.request_path, 
      conn.req_headers, 
      body, 
      MyApp.UserService,
      base_url: "http://localhost:4000/soap"
    ) do
      {:ok, status, headers, response_body} ->
        conn
        |> put_status(status)
        |> put_headers(headers)
        |> text(response_body)
      {:error, status, headers, response_body} ->
        conn
        |> put_status(status)
        |> put_headers(headers)
        |> text(response_body)
    end
  end
  
  defp put_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, acc ->
      put_resp_header(acc, key, value)
    end)
  end
end
```

#### Standalone with Cowboy

```elixir
defmodule MyApp.SOAPServer do
  def start_link do
    dispatch = :cowboy_router.compile([
      {:_, [
        {"/soap/users", __MODULE__, [service: MyApp.UserService]}
      ]}
    ])
    
    {:ok, _} = :cowboy.start_clear(:soap_server, [{:port, 8080}], %{
      env: %{dispatch: dispatch}
    })
  end
  
  def init(req, opts) do
    service = Keyword.fetch!(opts, :service)
    method = :cowboy_req.method(req)
    path = :cowboy_req.path(req)
    headers = :cowboy_req.headers(req)
    {:ok, body, _req} = :cowboy_req.read_body(req)
    
    case Lather.Server.Handler.handle_request(method, path, headers, body, service) do
      {:ok, status, response_headers, response_body} ->
        req2 = :cowboy_req.reply(status, response_headers, response_body, req)
        {:ok, req2, opts}
      {:error, status, response_headers, response_body} ->
        req2 = :cowboy_req.reply(status, response_headers, response_body, req)
        {:ok, req2, opts}
    end
  end
end
```

### 3. Test Your Service

#### Get WSDL
```bash
curl http://localhost:4000/soap/users?wsdl
```

#### Call SOAP Operation
```bash
curl -X POST http://localhost:4000/soap/users \
  -H "Content-Type: text/xml; charset=utf-8" \
  -H "SOAPAction: http://myapp.com/GetUser" \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <GetUser xmlns="http://myapp.com/users">
      <userId>123</userId>
    </GetUser>
  </soap:Body>
</soap:Envelope>'
```

## Features Demonstrated

- ✅ **Automatic WSDL Generation** - Generate WSDL from service definitions
- ✅ **Operation Dispatch** - Route SOAP requests to appropriate functions  
- ✅ **Parameter Validation** - Validate required parameters and types
- ✅ **Error Handling** - Comprehensive SOAP fault handling
- ✅ **Authentication** - Basic Auth, WS-Security, and custom authentication
- ✅ **Phoenix Integration** - Seamless integration with Phoenix applications
- ✅ **Standalone Deployment** - Deploy as standalone HTTP services
- ✅ **Type Safety** - Define and validate complex types
- ✅ **Documentation** - Built-in operation documentation
- ✅ **Monitoring** - Telemetry integration for observability

## Testing Tools

### SoapUI
Import the generated WSDL into SoapUI for comprehensive testing.

### Postman
Use Postman's SOAP request feature to test operations.

### Custom Test Client
```elixir
defmodule MyApp.TestClient do
  def test_get_user do
    wsdl_url = "http://localhost:4000/soap/users?wsdl"
    {:ok, client} = Lather.DynamicClient.new(wsdl_url)
    
    Lather.DynamicClient.call(client, "GetUser", %{"userId" => "123"})
  end
end
```

## Production Considerations

- **SSL/TLS** - Always use HTTPS in production
- **Authentication** - Implement appropriate authentication mechanisms
- **Rate Limiting** - Add rate limiting to prevent abuse
- **Monitoring** - Set up comprehensive monitoring and alerting
- **Logging** - Log all SOAP operations for audit trails
- **Error Handling** - Provide meaningful error messages
- **Documentation** - Maintain up-to-date API documentation
- **Testing** - Implement comprehensive test suites
- **Performance** - Monitor and optimize response times
- **Security** - Regular security audits and updates