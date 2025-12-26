defmodule Lather.Integration.RoundTripTest do
  @moduledoc """
  End-to-end integration tests that verify the full client-server round trip.

  These tests catch bugs that unit tests miss - specifically issues at integration
  boundaries where component outputs must match other components' input expectations.
  """
  use ExUnit.Case, async: false

  # These tests require starting actual HTTP servers
  @moduletag :integration

  # Define the test service module at compile time to avoid redefinition warnings
  defmodule TestCalculatorService do
    use Lather.Server

    @namespace "http://test.example.com/calculator"
    @service_name "TestCalculatorService"

    soap_operation "Add" do
      description "Adds two numbers"
      input do
        parameter "a", :decimal, required: true
        parameter "b", :decimal, required: true
      end
      output do
        parameter "result", :decimal
      end
      soap_action "Add"
    end

    soap_operation "Subtract" do
      description "Subtracts b from a"
      input do
        parameter "a", :decimal, required: true
        parameter "b", :decimal, required: true
      end
      output do
        parameter "result", :decimal
      end
      soap_action "Subtract"
    end

    soap_operation "Echo" do
      description "Echoes the input message"
      input do
        parameter "message", :string, required: true
      end
      output do
        parameter "echo", :string
      end
      soap_action "Echo"
    end

    soap_operation "Divide" do
      description "Divides a by b"
      input do
        parameter "dividend", :decimal, required: true
        parameter "divisor", :decimal, required: true
      end
      output do
        parameter "quotient", :decimal
      end
      soap_action "Divide"
    end

    def add(%{"a" => a, "b" => b}) do
      {:ok, %{"result" => parse_number(a) + parse_number(b)}}
    end

    def subtract(%{"a" => a, "b" => b}) do
      {:ok, %{"result" => parse_number(a) - parse_number(b)}}
    end

    def echo(%{"message" => msg}) do
      {:ok, %{"echo" => msg}}
    end

    def divide(%{"dividend" => dividend, "divisor" => divisor}) do
      d = parse_number(divisor)

      if d == 0 do
        Lather.Server.soap_fault("Client", "Division by zero")
      else
        {:ok, %{"quotient" => parse_number(dividend) / d}}
      end
    end

    defp parse_number(val) when is_number(val), do: val

    defp parse_number(val) when is_binary(val) do
      case Float.parse(val) do
        {num, _} -> num
        :error -> String.to_integer(val)
      end
    end
  end

  # Define the router at compile time
  defmodule TestRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.RoundTripTest.TestCalculatorService)
      )
    end
  end

  describe "full client-server round trip" do
    setup do
      # Start the Lather application (for Finch)
      {:ok, _} = Application.ensure_all_started(:lather)

      # Start the server on a random available port
      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: TestRouter, port: port, scheme: :http)

      on_exit(fn ->
        # Cleanup server - use GenServer.stop with a timeout
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      # Wait for server to be ready
      Process.sleep(50)

      {:ok, port: port, base_url: "http://localhost:#{port}"}
    end

    test "client can connect via WSDL and call Add operation", %{base_url: base_url} do
      wsdl_url = "#{base_url}/soap?wsdl"

      # Connect client using the server-generated WSDL
      assert {:ok, client} = Lather.DynamicClient.new(wsdl_url, timeout: 5000)

      # Verify operations are discovered
      operations = Lather.DynamicClient.list_operations(client)
      operation_names = Enum.map(operations, & &1.name)
      assert "Add" in operation_names

      # Make the call
      assert {:ok, response} = Lather.DynamicClient.call(client, "Add", %{"a" => 10, "b" => 5})

      # Verify we get the actual result, not wrapped in extra keys
      assert is_map(response)
      assert Map.has_key?(response, "result")
      assert parse_result(response["result"]) == 15.0
    end

    test "client can call Subtract operation", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Subtract", %{"a" => 100, "b" => 37})

      assert Map.has_key?(response, "result")
      result = parse_result(response["result"])
      assert result == 63.0
    end

    test "client can call Echo operation with string", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Echo", %{"message" => "Hello World"})

      assert Map.has_key?(response, "echo")
      assert response["echo"] == "Hello World"
    end

    test "client can call Divide operation", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Divide", %{"dividend" => 100, "divisor" => 4})

      assert Map.has_key?(response, "quotient")
      result = parse_result(response["quotient"])
      assert result == 25.0
    end

    test "client receives SOAP fault for division by zero", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      assert {:error, error} =
               Lather.DynamicClient.call(client, "Divide", %{"dividend" => 100, "divisor" => 0})

      # Should be a SOAP fault
      assert error != nil
    end

    test "client can make multiple sequential calls", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Make several calls in sequence
      assert {:ok, r1} = Lather.DynamicClient.call(client, "Add", %{"a" => 1, "b" => 2})
      assert {:ok, r2} = Lather.DynamicClient.call(client, "Add", %{"a" => 3, "b" => 4})
      assert {:ok, r3} = Lather.DynamicClient.call(client, "Subtract", %{"a" => 10, "b" => 3})

      assert parse_result(r1["result"]) == 3.0
      assert parse_result(r2["result"]) == 7.0
      assert parse_result(r3["result"]) == 7.0
    end

    test "client can make concurrent calls", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Make concurrent calls
      tasks = [
        Task.async(fn -> Lather.DynamicClient.call(client, "Add", %{"a" => 1, "b" => 1}) end),
        Task.async(fn -> Lather.DynamicClient.call(client, "Add", %{"a" => 2, "b" => 2}) end),
        Task.async(fn -> Lather.DynamicClient.call(client, "Add", %{"a" => 3, "b" => 3}) end),
        Task.async(fn ->
          Lather.DynamicClient.call(client, "Subtract", %{"a" => 10, "b" => 5})
        end)
      ]

      results = Task.await_many(tasks, 10_000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end

    test "response contains only expected keys, not wrapper elements", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      {:ok, response} = Lather.DynamicClient.call(client, "Add", %{"a" => 5, "b" => 3})

      # Response should be flat with just the output parameters
      # NOT wrapped like %{"AddResponse" => %{"result" => ...}}
      refute Map.has_key?(response, "AddResponse")
      refute Map.has_key?(response, "Response")
      refute Map.has_key?(response, "soap:Body")
      refute Map.has_key?(response, "Body")

      # Should have the actual result key directly
      assert Map.has_key?(response, "result")
    end
  end

  defp parse_result(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> value
    end
  end

  defp parse_result(value) when is_number(value), do: value * 1.0
  defp parse_result(value), do: value
end
