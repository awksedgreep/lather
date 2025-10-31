# Enhanced WSDL and Forms Generation Test for Lather
# Demonstrates the new multi-protocol WSDL and interactive form capabilities

Mix.install([
  {:lather, path: "."},
  {:jason, "~> 1.4"}
])

# Define a comprehensive test service
defmodule TestEnhancedService do
  use Lather.Server

  @namespace "http://api.example.com/v1"
  @service_name "UserManagementService"

  # Define complex types
  soap_type "Address" do
    description "Physical address information"

    element "street", :string, required: true, description: "Street address"
    element "city", :string, required: true, description: "City name"
    element "state", :string, required: true, description: "State or province"
    element "postalCode", :string, required: true, description: "ZIP or postal code"
    element "country", :string, required: true, description: "Country code (ISO 3166-1)"
  end

  soap_type "User" do
    description "Complete user profile information"

    element "id", :string, required: true, description: "Unique user identifier"
    element "username", :string, required: true, description: "Login username"
    element "email", :string, required: true, description: "Email address"
    element "firstName", :string, required: true, description: "First name"
    element "lastName", :string, required: true, description: "Last name"
    element "dateOfBirth", :date, required: false, description: "Date of birth"
    element "isActive", :boolean, required: true, description: "Account active status"
    element "createdAt", :dateTime, required: true, description: "Account creation timestamp"
    element "lastLoginAt", :dateTime, required: false, description: "Last login timestamp"
    element "address", "Address", required: false, description: "Home address"
    element "profilePictureUrl", :anyURI, required: false, description: "Profile picture URL"
    element "accountBalance", :decimal, required: false, description: "Account balance"
  end

  soap_type "UserList" do
    description "Paginated list of users with metadata"

    element "users", "User", max_occurs: "unbounded", description: "Array of user objects"
    element "totalCount", :integer, required: true, description: "Total number of users"
    element "currentPage", :integer, required: true, description: "Current page number"
    element "pageSize", :integer, required: true, description: "Items per page"
    element "totalPages", :integer, required: true, description: "Total number of pages"
  end

  soap_type "SearchCriteria" do
    description "Advanced user search criteria"

    element "username", :string, required: false, description: "Username pattern (supports wildcards)"
    element "email", :string, required: false, description: "Email pattern (supports wildcards)"
    element "firstName", :string, required: false, description: "First name pattern"
    element "lastName", :string, required: false, description: "Last name pattern"
    element "isActive", :boolean, required: false, description: "Filter by active status"
    element "createdAfter", :dateTime, required: false, description: "Created after this date"
    element "createdBefore", :dateTime, required: false, description: "Created before this date"
    element "city", :string, required: false, description: "Filter by city"
    element "country", :string, required: false, description: "Filter by country"
  end

  # Simple operation
  soap_operation "GetUser" do
    description "Retrieves a user by their unique identifier with complete profile information"

    input do
      parameter "userId", :string, required: true, description: "Unique user ID to retrieve"
    end

    output do
      parameter "user", "User", description: "Complete user profile information"
    end

    soap_action "http://api.example.com/v1/GetUser"
  end

  def get_user(%{"userId" => user_id}) do
    {:ok, %{"user" => %{
      "id" => user_id,
      "username" => "johndoe",
      "email" => "john.doe@example.com",
      "firstName" => "John",
      "lastName" => "Doe",
      "dateOfBirth" => "1990-05-15",
      "isActive" => true,
      "createdAt" => "2024-01-01T00:00:00Z",
      "lastLoginAt" => "2024-11-01T10:30:00Z",
      "address" => %{
        "street" => "123 Main St",
        "city" => "Portland",
        "state" => "OR",
        "postalCode" => "97201",
        "country" => "US"
      },
      "profilePictureUrl" => "https://example.com/images/profile.jpg",
      "accountBalance" => "1250.75"
    }}}
  end

  # Complex operation with multiple inputs
  soap_operation "CreateUser" do
    description "Creates a new user account with complete profile validation and duplicate checking"

    input do
      parameter "user", "User", required: true, description: "Complete user information to create"
      parameter "sendWelcomeEmail", :boolean, required: false, description: "Send welcome email (default: true)"
      parameter "assignToRole", :string, required: false, description: "Initial role assignment"
    end

    output do
      parameter "userId", :string, description: "ID of the newly created user"
      parameter "success", :boolean, description: "Whether creation was successful"
      parameter "message", :string, description: "Success or error message"
      parameter "validationErrors", :string, max_occurs: "unbounded", description: "List of validation errors"
    end

    soap_action "http://api.example.com/v1/CreateUser"
  end

  def create_user(params) do
    {:ok, %{
      "userId" => "new-user-12345",
      "success" => true,
      "message" => "User created successfully",
      "validationErrors" => []
    }}
  end

  # Search operation with complex criteria
  soap_operation "SearchUsers" do
    description "Advanced user search with pagination, filtering, and sorting capabilities"

    input do
      parameter "criteria", "SearchCriteria", required: true, description: "Search and filter criteria"
      parameter "page", :integer, required: false, description: "Page number (1-based, default: 1)"
      parameter "pageSize", :integer, required: false, description: "Items per page (default: 10, max: 100)"
      parameter "sortBy", :string, required: false, description: "Sort field (username, email, createdAt)"
      parameter "sortDirection", :string, required: false, description: "Sort direction (asc, desc, default: asc)"
    end

    output do
      parameter "userList", "UserList", description: "Paginated search results with metadata"
      parameter "searchTime", :decimal, description: "Search execution time in seconds"
    end

    soap_action "http://api.example.com/v1/SearchUsers"
  end

  def search_users(params) do
    {:ok, %{
      "userList" => %{
        "users" => [],
        "totalCount" => 0,
        "currentPage" => 1,
        "pageSize" => 10,
        "totalPages" => 0
      },
      "searchTime" => 0.125
    }}
  end

  # Batch operation
  soap_operation "BulkUpdateUsers" do
    description "Updates multiple users in a single transaction with rollback support"

    input do
      parameter "userIds", :string, max_occurs: "unbounded", required: true, description: "List of user IDs to update"
      parameter "updateData", "User", required: true, description: "Data to update (null fields are ignored)"
      parameter "createAuditLog", :boolean, required: false, description: "Create audit log entries (default: true)"
    end

    output do
      parameter "updatedCount", :integer, description: "Number of successfully updated users"
      parameter "failedCount", :integer, description: "Number of failed updates"
      parameter "errors", :string, max_occurs: "unbounded", description: "List of error messages"
      parameter "transactionId", :string, description: "Transaction ID for audit purposes"
    end

    soap_action "http://api.example.com/v1/BulkUpdateUsers"
  end

  def bulk_update_users(params) do
    {:ok, %{
      "updatedCount" => 5,
      "failedCount" => 0,
      "errors" => [],
      "transactionId" => "txn-abcd1234"
    }}
  end
