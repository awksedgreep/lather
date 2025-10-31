defmodule EnterpriseServiceExample do
  @moduledoc """
  Example of using Lather with an enterprise SOAP service.

  This example demonstrates:
  - Authentication (Basic Auth and WS-Security)
  - SSL/TLS configuration
  - Complex parameter structures
  - Error handling and recovery
  - Connection pooling
  """

  @enterprise_wsdl "https://enterprise.example.com/services/UserService?wsdl"

  def run do
    IO.puts("Enterprise Service Example")
    IO.puts("========================")

    case connect_with_auth() do
      {:ok, client} ->
        demo_enterprise_operations(client)
      {:error, error} ->
        IO.puts("Failed to connect: #{Lather.Error.format_error(error)}")
    end
  end

  defp connect_with_auth do
    IO.puts("Connecting to enterprise service with authentication...")

    # Configuration for enterprise service
    options = [
      # Basic authentication
      basic_auth: {get_username(), get_password()},

      # SSL configuration
      ssl_options: ssl_config(),

      # Timeouts
      timeout: 60_000,
      pool_timeout: 10_000,

      # Custom headers
      headers: [
        {"User-Agent", "MyApp/1.0"},
        {"X-API-Version", "2.0"}
      ]
    ]

    case Lather.DynamicClient.new(@enterprise_wsdl, options) do
      {:ok, client} ->
        IO.puts("✓ Connected successfully with authentication!")
        {:ok, client}

      {:error, error} ->
        IO.puts("✗ Connection failed: #{Lather.Error.format_error(error)}")

        # Check if error is recoverable
        if Lather.Error.recoverable?(error) do
          IO.puts("Error is recoverable, you might want to retry...")
        end

        {:error, error}
    end
  end

  defp demo_enterprise_operations(client) do
    IO.puts("\nAvailable operations:")
    operations = Lather.DynamicClient.list_operations(client)
    Enum.each(operations, fn op -> IO.puts("  - #{op}") end)

    # Demo different operation types
    demo_list_users(client)
    demo_create_user(client)
    demo_update_user(client)
    demo_complex_search(client)
    demo_batch_operations(client)
  end

  defp demo_list_users(client) do
    IO.puts("\n👥 Listing users in Engineering department...")

    params = %{
      "department" => "Engineering",
      "active" => true,
      "pageSize" => 10,
      "pageNumber" => 1
    }

    case execute_with_retry(client, "ListUsers", params) do
      {:ok, response} ->
        IO.puts("✓ Users retrieved successfully")
        display_users(response)

      {:error, error} ->
        handle_error("ListUsers", error)
    end
  end

  defp demo_create_user(client) do
    IO.puts("\n➕ Creating a new user...")

    # Complex nested parameters
    params = %{
      "user" => %{
        "personalInfo" => %{
          "firstName" => "John",
          "lastName" => "Doe",
          "email" => "john.doe@company.com",
          "phone" => "+1-555-0123"
        },
        "workInfo" => %{
          "department" => "Engineering",
          "title" => "Software Engineer",
          "manager" => "jane.smith@company.com",
          "startDate" => "2024-01-15"
        },
        "permissions" => [
          "read_projects",
          "write_code",
          "access_development_tools"
        ],
        "metadata" => %{
          "source" => "api",
          "requestId" => generate_request_id()
        }
      }
    }

    case execute_with_retry(client, "CreateUser", params) do
      {:ok, response} ->
        IO.puts("✓ User created successfully")
        display_create_response(response)

      {:error, error} ->
        handle_error("CreateUser", error)
    end
  end

  defp demo_update_user(client) do
    IO.puts("\n✏️ Updating user information...")

    params = %{
      "userId" => "12345",
      "updates" => %{
        "workInfo" => %{
          "title" => "Senior Software Engineer",
          "department" => "Engineering"
        },
        "permissions" => [
          "read_projects",
          "write_code",
          "access_development_tools",
          "mentor_junior_developers"
        ]
      },
      "options" => %{
        "sendNotification" => true,
        "auditReason" => "Promotion"
      }
    }

    case execute_with_retry(client, "UpdateUser", params) do
      {:ok, response} ->
        IO.puts("✓ User updated successfully")
        display_update_response(response)

      {:error, error} ->
        handle_error("UpdateUser", error)
    end
  end

  defp demo_complex_search(client) do
    IO.puts("\n🔍 Performing complex user search...")

    params = %{
      "searchCriteria" => %{
        "filters" => [
          %{
            "field" => "department",
            "operator" => "equals",
            "value" => "Engineering"
          },
          %{
            "field" => "active",
            "operator" => "equals",
            "value" => true
          },
          %{
            "field" => "startDate",
            "operator" => "greaterThan",
            "value" => "2023-01-01"
          }
        ],
        "sorting" => [
          %{
            "field" => "lastName",
            "direction" => "asc"
          },
          %{
            "field" => "startDate",
            "direction" => "desc"
          }
        ],
        "pagination" => %{
          "pageSize" => 25,
          "pageNumber" => 1
        }
      },
      "includeFields" => [
        "personalInfo",
        "workInfo",
        "permissions"
      ]
    }

    case execute_with_retry(client, "SearchUsers", params) do
      {:ok, response} ->
        IO.puts("✓ Search completed successfully")
        display_search_response(response)

      {:error, error} ->
        handle_error("SearchUsers", error)
    end
  end

  defp demo_batch_operations(client) do
    IO.puts("\n📦 Performing batch operations...")

    # Create multiple users in a single request
    params = %{
      "batchRequest" => %{
        "operations" => [
          %{
            "type" => "create",
            "user" => %{
              "personalInfo" => %{
                "firstName" => "Alice",
                "lastName" => "Johnson",
                "email" => "alice.johnson@company.com"
              },
              "workInfo" => %{
                "department" => "Marketing",
                "title" => "Marketing Manager"
              }
            }
          },
          %{
            "type" => "create",
            "user" => %{
              "personalInfo" => %{
                "firstName" => "Bob",
                "lastName" => "Wilson",
                "email" => "bob.wilson@company.com"
              },
              "workInfo" => %{
                "department" => "Sales",
                "title" => "Sales Representative"
              }
            }
          }
        ],
        "options" => %{
          "continueOnError" => true,
          "transactional" => false
        }
      }
    }

    case execute_with_retry(client, "BatchUserOperations", params) do
      {:ok, response} ->
        IO.puts("✓ Batch operations completed")
        display_batch_response(response)

      {:error, error} ->
        handle_error("BatchUserOperations", error)
    end
  end

  # Execute with automatic retry on recoverable errors
  defp execute_with_retry(client, operation, params, retry_count \\ 0) do
    case Lather.DynamicClient.call(client, operation, params) do
      {:ok, response} ->
        {:ok, response}

      {:error, error} ->
        if retry_count < 3 and Lather.Error.recoverable?(error) do
          IO.puts("   Retrying operation (attempt #{retry_count + 1})...")
          :timer.sleep(1000 * (retry_count + 1))  # Exponential backoff
          execute_with_retry(client, operation, params, retry_count + 1)
        else
          {:error, error}
        end
    end
  end

  defp handle_error(operation, error) do
    case error do
      %{type: :soap_fault} = fault ->
        IO.puts("✗ SOAP Fault in #{operation}:")
        IO.puts("   Code: #{fault.fault_code}")
        IO.puts("   Message: #{fault.fault_string}")
        if fault.detail do
          IO.puts("   Detail: #{inspect(fault.detail)}")
        end

      %{type: :http_error} = http_error ->
        IO.puts("✗ HTTP Error in #{operation}:")
        IO.puts("   Status: #{http_error.status}")
        IO.puts("   Body: #{String.slice(http_error.body, 0, 200)}")

      %{type: :transport_error} = transport_error ->
        IO.puts("✗ Transport Error in #{operation}:")
        IO.puts("   Reason: #{transport_error.reason}")

      %{type: :validation_error} = validation_error ->
        IO.puts("✗ Validation Error in #{operation}:")
        IO.puts("   Field: #{validation_error.field}")
        IO.puts("   Reason: #{validation_error.reason}")

      other ->
        IO.puts("✗ Unknown Error in #{operation}: #{inspect(other)}")
    end
  end

  # Configuration helpers
  defp get_username do
    System.get_env("SOAP_USERNAME") || "demo_user"
  end

  defp get_password do
    System.get_env("SOAP_PASSWORD") || "demo_password"
  end

  defp ssl_config do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ],
      versions: [:"tlsv1.2", :"tlsv1.3"],
      ciphers: :ssl.cipher_suites(:default, :"tlsv1.2")
    ]
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  # Response display helpers
  defp display_users(%{"ListUsersResult" => users}) when is_list(users) do
    IO.puts("   Found #{length(users)} users:")
    Enum.take(users, 3) |> Enum.each(fn user ->
      name = get_in(user, ["personalInfo", "firstName"]) <> " " <> get_in(user, ["personalInfo", "lastName"])
      dept = get_in(user, ["workInfo", "department"])
      IO.puts("     - #{name} (#{dept})")
    end)
    if length(users) > 3, do: IO.puts("     ... and #{length(users) - 3} more")
  end

  defp display_users(response) do
    IO.puts("   #{inspect(response, pretty: true)}")
  end

  defp display_create_response(%{"CreateUserResult" => result}) do
    IO.puts("   User ID: #{result["userId"]}")
    IO.puts("   Status: #{result["status"]}")
  end

  defp display_create_response(response) do
    IO.puts("   #{inspect(response, pretty: true)}")
  end

  defp display_update_response(%{"UpdateUserResult" => result}) do
    IO.puts("   Updated: #{result["updated"]}")
    IO.puts("   Version: #{result["version"]}")
  end

  defp display_update_response(response) do
    IO.puts("   #{inspect(response, pretty: true)}")
  end

  defp display_search_response(%{"SearchUsersResult" => result}) do
    IO.puts("   Total matches: #{result["totalCount"]}")
    IO.puts("   Returned: #{length(result["users"])}")
    IO.puts("   Page: #{result["pageNumber"]} of #{result["totalPages"]}")
  end

  defp display_search_response(response) do
    IO.puts("   #{inspect(response, pretty: true)}")
  end

  defp display_batch_response(%{"BatchUserOperationsResult" => result}) do
    IO.puts("   Successful: #{result["successCount"]}")
    IO.puts("   Failed: #{result["failureCount"]}")
    if result["failures"] && length(result["failures"]) > 0 do
      IO.puts("   Failures:")
      Enum.each(result["failures"], fn failure ->
        IO.puts("     - #{failure["operation"]}: #{failure["error"]}")
      end)
    end
  end

  defp display_batch_response(response) do
    IO.puts("   #{inspect(response, pretty: true)}")
  end

  # WS-Security example
  def connect_with_wssecurity do
    IO.puts("Connecting with WS-Security...")

    # Create WS-Security username token
    username_token = Lather.Auth.WSSecurity.username_token(
      get_username(),
      get_password(),
      timestamp: true,
      nonce: true
    )

    # Create security header
    security_header = Lather.Auth.WSSecurity.security_header(username_token, [])

    options = [
      soap_headers: [security_header],
      ssl_options: ssl_config(),
      timeout: 60_000
    ]

    case Lather.DynamicClient.new(@enterprise_wsdl, options) do
      {:ok, client} ->
        IO.puts("✓ Connected with WS-Security!")
        {:ok, client}

      {:error, error} ->
        IO.puts("✗ WS-Security connection failed: #{Lather.Error.format_error(error)}")
        {:error, error}
    end
  end

  # Connection pooling example
  def setup_connection_pool do
    # Configure Finch with custom pools for different endpoints
    finch_config = [
      name: Lather.Finch,
      pools: %{
        "https://enterprise.example.com" => [
          size: 25,
          count: 4,
          protocols: [:http2, :http1]
        ],
        "https://api.example.com" => [
          size: 10,
          count: 2
        ]
      }
    ]

    # This would be done in your application supervision tree
    # {Finch, finch_config}
    IO.puts("Connection pool configured for enterprise endpoints")
  end
end

# Run the example
if __name__ == :main do
  EnterpriseServiceExample.run()
end
