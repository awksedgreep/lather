# Test script to examine current WSDL generation in Lather
Mix.install([
  {:lather, path: "."}
])

# Define a simple test service
defmodule WSDLTestService do
  use Lather.Server

  @namespace "http://test.example.com/api"
  @service_name "TestService"

  # Define a simple complex type
  soap_type "User" do
    description "User information"

    element "id", :string, required: true, description: "Unique user ID"
    element "username", :string, required: true, description: "Username"
    element "email", :string, required: true, description: "Email address"
    element "isActive", :boolean, required: false, description: "Account status"
    element "createdAt", :dateTime, required: true, description: "Creation timestamp"
  end

  soap_type "UserList" do
    description "List of users"

    element "users", "User", max_occurs: "unbounded", description: "Array of users"
    element "totalCount", :int, required: true, description: "Total user count"
  end

  # Simple operation
  soap_operation "GetUser" do
    description "Retrieves a user by their ID"

    input do
      parameter "userId", :string, required: true, description: "User ID to retrieve"
    end

    output do
      parameter "user", "User", description: "User information"
    end

    soap_action "http://test.example.com/api/GetUser"
  end

  def get_user(%{"userId" => user_id}) do
    {:ok, %{"user" => %{
      "id" => user_id,
      "username" => "testuser",
      "email" => "test@example.com",
      "isActive" => true,
      "createdAt" => "2024-01-01T00:00:00Z"
    }}}
  end

  # More complex operation
  soap_operation "ListUsers" do
    description "Lists all users with pagination"

    input do
      parameter "page", :int, required: false, description: "Page number (default: 1)"
      parameter "pageSize", :int, required: false, description: "Items per page (default: 10)"
    end

    output do
      parameter "userList", "UserList", description: "Paginated user list"
    end

    soap_action "http://test.example.com/api/ListUsers"
  end

  def list_users(params) do
    {:ok, %{"userList" => %{
      "users" => [],
      "totalCount" => 0
    }}}
  end

  # Operation with complex input
  soap_operation "CreateUser" do
    description "Creates a new user account"

    input do
      parameter "user", "User", required: true, description: "User data to create"
    end

    output do
      parameter "userId", :string, description: "ID of created user"
      parameter "success", :boolean, description: "Whether creation succeeded"
    end

    soap_action "http://test.example.com/api/CreateUser"
  end

  def create_user(%{"user" => _user_data}) do
    {:ok, %{
      "userId" => "12345",
      "success" => true
    }}
  end
end

# Generate and display the current WSDL
service_info = WSDLTestService.__soap_service__()
base_url = "http://localhost:4000/soap/"

IO.puts("=" |> String.duplicate(80))
IO.puts("CURRENT LATHER WSDL GENERATION")
IO.puts("=" |> String.duplicate(80))
IO.puts("")

IO.puts("Service Info Structure:")
IO.inspect(service_info, pretty: true, limit: :infinity)
IO.puts("")

IO.puts("Generated WSDL:")
IO.puts("-" |> String.duplicate(80))

wsdl = Lather.Server.WSDLGenerator.generate(service_info, base_url)
IO.puts(wsdl)

IO.puts("-" |> String.duplicate(80))
IO.puts("")

# Analyze the structure
IO.puts("ANALYSIS:")
IO.puts("✓ Contains #{length(service_info.operations)} operations")
IO.puts("✓ Contains #{length(service_info.types)} complex types")
IO.puts("✓ Uses namespace: #{service_info.namespace}")
IO.puts("✓ Service name: #{service_info.name}")

IO.puts("")
IO.puts("CURRENT WSDL FORMAT:")
IO.puts("- Uses SOAP 1.1 bindings only")
IO.puts("- Document/literal style")
IO.puts("- Standard WSDL 1.1 structure")
IO.puts("- No SOAP 1.2 bindings present")
IO.puts("- No REST/JSON endpoints")

IO.puts("")
IO.puts("=" |> String.duplicate(80))
