defmodule Lather.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Lather.DynamicClient

  describe "Full client-server integration" do
    setup do
      # Start a test HTTP server with our SOAP service
      port = get_free_port()
      base_url = "http://localhost:#{port}"
      wsdl_url = "#{base_url}/soap?wsdl"

      # Start the HTTP server in the background
      server_pid = start_test_server(port)

      # Give the server a moment to start
      :timer.sleep(200)

      on_exit(fn ->
        if Process.alive?(server_pid) do
          Process.exit(server_pid, :kill)
        end
      end)

      %{
        port: port,
        base_url: base_url,
        wsdl_url: wsdl_url,
        server_pid: server_pid
      }
    end

    @tag timeout: 10_000
    @tag :skip
    test "client can connect to server and make SOAP calls", %{wsdl_url: wsdl_url} do
      # Test 1: Create dynamic client from server's WSDL
      assert {:ok, client} = DynamicClient.new(wsdl_url, timeout: 5_000)

      # Test 2: List available operations
      operations = DynamicClient.list_operations(client)
      assert "echo" in operations
      assert "add_numbers" in operations

      # Test 3: Simple echo operation
      assert {:ok, response} = DynamicClient.call(client, "echo", %{
        "message" => "Hello, World!"
      })
      assert response["response"] == "Echo: Hello, World!"

      # Test 4: Math operation with numbers
      assert {:ok, response} = DynamicClient.call(client, "add_numbers", %{
        "a" => "10",
        "b" => "25"
      })
      assert response["result"] == "35"
    end

    @tag timeout: 10_000
    @tag :skip
    test "client handles server errors gracefully", %{wsdl_url: wsdl_url} do
      assert {:ok, client} = DynamicClient.new(wsdl_url, timeout: 5_000)

      # Test SOAP fault handling
      assert {:error, %{type: :soap_fault} = fault} = DynamicClient.call(client, "error_operation", %{})
      assert fault.fault_code == "Client"
      assert String.contains?(fault.fault_string, "Unknown operation")
    end

    @tag timeout: 10_000
    @tag :skip
    test "WSDL generation and parsing round-trip", %{wsdl_url: wsdl_url} do
      # Test that we can fetch and parse the WSDL
      {:ok, %{status: 200, body: wsdl_xml}} = Finch.build(:get, wsdl_url)
      |> Finch.request(Lather.Finch)

      # WSDL should be valid XML
      assert String.contains?(wsdl_xml, "<?xml")
      assert String.contains?(wsdl_xml, "<definitions")
      assert String.contains?(wsdl_xml, "TestIntegrationService")

      # Should contain our operations
      assert String.contains?(wsdl_xml, "echo")
      assert String.contains?(wsdl_xml, "add_numbers")

      # Test WSDL analysis
      {:ok, service_info} = Lather.Wsdl.Analyzer.load_and_analyze(wsdl_url)

      assert service_info.service_name == "TestIntegrationService"
      assert length(service_info.operations) >= 2

      operation_names = Enum.map(service_info.operations, & &1.name)
      assert "echo" in operation_names
      assert "add_numbers" in operation_names
    end
  end

  # Start a simple HTTP server for testing
  defp start_test_server(port) do
    spawn_link(fn ->
      {:ok, listen_socket} = :gen_tcp.listen(port, [
        :binary,
        packet: :http_bin,
        active: false,
        reuseaddr: true
      ])

      accept_loop(listen_socket)
    end)
  end

  defp accept_loop(listen_socket) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)

    spawn(fn ->
      handle_connection(socket)
    end)

    accept_loop(listen_socket)
  end

  defp handle_connection(socket) do
    case parse_http_request(socket) do
      {:ok, conn} ->
        response_conn = handle_soap_request(conn)
        send_http_response(socket, response_conn)
      {:error, _reason} ->
        :ok
    end

    :gen_tcp.close(socket)
  end

  # Handle SOAP requests
  defp handle_soap_request(conn) do
    case {conn.method, conn.request_path} do
      {"GET", "/soap"} ->
        # Check for WSDL request
        case Map.get(conn.query_params || %{}, "wsdl") do
          val when val in [nil, "", "1", "true"] ->
            # Generate WSDL
            wsdl_content = generate_test_wsdl(conn)

            %{conn | status: 200, resp_body: wsdl_content}
            |> put_resp_header("content-type", "text/xml")
          _ ->
            %{conn | status: 404, resp_body: "Not Found"}
        end

      {"POST", "/soap"} ->
        # Handle SOAP request
        handle_soap_operation(conn)

      _ ->
        %{conn | status: 404, resp_body: "Not Found"}
    end
  end

  # Handle SOAP operation calls
  defp handle_soap_operation(conn) do
    case parse_soap_request(conn.body) do
      {:ok, "echo", params} ->
        message = Map.get(params, "message", "")
        response = build_soap_response("echo", %{response: "Echo: #{message}"})

        %{conn | status: 200, resp_body: response}
        |> put_resp_header("content-type", "text/xml")

      {:ok, "add_numbers", params} ->
        a = Map.get(params, "a", "0") |> parse_int()
        b = Map.get(params, "b", "0") |> parse_int()
        result = a + b

        response = build_soap_response("add_numbers", %{result: result})

        %{conn | status: 200, resp_body: response}
        |> put_resp_header("content-type", "text/xml")

      {:ok, operation, _params} ->
        # Unknown operation - return SOAP fault
        fault = build_soap_fault("Client", "Unknown operation: #{operation}")

        %{conn | status: 500, resp_body: fault}
        |> put_resp_header("content-type", "text/xml")

      {:error, reason} ->
        fault = build_soap_fault("Client", "Parse error: #{reason}")

        %{conn | status: 400, resp_body: fault}
        |> put_resp_header("content-type", "text/xml")
    end
  end

  # Simple SOAP request parser
  defp parse_soap_request(body) when is_binary(body) do
    try do
      # Very basic XML parsing - just extract operation and simple params
      cond do
        String.contains?(body, "<echo>") or String.contains?(body, ":echo>") ->
          message = extract_xml_value(body, "message") || ""
          {:ok, "echo", %{"message" => message}}

        String.contains?(body, "<add_numbers>") or String.contains?(body, ":add_numbers>") ->
          a = extract_xml_value(body, "a") || "0"
          b = extract_xml_value(body, "b") || "0"
          {:ok, "add_numbers", %{"a" => a, "b" => b}}

        true ->
          # Try to extract any operation name
          case Regex.run(~r/<([^:>\s]+:)?(\w+)>/, body) do
            [_, _, operation] -> {:ok, operation, %{}}
            _ -> {:error, "No operation found"}
          end
      end
    rescue
      _ -> {:error, "Invalid XML"}
    end
  end

  # Extract simple XML values
  defp extract_xml_value(xml, tag) do
    patterns = [
      ~r/<#{tag}[^>]*>([^<]*)<\/#{tag}>/,
      ~r/<[^:]*:#{tag}[^>]*>([^<]*)<\/[^:]*:#{tag}>/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, xml) do
        [_, value] -> String.trim(value)
        _ -> nil
      end
    end)
  end

  # Build SOAP response
  defp build_soap_response(operation, data) do
    response_name = "#{operation}Response"

    content = Enum.map(data, fn {key, value} ->
      "<#{key}>#{value}</#{key}>"
    end) |> Enum.join("")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <#{response_name}>
          #{content}
        </#{response_name}>
      </soap:Body>
    </soap:Envelope>
    """
  end

  # Build SOAP fault
  defp build_soap_fault(fault_code, fault_string) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <soap:Fault>
          <faultcode>#{fault_code}</faultcode>
          <faultstring>#{fault_string}</faultstring>
        </soap:Fault>
      </soap:Body>
    </soap:Envelope>
    """
  end

  # Generate test WSDL
  defp generate_test_wsdl(conn) do
    base_url = "http://#{conn.host}:#{conn.port}/soap"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                 xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                 xmlns:tns="http://test.lather.com/"
                 xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                 targetNamespace="http://test.lather.com/"
                 name="TestIntegrationService">

      <types>
        <xsd:schema targetNamespace="http://test.lather.com/">
          <xsd:element name="echo">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="message" type="xsd:string"/>
              </xsd:sequence>
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="echoResponse">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="response" type="xsd:string"/>
              </xsd:sequence>
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="add_numbers">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="a" type="xsd:string"/>
                <xsd:element name="b" type="xsd:string"/>
              </xsd:sequence>
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="add_numbersResponse">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="result" type="xsd:string"/>
              </xsd:sequence>
            </xsd:complexType>
          </xsd:element>
        </xsd:schema>
      </types>

      <message name="echoRequest">
        <part name="parameters" element="tns:echo"/>
      </message>
      <message name="echoResponse">
        <part name="parameters" element="tns:echoResponse"/>
      </message>
      <message name="add_numbersRequest">
        <part name="parameters" element="tns:add_numbers"/>
      </message>
      <message name="add_numbersResponse">
        <part name="parameters" element="tns:add_numbersResponse"/>
      </message>

      <portType name="TestIntegrationServicePortType">
        <operation name="echo">
          <input message="tns:echoRequest"/>
          <output message="tns:echoResponse"/>
        </operation>
        <operation name="add_numbers">
          <input message="tns:add_numbersRequest"/>
          <output message="tns:add_numbersResponse"/>
        </operation>
      </portType>

      <binding name="TestIntegrationServiceBinding" type="tns:TestIntegrationServicePortType">
        <soap:binding style="document" transport="http://schemas.xmlsoap.org/soap/http"/>
        <operation name="echo">
          <soap:operation soapAction="echo"/>
          <input><soap:body use="literal"/></input>
          <output><soap:body use="literal"/></output>
        </operation>
        <operation name="add_numbers">
          <soap:operation soapAction="add_numbers"/>
          <input><soap:body use="literal"/></input>
          <output><soap:body use="literal"/></output>
        </operation>
      </binding>

      <service name="TestIntegrationService">
        <port name="TestIntegrationServicePort" binding="tns:TestIntegrationServiceBinding">
          <soap:address location="#{base_url}"/>
        </port>
      </service>
    </definitions>
    """ |> String.trim()
  end

  # Simple HTTP request parser
  defp parse_http_request(socket) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, {_http_request, method, {_abs_path, path}, _version}} ->
        # Parse headers and body
        headers = parse_headers(socket, [])
        body = parse_body(socket, headers)

        # Parse query params and host/port
        {path, query_params} = parse_query_string(path)
        {host, port} = extract_host_port(headers)

        conn = %{
          method: to_string(method),
          request_path: to_string(path),
          query_params: query_params,
          req_headers: headers,
          body: body,
          host: host,
          port: port,
          status: 200,
          resp_body: "",
          resp_headers: []
        }

        {:ok, conn}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, {:http_header, _, name, _, value}} ->
        header = {to_string(name) |> String.downcase(), to_string(value)}
        parse_headers(socket, [header | headers])
      {:ok, :http_eoh} ->
        Enum.reverse(headers)
      _ ->
        Enum.reverse(headers)
    end
  end

  defp parse_body(socket, headers) do
    content_length = case List.keyfind(headers, "content-length", 0) do
      {_, length_str} -> String.to_integer(length_str)
      nil -> 0
    end

    if content_length > 0 do
      :inet.setopts(socket, packet: :raw)
      {:ok, body} = :gen_tcp.recv(socket, content_length, 5000)
      body
    else
      ""
    end
  end

  defp extract_host_port(headers) do
    case List.keyfind(headers, "host", 0) do
      {_, host_header} ->
        case String.split(host_header, ":") do
          [host, port] -> {host, String.to_integer(port)}
          [host] -> {host, 80}
        end
      nil -> {"localhost", 80}
    end
  end

  defp parse_query_string(path) do
    case String.split(to_string(path), "?", parts: 2) do
      [path] -> {path, %{}}
      [path, query] ->
        params = query
        |> String.split("&")
        |> Enum.reduce(%{}, fn param, acc ->
          case String.split(param, "=", parts: 2) do
            [key] -> Map.put(acc, key, "")
            [key, value] -> Map.put(acc, key, URI.decode(value))
          end
        end)
        {path, params}
    end
  end

  defp send_http_response(socket, conn) do
    status_line = "HTTP/1.1 #{conn.status} #{status_text(conn.status)}\r\n"

    default_headers = [
      {"content-length", byte_size(conn.resp_body) |> to_string()},
      {"connection", "close"}
    ]

    headers = (conn.resp_headers ++ default_headers)
    |> Enum.map(fn {name, value} -> "#{name}: #{value}\r\n" end)
    |> Enum.join()

    response = status_line <> headers <> "\r\n" <> conn.resp_body
    :gen_tcp.send(socket, response)
  end

  defp put_resp_header(conn, name, value) do
    Map.update(conn, :resp_headers, [{name, value}], fn headers ->
      [{name, value} | headers]
    end)
  end

  defp status_text(200), do: "OK"
  defp status_text(404), do: "Not Found"
  defp status_text(500), do: "Internal Server Error"
  defp status_text(_), do: "Unknown"

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> 0
    end
  end
  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(_), do: 0

  # Get a free port for testing
  defp get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
