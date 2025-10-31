defmodule Lather.DebugIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "Debug integration" do
    test "check what WSDL server returns" do
      port = get_free_port()
      wsdl_url = "http://localhost:#{port}/soap?wsdl"

      # Start test server
      server_pid = start_test_server(port)
      :timer.sleep(200)

      # Fetch WSDL manually
      {:ok, %{status: status, body: body}} = Finch.build(:get, wsdl_url)
      |> Finch.request(Lather.Finch)

      IO.puts("Status: #{status}")
      IO.puts("Body length: #{byte_size(body)}")
      IO.puts("First 200 chars:")
      IO.puts(String.slice(body, 0, 200))

      Process.exit(server_pid, :kill)
    end
  end

  # Simplified server for debugging
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
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        spawn(fn -> handle_connection(socket) end)
        accept_loop(listen_socket)
      {:error, _} ->
        :ok
    end
  end

  defp handle_connection(socket) do
    case parse_http_request(socket) do
      {:ok, conn} ->
        _response = case {conn.method, conn.request_path} do
          {"GET", "/soap"} ->
            case Map.get(conn.query_params || %{}, "wsdl") do
              val when val in [nil, "", "1", "true"] ->
                wsdl = """
<?xml version="1.0" encoding="UTF-8"?>
<definitions xmlns="http://schemas.xmlsoap.org/wsdl/" name="TestService">
  <types></types>
  <message name="echoRequest">
    <part name="message" type="xsd:string"/>
  </message>
  <message name="echoResponse">
    <part name="response" type="xsd:string"/>
  </message>
  <portType name="TestPortType">
    <operation name="echo">
      <input message="tns:echoRequest"/>
      <output message="tns:echoResponse"/>
    </operation>
  </portType>
  <binding name="TestBinding" type="tns:TestPortType">
    <soap:binding style="rpc" transport="http://schemas.xmlsoap.org/soap/http"/>
    <operation name="echo">
      <soap:operation soapAction="echo"/>
      <input><soap:body use="literal"/></input>
      <output><soap:body use="literal"/></output>
    </operation>
  </binding>
  <service name="TestService">
    <port name="TestPort" binding="tns:TestBinding">
      <soap:address location="http://localhost:8080/soap"/>
    </port>
  </service>
</definitions>
""" |> String.trim()

                http_response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/xml\r
                Content-Length: #{byte_size(wsdl)}\r
                Connection: close\r
                \r
                #{wsdl}
                """

                :gen_tcp.send(socket, http_response)
              _ ->
                :gen_tcp.send(socket, "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")
            end
          _ ->
            :gen_tcp.send(socket, "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")
        end
      {:error, _} ->
        :ok
    end

    :gen_tcp.close(socket)
  end

  defp parse_http_request(socket) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, {_http_request, method, {_abs_path, path}, _version}} ->
        _headers = parse_headers(socket, [])
        {path, query_params} = parse_query_string(path)

        conn = %{
          method: to_string(method),
          request_path: to_string(path),
          query_params: query_params
        }

        {:ok, conn}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, {:http_header, _, _name, _, _value}} ->
        parse_headers(socket, headers)
      {:ok, :http_eoh} ->
        headers
      _ ->
        headers
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

  defp get_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