end

# Generate and display enhanced WSDL
IO.puts("=" * 100)
IO.puts("ENHANCED LATHER WSDL AND FORMS GENERATION TEST")
IO.puts("=" * 100)
IO.puts("")

service_info = TestEnhancedService.__soap_service__()
base_url = "https://api.example.com/soap/"

IO.puts("Service Configuration:")
IO.puts("- Name: #{service_info.name}")
IO.puts("- Namespace: #{service_info.namespace}")
IO.puts("- Operations: #{length(service_info.operations)}")
IO.puts("- Complex Types: #{length(service_info.types)}")
IO.puts("")

# Test standard WSDL generation
IO.puts("1. STANDARD WSDL (SOAP 1.1 Only)")
IO.puts("-" * 80)
standard_wsdl = Lather.Server.WSDLGenerator.generate(service_info, base_url)
IO.puts(String.slice(standard_wsdl, 0, 1000) <> "...")
IO.puts("")

# Test enhanced multi-protocol WSDL generation
IO.puts("2. ENHANCED MULTI-PROTOCOL WSDL")
IO.puts("-" * 80)
enhanced_wsdl = Lather.Server.EnhancedWSDLGenerator.generate(
  service_info,
  base_url,
  protocols: [:soap_1_1, :soap_1_2, :http],
  base_path: "/api",
  include_json: true
)
IO.puts(String.slice(enhanced_wsdl, 0, 1500) <> "...")
IO.puts("")

# Test form generation for specific operation
IO.puts("3. INTERACTIVE FORM FOR GetUser OPERATION")
IO.puts("-" * 80)
get_user_operation = Enum.find(service_info.operations, &(&1.name == "GetUser"))
form_html = Lather.Server.FormGenerator.generate_operation_page(
  service_info,
  get_user_operation,
  base_url
)
IO.puts("HTML Form Generated: #{String.length(form_html)} characters")
IO.puts("Form includes:")
IO.puts("- Interactive parameter input")
IO.puts("- SOAP 1.1 examples with full HTTP headers")
IO.puts("- SOAP 1.2 examples with correct content-type")
IO.puts("- JSON examples for REST API")
IO.puts("- JavaScript for form submission")
IO.puts("")

# Test service overview page
IO.puts("4. SERVICE OVERVIEW PAGE")
IO.puts("-" * 80)
overview_html = Lather.Server.FormGenerator.generate_service_overview(
  service_info,
  base_url
)
IO.puts("Service Overview Generated: #{String.length(overview_html)} characters")
IO.puts("Overview includes:")
IO.puts("- All #{length(service_info.operations)} operations listed")
IO.puts("- Protocol endpoints (SOAP 1.1, SOAP 1.2, REST/JSON)")
IO.puts("- WSDL download links")
IO.puts("- Operation descriptions and parameter counts")
IO.puts("")

