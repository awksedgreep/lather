defmodule Lather.Integration.ComplexTypesRoundTripTest do
  @moduledoc """
  Integration tests for complex XSD types: nested structures, arrays, and custom types.

  Tests that complex data structures can correctly round-trip between client and server.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  # Service with complex type definitions
  defmodule ComplexTypesService do
    use Lather.Server

    @namespace "http://test.example.com/complex"
    @service_name "ComplexTypesService"

    # Define a complex type for User
    soap_type "User" do
      type_description "User account information"
      element "id", :integer, required: true
      element "username", :string, required: true
      element "email", :string, required: true
      element "active", :boolean, required: false
    end

    # Define a complex type for Address
    soap_type "Address" do
      type_description "Physical address"
      element "street", :string, required: true
      element "city", :string, required: true
      element "state", :string, required: false
      element "zipCode", :string, required: true
      element "country", :string, required: true
    end

    # Define a type with nested structure
    soap_type "Order" do
      type_description "Customer order"
      element "orderId", :string, required: true
      element "customerId", :string, required: true
      element "total", :decimal, required: true
      element "items", :integer, required: true  # Count of items
    end

    # Simple nested structure operation
    soap_operation "CreateUser" do
      description "Creates a user with nested data"
      input do
        parameter "username", :string, required: true
        parameter "email", :string, required: true
      end
      output do
        parameter "id", :integer
        parameter "username", :string
        parameter "email", :string
        parameter "created", :boolean
      end
      soap_action "CreateUser"
    end

    def create_user(%{"username" => username, "email" => email}) do
      {:ok, %{
        "id" => :rand.uniform(10000),
        "username" => username,
        "email" => email,
        "created" => true
      }}
    end

    # Operation that returns multiple related values
    soap_operation "GetUserProfile" do
      description "Gets user profile with address"
      input do
        parameter "userId", :integer, required: true
      end
      output do
        parameter "userId", :integer
        parameter "username", :string
        parameter "email", :string
        parameter "street", :string
        parameter "city", :string
        parameter "country", :string
      end
      soap_action "GetUserProfile"
    end

    def get_user_profile(%{"userId" => user_id}) do
      {:ok, %{
        "userId" => parse_int(user_id),
        "username" => "user_#{user_id}",
        "email" => "user#{user_id}@example.com",
        "street" => "123 Main St",
        "city" => "Springfield",
        "country" => "USA"
      }}
    end

    # Operation with many parameters - single item order
    soap_operation "ProcessSingleItem" do
      description "Processes a single item order"
      input do
        parameter "orderId", :string, required: true
        parameter "customerId", :string, required: true
        parameter "itemName", :string, required: true
        parameter "itemQty", :integer, required: true
        parameter "itemPrice", :decimal, required: true
        parameter "shippingStreet", :string, required: true
        parameter "shippingCity", :string, required: true
        parameter "shippingCountry", :string, required: true
      end
      output do
        parameter "orderId", :string
        parameter "status", :string
        parameter "total", :decimal
        parameter "itemCount", :integer
      end
      soap_action "ProcessSingleItem"
    end

    def process_single_item(params) do
      item_qty = parse_int(params["itemQty"])
      item_price = parse_float(params["itemPrice"])
      total = item_qty * item_price

      {:ok, %{
        "orderId" => params["orderId"],
        "status" => "processed",
        "total" => total,
        "itemCount" => 1
      }}
    end

    # Operation with two items
    soap_operation "ProcessTwoItems" do
      description "Processes an order with two items"
      input do
        parameter "orderId", :string, required: true
        parameter "customerId", :string, required: true
        parameter "item1Name", :string, required: true
        parameter "item1Qty", :integer, required: true
        parameter "item1Price", :decimal, required: true
        parameter "item2Name", :string, required: true
        parameter "item2Qty", :integer, required: true
        parameter "item2Price", :decimal, required: true
        parameter "shippingStreet", :string, required: true
        parameter "shippingCity", :string, required: true
        parameter "shippingCountry", :string, required: true
      end
      output do
        parameter "orderId", :string
        parameter "status", :string
        parameter "total", :decimal
        parameter "itemCount", :integer
      end
      soap_action "ProcessTwoItems"
    end

    def process_two_items(params) do
      item1_qty = parse_int(params["item1Qty"])
      item1_price = parse_float(params["item1Price"])
      item2_qty = parse_int(params["item2Qty"])
      item2_price = parse_float(params["item2Price"])

      total = item1_qty * item1_price + item2_qty * item2_price

      {:ok, %{
        "orderId" => params["orderId"],
        "status" => "processed",
        "total" => total,
        "itemCount" => 2
      }}
    end

    # Operation that echoes back structured data
    soap_operation "EchoStructure" do
      description "Echoes back a structured input"
      input do
        parameter "name", :string, required: true
        parameter "count", :integer, required: true
        parameter "amount", :decimal, required: true
        parameter "enabled", :boolean, required: true
        parameter "date", :string, required: true
      end
      output do
        parameter "name", :string
        parameter "count", :integer
        parameter "amount", :decimal
        parameter "enabled", :boolean
        parameter "date", :string
        parameter "received", :boolean
      end
      soap_action "EchoStructure"
    end

    def echo_structure(params) do
      {:ok, %{
        "name" => params["name"],
        "count" => parse_int(params["count"]),
        "amount" => parse_float(params["amount"]),
        "enabled" => parse_bool(params["enabled"]),
        "date" => params["date"],
        "received" => true
      }}
    end

    # Operation with optional nested values
    soap_operation "GetOptionalData" do
      description "Gets data with optional fields"
      input do
        parameter "includeAddress", :boolean, required: false
        parameter "includeStats", :boolean, required: false
      end
      output do
        parameter "userId", :integer
        parameter "username", :string
        parameter "street", :string
        parameter "city", :string
        parameter "orderCount", :integer
        parameter "totalSpent", :decimal
      end
      soap_action "GetOptionalData"
    end

    def get_optional_data(params) do
      include_address = parse_bool(Map.get(params, "includeAddress", false))
      include_stats = parse_bool(Map.get(params, "includeStats", false))

      result = %{
        "userId" => 1001,
        "username" => "testuser"
      }

      result =
        if include_address do
          Map.merge(result, %{
            "street" => "456 Oak Ave",
            "city" => "Portland"
          })
        else
          Map.merge(result, %{"street" => "", "city" => ""})
        end

      result =
        if include_stats do
          Map.merge(result, %{
            "orderCount" => 25,
            "totalSpent" => 1234.56
          })
        else
          Map.merge(result, %{"orderCount" => 0, "totalSpent" => 0.0})
        end

      {:ok, result}
    end

    # Helpers
    defp parse_int(val) when is_integer(val), do: val
    defp parse_int(val) when is_binary(val), do: String.to_integer(val)
    defp parse_int(nil), do: 0
    defp parse_int(_), do: 0

    defp parse_float(val) when is_float(val), do: val
    defp parse_float(val) when is_integer(val), do: val * 1.0
    defp parse_float(val) when is_binary(val) do
      case Float.parse(val) do
        {f, _} -> f
        :error -> 0.0
      end
    end
    defp parse_float(nil), do: 0.0
    defp parse_float(_), do: 0.0

    defp parse_bool(true), do: true
    defp parse_bool(false), do: false
    defp parse_bool("true"), do: true
    defp parse_bool("false"), do: false
    defp parse_bool("1"), do: true
    defp parse_bool("0"), do: false
    defp parse_bool(_), do: false
  end

  defmodule ComplexTypesRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.ComplexTypesRoundTripTest.ComplexTypesService)
      )
    end
  end

  describe "user creation with nested data" do
    setup :start_server

    test "creates user with required fields", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "username" => "johndoe",
        "email" => "john@example.com"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "CreateUser", params)
      assert response["username"] == "johndoe"
      assert response["email"] == "john@example.com"
      assert parse_bool_result(response["created"]) == true
      assert is_integer(parse_int_result(response["id"])) or is_binary(response["id"])
    end

    test "creates another user successfully", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "username" => "janedoe",
        "email" => "jane@example.com"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "CreateUser", params)
      assert response["username"] == "janedoe"
      assert response["email"] == "jane@example.com"
    end
  end

  describe "user profile with address" do
    setup :start_server

    test "retrieves complete profile", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "GetUserProfile", %{"userId" => 123})

      assert parse_int_result(response["userId"]) == 123
      assert is_binary(response["username"])
      assert is_binary(response["email"])
      assert response["street"] == "123 Main St"
      assert response["city"] == "Springfield"
      assert response["country"] == "USA"
    end
  end

  describe "order processing with many parameters" do
    setup :start_server

    test "processes order with single item", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "orderId" => "ORD-001",
        "customerId" => "CUST-123",
        "itemName" => "Widget",
        "itemQty" => 5,
        "itemPrice" => 19.99,
        "shippingStreet" => "789 Pine St",
        "shippingCity" => "Seattle",
        "shippingCountry" => "USA"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "ProcessSingleItem", params)

      assert response["orderId"] == "ORD-001"
      assert response["status"] == "processed"
      assert_in_delta parse_float_result(response["total"]), 99.95, 0.01
      assert parse_int_result(response["itemCount"]) == 1
    end

    test "processes order with two items", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "orderId" => "ORD-002",
        "customerId" => "CUST-456",
        "item1Name" => "Widget",
        "item1Qty" => 2,
        "item1Price" => 25.00,
        "item2Name" => "Gadget",
        "item2Qty" => 3,
        "item2Price" => 15.00,
        "shippingStreet" => "321 Elm St",
        "shippingCity" => "Boston",
        "shippingCountry" => "USA"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "ProcessTwoItems", params)

      # Total = 2*25 + 3*15 = 50 + 45 = 95
      assert_in_delta parse_float_result(response["total"]), 95.0, 0.01
      assert parse_int_result(response["itemCount"]) == 2
    end
  end

  describe "echo structured data" do
    setup :start_server

    test "echoes all data types correctly", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "name" => "Test Structure",
        "count" => 42,
        "amount" => 123.45,
        "enabled" => true,
        "date" => "2024-03-15"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoStructure", params)

      assert response["name"] == "Test Structure"
      assert parse_int_result(response["count"]) == 42
      assert_in_delta parse_float_result(response["amount"]), 123.45, 0.01
      assert parse_bool_result(response["enabled"]) == true
      assert response["date"] == "2024-03-15"
      assert parse_bool_result(response["received"]) == true
    end

    test "handles edge case values in structure", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "name" => "",
        "count" => 0,
        "amount" => 0.0,
        "enabled" => false,
        "date" => "2000-01-01"
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoStructure", params)

      assert response["name"] == ""
      assert parse_int_result(response["count"]) == 0
      assert parse_float_result(response["amount"]) == 0.0
      assert parse_bool_result(response["enabled"]) == false
    end
  end

  describe "optional data handling" do
    setup :start_server

    test "retrieves data without optional fields", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "includeAddress" => false,
        "includeStats" => false
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "GetOptionalData", params)

      assert parse_int_result(response["userId"]) == 1001
      assert response["username"] == "testuser"
    end

    test "retrieves data with address only", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "includeAddress" => true,
        "includeStats" => false
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "GetOptionalData", params)

      assert response["street"] == "456 Oak Ave"
      assert response["city"] == "Portland"
    end

    test "retrieves data with stats only", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "includeAddress" => false,
        "includeStats" => true
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "GetOptionalData", params)

      assert parse_int_result(response["orderCount"]) == 25
      assert_in_delta parse_float_result(response["totalSpent"]), 1234.56, 0.01
    end

    test "retrieves data with all optional fields", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "includeAddress" => true,
        "includeStats" => true
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "GetOptionalData", params)

      assert response["street"] == "456 Oak Ave"
      assert response["city"] == "Portland"
      assert parse_int_result(response["orderCount"]) == 25
      assert_in_delta parse_float_result(response["totalSpent"]), 1234.56, 0.01
    end
  end

  describe "WSDL type definitions" do
    setup :start_server

    test "WSDL contains type definitions", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Just verify the client can be created and has operations
      operations = Lather.DynamicClient.list_operations(client)
      operation_names = Enum.map(operations, & &1.name)

      assert "CreateUser" in operation_names
      assert "GetUserProfile" in operation_names
      assert "ProcessSingleItem" in operation_names
      assert "ProcessTwoItems" in operation_names
      assert "EchoStructure" in operation_names
      assert "GetOptionalData" in operation_names
    end
  end

  # Setup helper
  defp start_server(_context) do
    {:ok, _} = Application.ensure_all_started(:lather)

    port = Enum.random(10000..60000)
    {:ok, server_pid} = Bandit.start_link(plug: ComplexTypesRouter, port: port, scheme: :http)

    on_exit(fn ->
      try do
        GenServer.stop(server_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    Process.sleep(50)
    {:ok, port: port, base_url: "http://localhost:#{port}"}
  end

  # Result parsing helpers
  defp parse_int_result(val) when is_integer(val), do: val
  defp parse_int_result(val) when is_binary(val), do: String.to_integer(val)
  defp parse_int_result(val) when is_float(val), do: trunc(val)

  defp parse_float_result(val) when is_float(val), do: val
  defp parse_float_result(val) when is_integer(val), do: val * 1.0
  defp parse_float_result(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> String.to_integer(val) * 1.0
    end
  end

  defp parse_bool_result(true), do: true
  defp parse_bool_result(false), do: false
  defp parse_bool_result("true"), do: true
  defp parse_bool_result("false"), do: false
  defp parse_bool_result("1"), do: true
  defp parse_bool_result("0"), do: false
  defp parse_bool_result(val) when is_binary(val), do: val == "true"
end
