defmodule Lather.Integration.Soap12RoundTripTest do
  @moduledoc """
  End-to-end integration tests for SOAP 1.2 client-server round trip.

  These tests verify that a client can:
  1. Connect to a SOAP server via WSDL
  2. Make calls using explicit SOAP 1.2 protocol
  3. Send SOAP 1.2 formatted requests with correct namespace
  4. Receive responses with proper parsing

  This catches integration boundary issues that unit tests miss.
  """
  use ExUnit.Case, async: false

  # These tests require starting actual HTTP servers
  @moduletag :integration

  @soap12_namespace "http://www.w3.org/2003/05/soap-envelope"
  @soap11_namespace "http://schemas.xmlsoap.org/soap/envelope/"

  # Define the test service module at compile time to avoid redefinition warnings
  defmodule TestSoap12Service do
    use Lather.Server

    @namespace "http://test.example.com/soap12"
    @service_name "TestSoap12Service"

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

  # Define the router using standard Plug (same pattern as original round_trip_test)
  defmodule TestSoap12Router do
    use Plug.Router
    plug :match
    plug :dispatch

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.Soap12RoundTripTest.TestSoap12Service)
      )
    end
  end

  describe "SOAP 1.2 client-server round trip" do
    setup do
      # Start the Lather application (for Finch)
      {:ok, _} = Application.ensure_all_started(:lather)

      # Start the server on a random available port
      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: TestSoap12Router, port: port, scheme: :http)

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

    test "client can connect via WSDL and call Add operation with SOAP 1.2", %{base_url: base_url} do
      wsdl_url = "#{base_url}/soap?wsdl"

      # Connect client and explicitly set SOAP 1.2 version
      assert {:ok, client} = Lather.DynamicClient.new(wsdl_url, timeout: 5000, soap_version: :v1_2)

      # Verify operations are discovered
      operations = Lather.DynamicClient.list_operations(client)
      operation_names = Enum.map(operations, & &1.name)
      assert "Add" in operation_names

      # Make the call
      assert {:ok, response} = Lather.DynamicClient.call(client, "Add", %{"a" => 10, "b" => 5})

      # Verify we get the actual result
      assert is_map(response)
      assert Map.has_key?(response, "result")
      assert parse_result(response["result"]) == 15.0
    end

    test "client can call Subtract operation with SOAP 1.2", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000, soap_version: :v1_2)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Subtract", %{"a" => 100, "b" => 37})

      assert Map.has_key?(response, "result")
      result = parse_result(response["result"])
      assert result == 63.0
    end

    test "client can call Echo operation with SOAP 1.2", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000, soap_version: :v1_2)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Echo", %{"message" => "Hello SOAP 1.2"})

      assert Map.has_key?(response, "echo")
      assert response["echo"] == "Hello SOAP 1.2"
    end

    test "client can call Divide operation with SOAP 1.2", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000, soap_version: :v1_2)

      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Divide", %{"dividend" => 100, "divisor" => 4})

      assert Map.has_key?(response, "quotient")
      result = parse_result(response["quotient"])
      assert result == 25.0
    end

    test "client receives fault for division by zero with SOAP 1.2", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000, soap_version: :v1_2)

      assert {:error, error} =
               Lather.DynamicClient.call(client, "Divide", %{"dividend" => 100, "divisor" => 0})

      # Should receive a SOAP fault
      assert error != nil
    end

    test "SOAP 1.2 request envelope contains correct namespace" do
      # Build a SOAP 1.2 envelope and verify namespace
      {:ok, envelope} =
        Lather.Soap.Envelope.build(
          :TestOperation,
          %{param: "value"},
          version: :v1_2,
          namespace: "http://test.example.com/soap12"
        )

      # Verify SOAP 1.2 namespace is used
      assert String.contains?(envelope, @soap12_namespace)
      refute String.contains?(envelope, @soap11_namespace)

      # Verify envelope structure
      assert String.contains?(envelope, "<soap:Envelope")
      assert String.contains?(envelope, "<soap:Body")
    end

    test "SOAP 1.2 HTTP headers are correct" do
      # Verify SOAP 1.2 headers format
      headers =
        Lather.Http.Transport.build_headers(
          soap_version: :v1_2,
          soap_action: "http://test.example.com/TestAction"
        )

      # SOAP 1.2 uses application/soap+xml content type
      content_type_header = Enum.find(headers, fn {name, _} -> name == "content-type" end)
      assert content_type_header != nil
      {_, content_type} = content_type_header

      assert String.contains?(content_type, "application/soap+xml")
      # SOAP 1.2 embeds action in Content-Type instead of separate header
      assert String.contains?(content_type, "action=")

      # SOAP 1.2 should NOT have separate SOAPAction header
      soap_action_header =
        Enum.find(headers, fn {name, _} ->
          String.downcase(name) == "soapaction"
        end)

      assert soap_action_header == nil
    end

    test "client can make multiple sequential calls with SOAP 1.2", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000, soap_version: :v1_2)

      # Make several calls in sequence
      assert {:ok, r1} = Lather.DynamicClient.call(client, "Add", %{"a" => 1, "b" => 2})
      assert {:ok, r2} = Lather.DynamicClient.call(client, "Add", %{"a" => 3, "b" => 4})
      assert {:ok, r3} = Lather.DynamicClient.call(client, "Subtract", %{"a" => 10, "b" => 3})

      assert parse_result(r1["result"]) == 3.0
      assert parse_result(r2["result"]) == 7.0
      assert parse_result(r3["result"]) == 7.0
    end

    test "client can make concurrent calls with SOAP 1.2", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000, soap_version: :v1_2)

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
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000, soap_version: :v1_2)

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

  describe "SOAP version comparison" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: TestSoap12Router, port: port, scheme: :http)

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

    test "SOAP 1.1 and SOAP 1.2 envelopes have different namespaces" do
      params = %{test_param: "value"}

      {:ok, soap_1_1_envelope} = Lather.Soap.Envelope.build(:TestOp, params, version: :v1_1)
      {:ok, soap_1_2_envelope} = Lather.Soap.Envelope.build(:TestOp, params, version: :v1_2)

      # SOAP 1.1 should use the old namespace
      assert String.contains?(soap_1_1_envelope, @soap11_namespace)

      # SOAP 1.2 should use the new namespace
      assert String.contains?(soap_1_2_envelope, @soap12_namespace)

      # They should NOT contain each other's namespaces
      refute String.contains?(soap_1_1_envelope, @soap12_namespace)
      refute String.contains?(soap_1_2_envelope, @soap11_namespace)

      # Both should contain the same operation and parameters
      assert String.contains?(soap_1_1_envelope, "<TestOp>")
      assert String.contains?(soap_1_2_envelope, "<TestOp>")
      assert String.contains?(soap_1_1_envelope, "<test_param>value</test_param>")
      assert String.contains?(soap_1_2_envelope, "<test_param>value</test_param>")
    end

    test "SOAP 1.1 and SOAP 1.2 have different HTTP headers" do
      soap_action = "http://example.com/TestAction"

      soap_1_1_headers = Lather.Http.Transport.build_headers(soap_version: :v1_1, soap_action: soap_action)
      soap_1_2_headers = Lather.Http.Transport.build_headers(soap_version: :v1_2, soap_action: soap_action)

      # SOAP 1.1 should have separate SOAPAction header
      soap_1_1_soap_action =
        Enum.find(soap_1_1_headers, fn {name, _} ->
          String.downcase(name) == "soapaction"
        end)

      assert soap_1_1_soap_action != nil

      # SOAP 1.1 should use text/xml content type
      soap_1_1_content_type =
        Enum.find(soap_1_1_headers, fn {name, _} -> name == "content-type" end)

      {_, soap_1_1_ct_value} = soap_1_1_content_type
      assert String.contains?(soap_1_1_ct_value, "text/xml")

      # SOAP 1.2 should NOT have SOAPAction header
      soap_1_2_soap_action =
        Enum.find(soap_1_2_headers, fn {name, _} ->
          String.downcase(name) == "soapaction"
        end)

      assert soap_1_2_soap_action == nil

      # SOAP 1.2 should embed action in Content-Type
      soap_1_2_content_type =
        Enum.find(soap_1_2_headers, fn {name, _} -> name == "content-type" end)

      {_, soap_1_2_ct_value} = soap_1_2_content_type
      assert String.contains?(soap_1_2_ct_value, "application/soap+xml")
      assert String.contains?(soap_1_2_ct_value, "action=")
    end

    test "same operation produces same results with both SOAP versions", %{base_url: base_url} do
      wsdl_url = "#{base_url}/soap?wsdl"

      # Create clients for both versions
      {:ok, client_v11} = Lather.DynamicClient.new(wsdl_url, timeout: 5000, soap_version: :v1_1)
      {:ok, client_v12} = Lather.DynamicClient.new(wsdl_url, timeout: 5000, soap_version: :v1_2)

      # Call the same operation with both
      {:ok, response_v11} = Lather.DynamicClient.call(client_v11, "Add", %{"a" => 25, "b" => 17})
      {:ok, response_v12} = Lather.DynamicClient.call(client_v12, "Add", %{"a" => 25, "b" => 17})

      # Both should return the same result
      assert parse_result(response_v11["result"]) == 42.0
      assert parse_result(response_v12["result"]) == 42.0
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