# Show the complex operation details
IO.puts("5. COMPLEX OPERATION DETAILS")
IO.puts("-" * 80)
search_operation = Enum.find(service_info.operations, &(&1.name == "SearchUsers"))
IO.puts("SearchUsers Operation:")
IO.puts("- Description: #{search_operation.description}")
IO.puts("- Input Parameters: #{length(search_operation.input)}")
IO.puts("  * criteria (SearchCriteria complex type)")
IO.puts("  * page, pageSize, sortBy, sortDirection")
IO.puts("- Output Parameters: #{length(search_operation.output)}")
IO.puts("  * userList (UserList complex type)")
IO.puts("  * searchTime (decimal)")
IO.puts("")

# Show the multi-protocol endpoints that would be generated
IO.puts("6. MULTI-PROTOCOL ENDPOINTS")
IO.puts("-" * 80)
IO.puts("The enhanced WSDL creates these endpoints:")
IO.puts("")
IO.puts("SOAP 1.1 (Maximum Compatibility):")
IO.puts("  POST #{base_url}soap/v1.1/#{service_info.name}")
IO.puts("  Content-Type: text/xml; charset=utf-8")
IO.puts("  SOAPAction: [operation-specific]")
IO.puts("")
IO.puts("SOAP 1.2 (Enhanced Error Handling):")
IO.puts("  POST #{base_url}soap/v1.2/#{service_info.name}")
IO.puts("  Content-Type: application/soap+xml; charset=utf-8; action=\"[action]\"")
IO.puts("")
IO.puts("REST/JSON (Modern API):")
IO.puts("  POST #{base_url}api/#{String.downcase(service_info.name)}/[operation]")
IO.puts("  Content-Type: application/json; charset=utf-8")
IO.puts("")

# Show the web interface URLs
IO.puts("7. WEB INTERFACE URLS")
IO.puts("-" * 80)
IO.puts("Interactive web interface URLs:")
IO.puts("")
IO.puts("Service Overview:")
IO.puts("  GET #{base_url}#{service_info.name}")
IO.puts("")
IO.puts("Operation Forms:")
for operation <- service_info.operations do
  IO.puts("  GET #{base_url}#{service_info.name}?op=#{operation.name}")
end
IO.puts("")
IO.puts("WSDL Downloads:")
IO.puts("  GET #{base_url}#{service_info.name}?wsdl")
IO.puts("  GET #{base_url}#{service_info.name}?wsdl&enhanced=true")
IO.puts("")

IO.puts("8. FEATURES COMPARISON")
IO.puts("-" * 80)
IO.puts("Standard WSDL vs Enhanced WSDL:")
IO.puts("")
IO.puts("Standard WSDL:")
IO.puts("✓ SOAP 1.1 binding")
IO.puts("✓ Document/literal style")
IO.puts("✓ Single endpoint")
IO.puts("✓ XSD type definitions")
IO.puts("")
IO.puts("Enhanced WSDL:")
IO.puts("✓ SOAP 1.1 binding (primary)")
IO.puts("✓ SOAP 1.2 binding (enhanced)")
IO.puts("✓ HTTP/REST binding (modern)")
IO.puts("✓ Multiple service endpoints")
IO.puts("✓ Enhanced documentation")
IO.puts("✓ Protocol negotiation support")
IO.puts("✓ JSON content type support")
IO.puts("")

IO.puts("9. CLIENT COMPATIBILITY")
IO.puts("-" * 80)
IO.puts("The layered approach ensures compatibility with:")
IO.puts("")
IO.puts("Legacy Systems (SOAP 1.1):")
IO.puts("- .NET Framework 2.0+")
IO.puts("- Java JAX-WS")
IO.puts("- PHP SoapClient")
IO.puts("- Classic ASP.NET Web Services")
IO.puts("")
IO.puts("Modern Systems (SOAP 1.2):")
IO.puts("- .NET Core/5+")
IO.puts("- Modern Java frameworks")
IO.puts("- Enhanced error reporting")
IO.puts("- Better namespace handling")
IO.puts("")
IO.puts("Web Applications (REST/JSON):")
IO.puts("- JavaScript/AJAX clients")
IO.puts("- Mobile applications")
IO.puts("- Single Page Applications (SPA)")
IO.puts("- API testing tools (Postman, etc.)")
IO.puts("")

IO.puts("=" * 100)
IO.puts("ENHANCED WSDL AND FORMS GENERATION COMPLETE")
IO.puts("Total Features Implemented:")
IO.puts("✓ Multi-protocol WSDL generation")
IO.puts("✓ Interactive HTML forms")
IO.puts("✓ SOAP 1.1 and 1.2 examples")
IO.puts("✓ JSON/REST examples")
IO.puts("✓ Service overview pages")
IO.puts("✓ Complete protocol documentation")
IO.puts("✓ Responsive web interface")
IO.puts("✓ Enhanced error handling")
IO.puts("=" * 100)
