# Simple test to examine current WSDL generation
defmodule TestWSDLService do
  use Lather.Server

  @namespace "http://test.example.com/api"
  @service_name "TestService"

  # Define a simple type
  soap_type "User" do
    element "id", :string, required: true
    element "name", :string, required: true
    element "email", :string, required: true
  end

  # Define operations
  soap_operation "GetUser" do
    description "Get a user by ID"

    input do
      parameter "userId", :string, required: true
    end

    output do
      parameter "user", "User"
    end

    soap_action "http://test.example.com/api/GetUser"
  end

  def get_user(%{"userId" => user_id}) do
    {:ok, %{"user" => %{
      "id" => user_id,
      "name" => "Test User",
      "email" => "test@example.com"
    }}}
  end

  soap_operation "CreateUser" do
    description "Create a new user"

    input do
      parameter "user", "User", required: true
    end

    output do
      parameter "userId", :string
      parameter "success", :boolean
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

# Generate and display WSDL
service_info = TestWSDLService.__soap_service__()
base_url = "http://localhost:4000/soap/"

IO.puts("=== CURRENT WSDL GENERATION ===")
IO.puts("")

wsdl = Lather.Server.WSDLGenerator.generate(service_info, base_url)
IO.puts(wsdl)

IO.puts("")
IO.puts("=== END WSDL ===")
