defmodule Examples.Servers.UserService do
  @moduledoc """
  A comprehensive user management SOAP service.

  Demonstrates:
  - Complex type definitions
  - CRUD operations
  - Data validation
  - Error handling with detailed SOAP faults
  - Business logic implementation

  ## Operations

  - GetUser - Retrieve user by ID
  - CreateUser - Create a new user
  - UpdateUser - Update existing user
  - DeleteUser - Delete user by ID
  - ListUsers - Get paginated list of users
  - SearchUsers - Search users by criteria
  """

  use Lather.Server

  @namespace "http://examples.com/users"
  @service_name "UserService"

  # Define complex types
  soap_type "User" do
    description "User information"

    element "id", :string, required: true, description: "Unique user identifier"
    element "username", :string, required: true, description: "Username"
    element "email", :string, required: true, description: "Email address"
    element "firstName", :string, required: true, description: "First name"
    element "lastName", :string, required: true, description: "Last name"
    element "isActive", :boolean, required: true, description: "Account status"
    element "createdAt", :dateTime, required: true, description: "Account creation date"
    element "lastLoginAt", :dateTime, required: false, description: "Last login timestamp"
  end

  soap_type "UserList" do
    description "Paginated list of users"

    element "users", "User", max_occurs: "unbounded", description: "List of users"
    element "totalCount", :int, required: true, description: "Total number of users"
    element "page", :int, required: true, description: "Current page number"
    element "pageSize", :int, required: true, description: "Number of users per page"
  end

  soap_type "SearchCriteria" do
    description "User search criteria"

    element "username", :string, required: false, description: "Username pattern"
    element "email", :string, required: false, description: "Email pattern"
    element "firstName", :string, required: false, description: "First name pattern"
    element "lastName", :string, required: false, description: "Last name pattern"
    element "isActive", :boolean, required: false, description: "Account status filter"
  end

  # GetUser operation
  soap_operation "GetUser" do
    description "Retrieves a user by their unique identifier"

    input do
      parameter "userId", :string, required: true, description: "User ID to retrieve"
    end

    output do
      parameter "user", "User", description: "User information"
    end

    soap_action "http://examples.com/users/GetUser"
  end

  def get_user(%{"userId" => user_id}) do
    case UserStore.get_user(user_id) do
      {:ok, user} ->
        {:ok, %{"user" => user}}

      {:error, :not_found} ->
        soap_fault("Client", "User not found", %{userId: user_id})

      {:error, reason} ->
        soap_fault("Server", "Failed to retrieve user: #{reason}")
    end
  end

  # CreateUser operation
  soap_operation "CreateUser" do
    description "Creates a new user account"

    input do
      parameter "user", "User", required: true, description: "User information to create"
    end

    output do
      parameter "userId", :string, description: "ID of the created user"
      parameter "user", "User", description: "Created user information"
    end

    soap_action "http://examples.com/users/CreateUser"
  end

  def create_user(%{"user" => user_data}) do
    with {:ok, validated_user} <- validate_user_data(user_data),
         {:ok, created_user} <- UserStore.create_user(validated_user) do
      {:ok, %{
        "userId" => created_user["id"],
        "user" => created_user
      }}
    else
      {:error, validation_errors} when is_list(validation_errors) ->
        soap_fault("Client", "Validation failed", %{errors: validation_errors})

      {:error, :username_exists} ->
        soap_fault("Client", "Username already exists", %{username: user_data["username"]})

      {:error, :email_exists} ->
        soap_fault("Client", "Email already exists", %{email: user_data["email"]})

      {:error, reason} ->
        soap_fault("Server", "Failed to create user: #{reason}")
    end
  end

  # UpdateUser operation
  soap_operation "UpdateUser" do
    description "Updates an existing user account"

    input do
      parameter "userId", :string, required: true, description: "ID of user to update"
      parameter "user", "User", required: true, description: "Updated user information"
    end

    output do
      parameter "user", "User", description: "Updated user information"
    end

    soap_action "http://examples.com/users/UpdateUser"
  end

  def update_user(%{"userId" => user_id, "user" => user_data}) do
    with {:ok, existing_user} <- UserStore.get_user(user_id),
         {:ok, validated_user} <- validate_user_data(user_data),
         {:ok, updated_user} <- UserStore.update_user(user_id, validated_user) do
      {:ok, %{"user" => updated_user}}
    else
      {:error, :not_found} ->
        soap_fault("Client", "User not found", %{userId: user_id})

      {:error, validation_errors} when is_list(validation_errors) ->
        soap_fault("Client", "Validation failed", %{errors: validation_errors})

      {:error, reason} ->
        soap_fault("Server", "Failed to update user: #{reason}")
    end
  end

  # DeleteUser operation
  soap_operation "DeleteUser" do
    description "Deletes a user account"

    input do
      parameter "userId", :string, required: true, description: "ID of user to delete"
    end

    output do
      parameter "success", :boolean, description: "Whether deletion was successful"
      parameter "message", :string, description: "Deletion result message"
    end

    soap_action "http://examples.com/users/DeleteUser"
  end

  def delete_user(%{"userId" => user_id}) do
    case UserStore.delete_user(user_id) do
      :ok ->
        {:ok, %{
          "success" => true,
          "message" => "User deleted successfully"
        }}

      {:error, :not_found} ->
        soap_fault("Client", "User not found", %{userId: user_id})

      {:error, :cannot_delete_active_user} ->
        soap_fault("Client", "Cannot delete active user", %{userId: user_id})

      {:error, reason} ->
        soap_fault("Server", "Failed to delete user: #{reason}")
    end
  end

  # ListUsers operation
  soap_operation "ListUsers" do
    description "Retrieves a paginated list of users"

    input do
      parameter "page", :int, required: false, description: "Page number (default: 1)"
      parameter "pageSize", :int, required: false, description: "Users per page (default: 10)"
    end

    output do
      parameter "userList", "UserList", description: "Paginated list of users"
    end

    soap_action "http://examples.com/users/ListUsers"
  end

  def list_users(params) do
    page = Map.get(params, "page", "1") |> String.to_integer()
    page_size = Map.get(params, "pageSize", "10") |> String.to_integer()

    case UserStore.list_users(page, page_size) do
      {:ok, users, total_count} ->
        {:ok, %{
          "userList" => %{
            "users" => users,
            "totalCount" => total_count,
            "page" => page,
            "pageSize" => page_size
          }
        }}

      {:error, reason} ->
        soap_fault("Server", "Failed to list users: #{reason}")
    end
  end

  # SearchUsers operation
  soap_operation "SearchUsers" do
    description "Searches for users based on criteria"

    input do
      parameter "criteria", "SearchCriteria", required: true, description: "Search criteria"
      parameter "page", :int, required: false, description: "Page number (default: 1)"
      parameter "pageSize", :int, required: false, description: "Users per page (default: 10)"
    end

    output do
      parameter "userList", "UserList", description: "Matching users"
    end

    soap_action "http://examples.com/users/SearchUsers"
  end

  def search_users(%{"criteria" => criteria} = params) do
    page = Map.get(params, "page", "1") |> String.to_integer()
    page_size = Map.get(params, "pageSize", "10") |> String.to_integer()

    case UserStore.search_users(criteria, page, page_size) do
      {:ok, users, total_count} ->
        {:ok, %{
          "userList" => %{
            "users" => users,
            "totalCount" => total_count,
            "page" => page,
            "pageSize" => page_size
          }
        }}

      {:error, reason} ->
        soap_fault("Server", "Failed to search users: #{reason}")
    end
  end

  # Private helper functions
  defp validate_user_data(user_data) do
    errors = []

    errors = if valid_email?(user_data["email"]) do
      errors
    else
      ["Invalid email format" | errors]
    end

    errors = if valid_username?(user_data["username"]) do
      errors
    else
      ["Username must be 3-50 characters, alphanumeric and underscores only" | errors]
    end

    errors = if String.length(user_data["firstName"] || "") >= 1 do
      errors
    else
      ["First name is required" | errors]
    end

    errors = if String.length(user_data["lastName"] || "") >= 1 do
      errors
    else
      ["Last name is required" | errors]
    end

    case errors do
      [] -> {:ok, user_data}
      errors -> {:error, errors}
    end
  end

  defp valid_email?(email) do
    email_regex = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
    Regex.match?(email_regex, email || "")
  end

  defp valid_username?(username) do
    username_regex = ~r/^[a-zA-Z0-9_]{3,50}$/
    Regex.match?(username_regex, username || "")
  end
