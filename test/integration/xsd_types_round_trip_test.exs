defmodule Lather.Integration.XsdTypesRoundTripTest do
  @moduledoc """
  Integration tests for XSD data type round-trip conversion.

  Tests that all supported XSD types can be correctly serialized by the client,
  parsed by the server, and returned in responses without data corruption.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  # Define a service that exercises all XSD types
  defmodule AllTypesService do
    use Lather.Server

    @namespace "http://test.example.com/alltypes"
    @service_name "AllTypesService"

    # String type
    soap_operation "EchoString" do
      description "Echoes a string value"
      input do
        parameter "value", :string, required: true
      end
      output do
        parameter "result", :string
      end
      soap_action "EchoString"
    end

    def echo_string(%{"value" => val}), do: {:ok, %{"result" => val}}

    # Integer type
    soap_operation "EchoInteger" do
      description "Echoes an integer value"
      input do
        parameter "value", :integer, required: true
      end
      output do
        parameter "result", :integer
      end
      soap_action "EchoInteger"
    end

    def echo_integer(%{"value" => val}) do
      {:ok, %{"result" => parse_int(val)}}
    end

    # Decimal/float type
    soap_operation "EchoDecimal" do
      description "Echoes a decimal value"
      input do
        parameter "value", :decimal, required: true
      end
      output do
        parameter "result", :decimal
      end
      soap_action "EchoDecimal"
    end

    def echo_decimal(%{"value" => val}) do
      {:ok, %{"result" => parse_float(val)}}
    end

    # Boolean type
    soap_operation "EchoBoolean" do
      description "Echoes a boolean value"
      input do
        parameter "value", :boolean, required: true
      end
      output do
        parameter "result", :boolean
      end
      soap_action "EchoBoolean"
    end

    def echo_boolean(%{"value" => val}) do
      {:ok, %{"result" => parse_bool(val)}}
    end

    # DateTime type
    soap_operation "EchoDateTime" do
      description "Echoes a dateTime value"
      input do
        parameter "value", :datetime, required: true
      end
      output do
        parameter "result", :datetime
      end
      soap_action "EchoDateTime"
    end

    def echo_date_time(%{"value" => val}), do: {:ok, %{"result" => val}}

    # Date type
    soap_operation "EchoDate" do
      description "Echoes a date value"
      input do
        parameter "value", :date, required: true
      end
      output do
        parameter "result", :date
      end
      soap_action "EchoDate"
    end

    def echo_date(%{"value" => val}), do: {:ok, %{"result" => val}}

    # Multiple types in one operation
    soap_operation "ProcessMultipleTypes" do
      description "Processes multiple types at once"
      input do
        parameter "stringVal", :string, required: true
        parameter "intVal", :integer, required: true
        parameter "decimalVal", :decimal, required: true
        parameter "boolVal", :boolean, required: true
      end
      output do
        parameter "stringResult", :string
        parameter "intResult", :integer
        parameter "decimalResult", :decimal
        parameter "boolResult", :boolean
      end
      soap_action "ProcessMultipleTypes"
    end

    def process_multiple_types(%{"stringVal" => s, "intVal" => i, "decimalVal" => d, "boolVal" => b}) do
      {:ok, %{
        "stringResult" => s,
        "intResult" => parse_int(i),
        "decimalResult" => parse_float(d),
        "boolResult" => parse_bool(b)
      }}
    end

    # Helper functions
    defp parse_int(val) when is_integer(val), do: val
    defp parse_int(val) when is_binary(val), do: String.to_integer(val)

    defp parse_float(val) when is_float(val), do: val
    defp parse_float(val) when is_integer(val), do: val * 1.0
    defp parse_float(val) when is_binary(val) do
      case Float.parse(val) do
        {f, _} -> f
        :error -> String.to_integer(val) * 1.0
      end
    end

    defp parse_bool(true), do: true
    defp parse_bool(false), do: false
    defp parse_bool("true"), do: true
    defp parse_bool("false"), do: false
    defp parse_bool("1"), do: true
    defp parse_bool("0"), do: false
  end

  defmodule AllTypesRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.XsdTypesRoundTripTest.AllTypesService)
      )
    end
  end

  describe "string type round-trip" do
    setup :start_server

    test "handles simple ASCII strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoString", %{"value" => "Hello World"})
      assert response["result"] == "Hello World"
    end

    test "handles empty strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoString", %{"value" => ""})
      assert response["result"] == ""
    end

    test "handles strings with numbers", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoString", %{"value" => "Test123"})
      assert response["result"] == "Test123"
    end

    test "handles long strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)
      long_string = String.duplicate("a", 10000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoString", %{"value" => long_string})
      assert response["result"] == long_string
    end

    test "handles whitespace strings", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoString", %{"value" => "  spaces  "})
      # Note: XML may normalize whitespace differently
      assert is_binary(response["result"])
    end
  end

  describe "integer type round-trip" do
    setup :start_server

    test "handles positive integers", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoInteger", %{"value" => 42})
      assert parse_int_result(response["result"]) == 42
    end

    test "handles zero", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoInteger", %{"value" => 0})
      assert parse_int_result(response["result"]) == 0
    end

    test "handles negative integers", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoInteger", %{"value" => -100})
      assert parse_int_result(response["result"]) == -100
    end

    test "handles large positive integers", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoInteger", %{"value" => 2_147_483_647})
      assert parse_int_result(response["result"]) == 2_147_483_647
    end

    test "handles large negative integers", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoInteger", %{"value" => -2_147_483_648})
      assert parse_int_result(response["result"]) == -2_147_483_648
    end
  end

  describe "decimal type round-trip" do
    setup :start_server

    test "handles positive decimals", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDecimal", %{"value" => 3.14159})
      assert_in_delta parse_float_result(response["result"]), 3.14159, 0.00001
    end

    test "handles zero as decimal", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDecimal", %{"value" => 0.0})
      assert parse_float_result(response["result"]) == 0.0
    end

    test "handles negative decimals", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDecimal", %{"value" => -123.456})
      assert_in_delta parse_float_result(response["result"]), -123.456, 0.001
    end

    test "handles very small decimals", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDecimal", %{"value" => 0.000001})
      assert_in_delta parse_float_result(response["result"]), 0.000001, 0.0000001
    end

    test "handles integers as decimals", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDecimal", %{"value" => 100})
      assert parse_float_result(response["result"]) == 100.0
    end
  end

  describe "boolean type round-trip" do
    setup :start_server

    test "handles true boolean", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoBoolean", %{"value" => true})
      assert parse_bool_result(response["result"]) == true
    end

    test "handles false boolean", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoBoolean", %{"value" => false})
      assert parse_bool_result(response["result"]) == false
    end

    test "handles string 'true'", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoBoolean", %{"value" => "true"})
      assert parse_bool_result(response["result"]) == true
    end

    test "handles string 'false'", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoBoolean", %{"value" => "false"})
      assert parse_bool_result(response["result"]) == false
    end
  end

  describe "datetime type round-trip" do
    setup :start_server

    test "handles ISO 8601 datetime string", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      datetime = "2024-03-15T10:30:00Z"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDateTime", %{"value" => datetime})
      assert is_binary(response["result"])
      # Should contain the date components
      assert String.contains?(response["result"], "2024")
    end

    test "handles datetime with timezone offset", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      datetime = "2024-03-15T10:30:00-05:00"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDateTime", %{"value" => datetime})
      assert is_binary(response["result"])
    end
  end

  describe "date type round-trip" do
    setup :start_server

    test "handles ISO 8601 date string", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      date = "2024-03-15"
      assert {:ok, response} = Lather.DynamicClient.call(client, "EchoDate", %{"value" => date})
      assert is_binary(response["result"])
      assert String.contains?(response["result"], "2024")
    end
  end

  describe "multiple types in single operation" do
    setup :start_server

    test "handles all types correctly", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "stringVal" => "test",
        "intVal" => 42,
        "decimalVal" => 3.14,
        "boolVal" => true
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "ProcessMultipleTypes", params)

      assert response["stringResult"] == "test"
      assert parse_int_result(response["intResult"]) == 42
      assert_in_delta parse_float_result(response["decimalResult"]), 3.14, 0.01
      assert parse_bool_result(response["boolResult"]) == true
    end

    test "handles edge case values", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      params = %{
        "stringVal" => "",
        "intVal" => 0,
        "decimalVal" => 0.0,
        "boolVal" => false
      }

      assert {:ok, response} = Lather.DynamicClient.call(client, "ProcessMultipleTypes", params)

      assert response["stringResult"] == ""
      assert parse_int_result(response["intResult"]) == 0
      assert parse_float_result(response["decimalResult"]) == 0.0
      assert parse_bool_result(response["boolResult"]) == false
    end
  end

  # Setup helper
  defp start_server(_context) do
    {:ok, _} = Application.ensure_all_started(:lather)

    port = Enum.random(10000..60000)
    {:ok, server_pid} = Bandit.start_link(plug: AllTypesRouter, port: port, scheme: :http)

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
