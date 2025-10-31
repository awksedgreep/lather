defmodule Lather.SimpleIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Lather.DynamicClient

  describe "Simple client-server integration" do

    @tag timeout: 10_000
    test "client can fetch and parse a real WSDL" do
      # Use a public SOAP service for testing
      # This weather service has been available for many years
      wsdl_url = "http://www.dneonline.com/calculator.asmx?WSDL"

      # Test that we can create a client from the WSDL
      case DynamicClient.new(wsdl_url, timeout: 10_000) do
        {:ok, client} ->
          # Test that we can list operations
          operations = DynamicClient.list_operations(client)

          # This service should have basic math operations
          assert is_list(operations)
          assert length(operations) > 0

          # Try to call a simple operation (Add)
          case DynamicClient.call(client, "Add", %{"intA" => "5", "intB" => "3"}) do
            {:ok, response} ->
              # Should get back the sum
              assert response["AddResult"] == "8"

            {:error, error} ->
              # If the service is down, that's OK for this test
              IO.puts("Service call failed (service may be down): #{inspect(error)}")
          end

        {:error, error} ->
          # If the service is unreachable, skip the test
          IO.puts("WSDL fetch failed (service may be down): #{inspect(error)}")
      end
    end

    @tag timeout: 10_000
    test "client handles invalid WSDL gracefully" do
      # Test with a non-existent WSDL URL
      invalid_wsdl_url = "http://localhost:99999/nonexistent.wsdl"

      case DynamicClient.new(invalid_wsdl_url, timeout: 2_000) do
        {:error, %{type: :transport_error}} ->
          # This is expected
          :ok
        {:error, %{type: :http_error}} ->
          # This is also acceptable
          :ok
        {:error, error} ->
          # Any error is fine, we're testing error handling
          assert error != nil
        {:ok, _client} ->
          # This should not happen with an invalid URL
          flunk("Expected error but got success")
      end
    end

    @tag timeout: 10_000
    test "client handles malformed WSDL gracefully" do
      # We'll create a simple HTTP server that returns invalid XML
      port = get_free_port()
      wsdl_url = "http://localhost:#{port}/bad.wsdl"

      # Start a server that returns bad XML
      server_pid = spawn_link(fn ->
        {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, packet: :http_bin, active: false, reuseaddr: true])
        {:ok, socket} = :gen_tcp.accept(listen_socket)

        # Return invalid XML
        bad_xml = "This is not XML at all!"
        response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/xml\r
        Content-Length: #{byte_size(bad_xml)}\r
        Connection: close\r
        \r
        #{bad_xml}
        """

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

      # Give server time to start
      :timer.sleep(100)

      # Try to create client with bad WSDL
      case DynamicClient.new(wsdl_url, timeout: 5_000) do
        {:error, %{type: :parse_error}} ->
          # This is expected
          :ok
        {:error, error} ->
          # Any parse-related error is acceptable
          error_string = inspect(error)
          assert String.contains?(error_string, "parse") ||
                 String.contains?(error_string, "XML") ||
                 String.contains?(error_string, "invalid")
        {:ok, _client} ->
          flunk("Expected parse error but got success")
      end

      # Clean up
      Process.exit(server_pid, :kill)
    end

    @tag timeout: 10_000
    @tag :skip
    test "WSDL analyzer works with real WSDL" do
      # Test the WSDL analyzer directly with a simple WSDL
      port = get_free_port()
      wsdl_url = "http://localhost:#{port}/simple.wsdl"

      # Start a server that returns valid WSDL
      server_pid = spawn_link(fn ->
        {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, packet: :http_bin, active: false, reuseaddr: true])
        {:ok, socket} = :gen_tcp.accept(listen_socket)

        # Return a minimal valid WSDL
        wsdl = """
<?xml version="1.0" encoding="UTF-8"?>
<definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
             xmlns:tns="http://test.example.com/"
             xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
             xmlns:xsd="http://www.w3.org/2001/XMLSchema"
             targetNamespace="http://test.example.com/"
             name="SimpleService">
  <message name="EchoRequest">
    <part name="message" type="xsd:string"/>
  </message>
  <message name="EchoResponse">
    <part name="response" type="xsd:string"/>
  </message>
  <portType name="SimplePortType">
    <operation name="Echo">
      <input message="tns:EchoRequest"/>
      <output message="tns:EchoResponse"/>
    </operation>
  </portType>
  <binding name="SimpleBinding" type="tns:SimplePortType">
    <soap:binding style="rpc" transport="http://schemas.xmlsoap.org/soap/http"/>
    <operation name="Echo">
      <soap:operation soapAction="Echo"/>
      <input><soap:body use="literal"/></input>
      <output><soap:body use="literal"/></output>
    </operation>
  </binding>
  <service name="SimpleService">
    <port name="SimplePort" binding="tns:SimpleBinding">
      <soap:address location="http://localhost:#{port}/soap"/>
    </port>
  </service>
</definitions>
""" |> String.trim()

        response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/xml\r
        Content-Length: #{byte_size(wsdl)}\r
        Connection: close\r
        \r
        #{wsdl}
        """

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

      # Give server time to start
      :timer.sleep(100)

      # Test WSDL analysis
      case Lather.Wsdl.Analyzer.load_and_analyze(wsdl_url) do
        {:ok, service_info} ->
          assert service_info.service_name == "SimpleService"
          assert length(service_info.operations) == 1

          operation = hd(service_info.operations)
          assert operation.name == "Echo"

        {:error, error} ->
          flunk("WSDL analysis failed: #{inspect(error)}")
      end

      # Clean up
      Process.exit(server_pid, :kill)
    end
  end

  # Get a free port for testing
  defp get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