end

# Mock data store for demonstration
defmodule UserStore do
  @moduledoc """
  Mock user data store for demonstration purposes.
  In a real application, this would interface with a database.
  """

  def get_user("123") do
    {:ok, %{
      "id" => "123",
      "username" => "johndoe",
      "email" => "john.doe@example.com",
      "firstName" => "John",
      "lastName" => "Doe",
      "isActive" => true,
      "createdAt" => "2024-01-01T00:00:00Z",
      "lastLoginAt" => "2024-10-30T10:30:00Z"
    }}
  end

  def get_user("456") do
    {:ok, %{
      "id" => "456",
      "username" => "janedoe",
      "email" => "jane.doe@example.com",
      "firstName" => "Jane",
      "lastName" => "Doe",
      "isActive" => true,
      "createdAt" => "2024-01-15T00:00:00Z",
      "lastLoginAt" => "2024-10-29T15:45:00Z"
    }}
  end

  def get_user(_), do: {:error, :not_found}

  def create_user(user_data) do
    # Check for existing username/email
    if user_data["username"] == "existing_user" do
      {:error, :username_exists}
    else
      new_id = generate_id()
      created_user = Map.merge(user_data, %{
        "id" => new_id,
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "isActive" => true
      })
      {:ok, created_user}
    end
  end

  def update_user(user_id, user_data) do
    case get_user(user_id) do
      {:ok, existing_user} ->
        updated_user = Map.merge(existing_user, user_data)
        {:ok, updated_user}
      error ->
        error
    end
  end

  def delete_user("123"), do: {:error, :cannot_delete_active_user}
  def delete_user("456"), do: :ok
  def delete_user(_), do: {:error, :not_found}

  def list_users(page, page_size) do
    all_users = [
      %{
        "id" => "123",
        "username" => "johndoe",
        "email" => "john.doe@example.com",
        "firstName" => "John",
        "lastName" => "Doe",
        "isActive" => true,
        "createdAt" => "2024-01-01T00:00:00Z",
        "lastLoginAt" => "2024-10-30T10:30:00Z"
      },
      %{
        "id" => "456",
        "username" => "janedoe",
        "email" => "jane.doe@example.com",
        "firstName" => "Jane",
        "lastName" => "Doe",
        "isActive" => true,
        "createdAt" => "2024-01-15T00:00:00Z",
        "lastLoginAt" => "2024-10-29T15:45:00Z"
      }
    ]

    start_index = (page - 1) * page_size
    users = Enum.slice(all_users, start_index, page_size)
    total_count = length(all_users)

    {:ok, users, total_count}
  end

  def search_users(criteria, page, page_size) do
    # Simple mock search implementation
    all_users = [
      %{
        "id" => "123",
        "username" => "johndoe",
        "email" => "john.doe@example.com",
        "firstName" => "John",
        "lastName" => "Doe",
        "isActive" => true,
        "createdAt" => "2024-01-01T00:00:00Z",
        "lastLoginAt" => "2024-10-30T10:30:00Z"
      },
      %{
        "id" => "456",
        "username" => "janedoe",
        "email" => "jane.doe@example.com",
        "firstName" => "Jane",
        "lastName" => "Doe",
        "isActive" => true,
        "createdAt" => "2024-01-15T00:00:00Z",
        "lastLoginAt" => "2024-10-29T15:45:00Z"
      }
    ]

    filtered_users = Enum.filter(all_users, fn user ->
      matches_criteria?(user, criteria)
    end)

    start_index = (page - 1) * page_size
    users = Enum.slice(filtered_users, start_index, page_size)
    total_count = length(filtered_users)

    {:ok, users, total_count}
  end

  defp matches_criteria?(user, criteria) do
    Enum.all?(criteria, fn {field, value} ->
      case field do
        "username" -> String.contains?(user["username"], value)
        "email" -> String.contains?(user["email"], value)
        "firstName" -> String.contains?(user["firstName"], value)
        "lastName" -> String.contains?(user["lastName"], value)
        "isActive" -> user["isActive"] == value
        _ -> true
      end
    end)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
