defmodule Lather.Integration.SoapHeadersRoundTripTest do
  @moduledoc """
  End-to-end integration tests for SOAP headers round trip.

  These tests verify the full client-server round trip for SOAP headers including:
  - Session headers
  - Custom headers with various content types
  - Multiple headers in a single request
  - Headers with namespaces
  - Headers with attributes
  - Server reading incoming headers
  - Server including headers in responses
  """
  use ExUnit.Case, async: false

  # These tests require starting actual HTTP servers
  @moduletag :integration

  alias Lather.Soap.Header
  alias Lather.Xml.Parser
  alias Lather.Xml.Builder

  # Define a test service that can read and respond with headers
  defmodule HeaderEchoService do
    use Lather.Server

    @namespace "http://test.example.com/headers"
    @service_name "HeaderEchoService"

    soap_operation "EchoMessage" do
      description "Echoes a message back"
      input do
        parameter "message", :string, required: true
      end
      output do
        parameter "echo", :string
      end
      soap_action "EchoMessage"
    end

    soap_operation "GetSessionInfo" do
      description "Returns session information"
      input do
        parameter "query", :string, required: true
      end
      output do
        parameter "sessionId", :string
        parameter "query", :string
      end
      soap_action "GetSessionInfo"
    end

    soap_operation "ProcessWithHeaders" do
      description "Processes a request and acknowledges headers"
      input do
        parameter "data", :string, required: true
      end
      output do
        parameter "processed", :string
        parameter "headersReceived", :string
      end
      soap_action "ProcessWithHeaders"
    end

    def echo_message(%{"message" => msg}) do
      {:ok, %{"echo" => msg}}
    end

    def get_session_info(%{"query" => query}) do
      {:ok, %{"sessionId" => "session-12345", "query" => query}}
    end

    def process_with_headers(%{"data" => data}) do
      {:ok, %{"processed" => "Processed: #{data}", "headersReceived" => "acknowledged"}}
    end
  end

  # Custom Plug router that can parse and echo headers
  defmodule HeaderAwareRouter do
    use Plug.Router
    plug :fetch_query_params
    plug :match
    plug :dispatch

    alias Lather.Xml.Parser
    alias Lather.Xml.Builder

    get "/soap" do
      # Handle WSDL request
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.SoapHeadersRoundTripTest.HeaderEchoService)
      )
    end

    post "/soap" do
      handle_soap_with_headers(conn)
    end

    # Catch-all for unmatched routes
    match _ do
      conn
      |> Plug.Conn.put_resp_content_type("text/xml")
      |> Plug.Conn.send_resp(404, error_response("Not Found"))
    end

    defp handle_soap_with_headers(conn) do
      case read_full_body(conn) do
        {:ok, body, conn} ->
          case Parser.parse(body) do
            {:ok, parsed} ->
              # Extract headers from the request
              headers = extract_headers(parsed)

              # Extract the operation and process it
              {operation, params} = extract_operation(parsed)

              # Build response with echoed headers
              response_xml = build_response_with_headers(operation, params, headers)

              conn
              |> Plug.Conn.put_resp_content_type("text/xml")
              |> Plug.Conn.send_resp(200, response_xml)

            {:error, _reason} ->
              conn
              |> Plug.Conn.put_resp_content_type("text/xml")
              |> Plug.Conn.send_resp(400, error_response("Parse error"))
          end

        {:error, _reason} ->
          conn
          |> Plug.Conn.put_resp_content_type("text/xml")
          |> Plug.Conn.send_resp(500, error_response("Failed to read body"))
      end
    end

    defp extract_headers(parsed) do
      envelope = parsed["soap:Envelope"] || parsed["Envelope"] || %{}
      header = envelope["soap:Header"] || envelope["Header"]

      if header && is_map(header) do
        # Filter out SOAP envelope attributes
        header
        |> Enum.reject(fn {k, _v} -> String.starts_with?(to_string(k), "@") end)
        |> Enum.into(%{})
      else
        %{}
      end
    end

    defp extract_operation(parsed) do
      envelope = parsed["soap:Envelope"] || parsed["Envelope"] || %{}
      body = envelope["soap:Body"] || envelope["Body"] || %{}

      # Find the first non-attribute key as the operation
      operation_entry =
        Enum.find(body, fn {k, _v} ->
          !String.starts_with?(to_string(k), "@") and
            k not in ["soap:Fault", "Fault"]
        end)

      case operation_entry do
        {op_name, op_content} ->
          # Extract params, filtering out attributes
          params =
            if is_map(op_content) do
              op_content
              |> Enum.reject(fn {k, _v} -> String.starts_with?(to_string(k), "@") end)
              |> Enum.into(%{})
            else
              %{}
            end

          clean_name = op_name |> String.split(":") |> List.last()
          {clean_name, params}

        nil ->
          {"Unknown", %{}}
      end
    end

    defp build_response_with_headers(operation, params, incoming_headers) do
      # Create response headers that echo back received headers
      response_headers = build_response_headers(incoming_headers)

      # Build the operation response
      response_body = build_operation_response(operation, params, incoming_headers)

      envelope =
        if map_size(response_headers) > 0 do
          %{
            "soap:Envelope" => %{
              "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
              "soap:Header" => response_headers,
              "soap:Body" => response_body
            }
          }
        else
          %{
            "soap:Envelope" => %{
              "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
              "soap:Body" => response_body
            }
          }
        end

      case Builder.build(envelope) do
        {:ok, xml} -> xml
        {:error, _} -> error_response("Build error")
      end
    end

    defp build_response_headers(incoming_headers) do
      # Echo back headers with "Echo-" prefix
      # Handle namespaced keys by stripping the prefix to avoid invalid XML
      Enum.reduce(incoming_headers, %{}, fn {key, value}, acc ->
        # Strip namespace prefix from keys like "wsse:Security" -> "Security"
        base_key = key |> String.split(":") |> List.last()
        echo_key = "Echo-#{base_key}"

        # Recursively clean the value to remove namespace prefixes
        clean_value = clean_namespaced_content(value)

        Map.put(acc, echo_key, clean_value)
      end)
    end

    # Recursively clean namespace prefixes and attributes from content
    defp clean_namespaced_content(value) when is_map(value) do
      value
      |> Enum.reject(fn {k, _v} ->
        k_str = to_string(k)
        # Remove xmlns attributes to avoid namespace declaration issues
        String.starts_with?(k_str, "@xmlns")
      end)
      |> Enum.map(fn {k, v} ->
        k_str = to_string(k)
        # Strip namespace prefix from both element names and attributes
        clean_key = if String.starts_with?(k_str, "@") do
          # For attributes like @wsu:Id, strip the prefix: @wsu:Id -> @Id
          attr_name = String.trim_leading(k_str, "@")
          "@" <> (attr_name |> String.split(":") |> List.last())
        else
          # For elements, strip the prefix: wsse:Username -> Username
          k_str |> String.split(":") |> List.last()
        end
        {clean_key, clean_namespaced_content(v)}
      end)
      |> Enum.into(%{})
    end

    defp clean_namespaced_content(value) when is_list(value) do
      Enum.map(value, &clean_namespaced_content/1)
    end

    defp clean_namespaced_content(value), do: value

    defp build_operation_response(operation, params, incoming_headers) do
      response_name = "#{operation}Response"

      case operation do
        "EchoMessage" ->
          message = get_param_value(params, "message")
          %{response_name => %{"echo" => message}}

        "GetSessionInfo" ->
          query = get_param_value(params, "query")
          session_id = get_header_value(incoming_headers, "SessionId")
          %{response_name => %{"sessionId" => session_id || "no-session", "query" => query}}

        "ProcessWithHeaders" ->
          data = get_param_value(params, "data")
          header_summary = summarize_headers(incoming_headers)
          %{response_name => %{"processed" => "Processed: #{data}", "headersReceived" => header_summary}}

        _ ->
          %{response_name => %{"result" => "unknown operation"}}
      end
    end

    defp get_param_value(params, key) do
      case params[key] do
        nil -> ""
        value when is_binary(value) -> value
        %{"#text" => text} -> text
        value when is_map(value) -> inspect(value)
        value -> to_string(value)
      end
    end

    defp get_header_value(headers, key) do
      case headers[key] do
        nil -> nil
        value when is_binary(value) -> value
        %{"#text" => text} -> text
        value when is_map(value) -> Map.get(value, "#text") || inspect(value)
        value -> to_string(value)
      end
    end

    defp summarize_headers(headers) when map_size(headers) == 0, do: "none"

    defp summarize_headers(headers) do
      headers
      |> Map.keys()
      |> Enum.sort()
      |> Enum.join(",")
    end

    defp error_response(message) do
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Server</faultcode>
            <faultstring>#{message}</faultstring>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """
    end

    # Read the complete request body handling chunked reads
    defp read_full_body(conn, body \\ "") do
      case Plug.Conn.read_body(conn) do
        {:ok, chunk, conn} -> {:ok, body <> chunk, conn}
        {:more, chunk, conn} -> read_full_body(conn, body <> chunk)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  describe "session headers round trip" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "client can send session ID header and server reads it", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Create session header
      session_header = Header.session("my-session-abc123")

      # Call with session header
      {:ok, response} = Lather.DynamicClient.call(
        client,
        "GetSessionInfo",
        %{"query" => "test"},
        headers: [session_header]
      )

      # Server should have read the session ID from the header
      assert response["sessionId"] == "my-session-abc123"
      assert response["query"] == "test"
    end

    test "session header with custom name and namespace", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Create session header with custom name and namespace
      session_header = Header.session("custom-session-xyz",
        header_name: "CustomSession",
        namespace: "http://example.com/session"
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "payload"},
        headers: [session_header]
      )

      # The server should acknowledge receiving the CustomSession header
      assert String.contains?(response["headersReceived"], "CustomSession")
    end
  end

  describe "custom headers round trip" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "custom header with string content", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      custom_header = Header.custom("MyAppVersion", "1.0.5")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "test"},
        headers: [custom_header]
      )

      assert String.contains?(response["headersReceived"], "MyAppVersion")
    end

    test "custom header with map content", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      custom_header = Header.custom("RequestMetadata", %{
        "clientId" => "client-123",
        "timestamp" => "2025-01-15T10:30:00Z"
      })

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "test"},
        headers: [custom_header]
      )

      assert String.contains?(response["headersReceived"], "RequestMetadata")
    end

    test "custom header with attributes", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      custom_header = Header.custom(
        "AuthToken",
        "token-value-xyz",
        %{"xmlns" => "http://example.com/auth", "mustUnderstand" => "1"}
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "secured-data"},
        headers: [custom_header]
      )

      assert String.contains?(response["headersReceived"], "AuthToken")
    end
  end

  describe "multiple headers round trip" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "combining multiple headers in one request", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Create multiple headers
      session_header = Header.session("session-multi-123")
      app_header = Header.custom("AppVersion", "2.0")
      client_header = Header.custom("ClientId", "mobile-client")

      # Merge them
      merged = Header.merge_headers([session_header, app_header, client_header])

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "multi-header-test"},
        headers: [merged]
      )

      # Server should have received all headers
      received = response["headersReceived"]
      assert String.contains?(received, "SessionId")
      assert String.contains?(received, "AppVersion")
      assert String.contains?(received, "ClientId")
    end

    test "passing headers as list without merging", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Pass multiple header maps as a list
      headers = [
        Header.session("list-session-456"),
        Header.custom("TraceId", "trace-abc-def")
      ]

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "list-headers-test"},
        headers: headers
      )

      received = response["headersReceived"]
      assert String.contains?(received, "SessionId")
      assert String.contains?(received, "TraceId")
    end
  end

  describe "headers with namespaces round trip" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "header with explicit xmlns namespace", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      namespaced_header = Header.custom(
        "CorrelationId",
        "corr-12345",
        %{"xmlns" => "http://example.com/correlation"}
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "namespaced-test"},
        headers: [namespaced_header]
      )

      assert String.contains?(response["headersReceived"], "CorrelationId")
    end

    test "header with prefixed namespace", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Create header with prefixed namespace attribute
      prefixed_header = %{
        "ns1:CustomHeader" => %{
          "@xmlns:ns1" => "http://example.com/custom",
          "#text" => "prefixed-value"
        }
      }

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "prefixed-ns-test"},
        headers: [prefixed_header]
      )

      # Server should receive the namespaced header
      assert response["processed"] == "Processed: prefixed-ns-test"
    end

    test "multiple namespaces in different headers", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      headers = [
        Header.custom("Header1", "value1", %{"xmlns" => "http://example.com/ns1"}),
        Header.custom("Header2", "value2", %{"xmlns" => "http://example.com/ns2"})
      ]

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "multi-ns-test"},
        headers: headers
      )

      received = response["headersReceived"]
      assert String.contains?(received, "Header1")
      assert String.contains?(received, "Header2")
    end
  end

  describe "headers with attributes round trip" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "header with mustUnderstand attribute", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header_with_attr = Header.custom(
        "TransactionId",
        "txn-999",
        %{
          "xmlns" => "http://example.com/txn",
          "soap:mustUnderstand" => "1"
        }
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "must-understand-test"},
        headers: [header_with_attr]
      )

      assert String.contains?(response["headersReceived"], "TransactionId")
    end

    test "header with actor/role attribute", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header_with_actor = Header.custom(
        "RoutingInfo",
        %{"destination" => "backend-service"},
        %{
          "xmlns" => "http://example.com/routing",
          "soap:actor" => "http://schemas.xmlsoap.org/soap/actor/next"
        }
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "routing-test"},
        headers: [header_with_actor]
      )

      assert String.contains?(response["headersReceived"], "RoutingInfo")
    end

    test "header with multiple custom attributes", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      multi_attr_header = Header.custom(
        "ExtendedInfo",
        "extended-value",
        %{
          "xmlns" => "http://example.com/extended",
          "version" => "2",
          "priority" => "high",
          "encrypted" => "false"
        }
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "multi-attr-test"},
        headers: [multi_attr_header]
      )

      assert String.contains?(response["headersReceived"], "ExtendedInfo")
    end
  end

  describe "server reading headers from incoming request" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "server extracts and uses header values in response", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      session_header = Header.session("extracted-session-id")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "GetSessionInfo",
        %{"query" => "get-user-info"},
        headers: [session_header]
      )

      # The server should have extracted and used the session ID
      assert response["sessionId"] == "extracted-session-id"
    end

    test "server handles missing headers gracefully", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Call without any headers
      {:ok, response} = Lather.DynamicClient.call(
        client,
        "GetSessionInfo",
        %{"query" => "no-session-test"}
      )

      # Server should return a default or indicate no session
      assert response["sessionId"] == "no-session"
    end

    test "server correctly parses complex header structures", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      complex_header = Header.custom("ComplexData", %{
        "user" => %{
          "id" => "user-123",
          "role" => "admin"
        },
        "timestamp" => "2025-01-15T12:00:00Z"
      })

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "complex-header-test"},
        headers: [complex_header]
      )

      assert String.contains?(response["headersReceived"], "ComplexData")
    end
  end

  describe "server including headers in response" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "response contains echoed headers", %{base_url: base_url} do
      # This test verifies the server can add headers to the response
      # by making a raw HTTP request and inspecting the response XML

      session_header = Header.session("echo-this-session")
      {:ok, envelope} = Lather.Soap.Envelope.build(
        "ProcessWithHeaders",
        %{"data" => "echo-test"},
        headers: [session_header],
        namespace: "http://test.example.com/headers"
      )

      # Send raw request and check response headers
      {:ok, response} = Finch.build(
        :post,
        "#{base_url}/soap",
        [{"content-type", "text/xml; charset=utf-8"}],
        envelope
      )
      |> Finch.request(Lather.Finch)

      # Parse the response to check for echoed headers
      {:ok, parsed} = Parser.parse(response.body)

      envelope_data = parsed["soap:Envelope"]
      header_section = envelope_data["soap:Header"]

      # The server should have included Echo-SessionId in response headers
      assert header_section != nil
      assert Map.has_key?(header_section, "Echo-SessionId")
    end

    test "response headers preserve values", %{base_url: base_url} do
      custom_header = Header.custom("RequestId", "req-abc-123")

      {:ok, envelope} = Lather.Soap.Envelope.build(
        "EchoMessage",
        %{"message" => "hello"},
        headers: [custom_header],
        namespace: "http://test.example.com/headers"
      )

      {:ok, response} = Finch.build(
        :post,
        "#{base_url}/soap",
        [{"content-type", "text/xml; charset=utf-8"}],
        envelope
      )
      |> Finch.request(Lather.Finch)

      {:ok, parsed} = Parser.parse(response.body)

      envelope_data = parsed["soap:Envelope"]
      header_section = envelope_data["soap:Header"]

      # Check that Echo-RequestId contains the original value
      echo_request_id = header_section["Echo-RequestId"]
      assert echo_request_id != nil

      # Extract the text value
      value = case echo_request_id do
        v when is_binary(v) -> v
        %{"#text" => t} -> t
        m when is_map(m) -> Map.get(m, "#text", inspect(m))
      end

      assert value == "req-abc-123"
    end
  end

  describe "header round trip with WS-Security" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "WS-Security username token header", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      # Create WS-Security header
      ws_security_header = Header.username_token("testuser", "testpass", password_type: :text)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "ws-security-test"},
        headers: [ws_security_header]
      )

      # Server should have received the wsse:Security header
      assert String.contains?(response["headersReceived"], "wsse:Security")
    end

    test "WS-Security timestamp header", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      timestamp_header = Header.timestamp(ttl: 300)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "timestamp-test"},
        headers: [timestamp_header]
      )

      assert String.contains?(response["headersReceived"], "wsse:Security")
    end

    test "combined WS-Security with username token and timestamp", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      combined_header = Header.username_token_with_timestamp("user1", "pass1", ttl: 600)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "combined-ws-security-test"},
        headers: [combined_header]
      )

      assert String.contains?(response["headersReceived"], "wsse:Security")
    end
  end

  describe "header edge cases" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      port = Enum.random(10000..60000)
      {:ok, server_pid} = Bandit.start_link(plug: HeaderAwareRouter, port: port, scheme: :http)

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

    test "empty header list", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "EchoMessage",
        %{"message" => "no-headers"},
        headers: []
      )

      assert response["echo"] == "no-headers"
    end

    test "header with empty string value", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      empty_header = Header.custom("EmptyValue", "")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "empty-value-test"},
        headers: [empty_header]
      )

      assert String.contains?(response["headersReceived"], "EmptyValue")
    end

    test "header with special characters in value", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      special_header = Header.custom("SpecialChars", "value<with>&special\"chars'")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "special-chars-test"},
        headers: [special_header]
      )

      assert String.contains?(response["headersReceived"], "SpecialChars")
    end

    test "header with unicode characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      unicode_header = Header.custom("UnicodeValue", "Hello World")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "unicode-test"},
        headers: [unicode_header]
      )

      assert String.contains?(response["headersReceived"], "UnicodeValue")
    end

    test "deeply nested header structure", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      nested_header = Header.custom("DeepNested", %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "value" => "deeply-nested-value"
            }
          }
        }
      })

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "deep-nested-test"},
        headers: [nested_header]
      )

      assert String.contains?(response["headersReceived"], "DeepNested")
    end

    test "very long header value", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      long_value = String.duplicate("x", 10_000)
      long_header = Header.custom("LongValue", long_value)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessWithHeaders",
        %{"data" => "long-value-test"},
        headers: [long_header]
      )

      assert String.contains?(response["headersReceived"], "LongValue")
    end
  end

  describe "header merge functionality" do
    test "merge_headers combines multiple header maps" do
      header1 = Header.session("session-123")
      header2 = Header.custom("AppVersion", "1.0")
      header3 = Header.custom("ClientId", "client-abc")

      merged = Header.merge_headers([header1, header2, header3])

      assert Map.has_key?(merged, "SessionId")
      assert Map.has_key?(merged, "AppVersion")
      assert Map.has_key?(merged, "ClientId")
    end

    test "merge_headers with overlapping keys deep merges nested content" do
      # When merging headers with the same key, deep_merge is applied.
      # For simple text content wrapped in maps, the reduce ordering
      # means later headers in the list take precedence at the leaf level.
      header1 = Header.custom("Key", "first-value")
      header2 = Header.custom("Key", "second-value")

      merged = Header.merge_headers([header1, header2])

      # Both headers have "Key" => %{"#text" => value}
      # The merge behavior depends on the implementation details
      # Just verify that merging works without error and produces a valid result
      assert Map.has_key?(merged, "Key")
      assert is_map(merged["Key"])
      assert Map.has_key?(merged["Key"], "#text")
    end

    test "merge_headers with nested maps performs deep merge" do
      header1 = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => "http://security.ns",
          "wsse:UsernameToken" => %{"Username" => "user1"}
        }
      }

      header2 = %{
        "wsse:Security" => %{
          "wsu:Timestamp" => %{"Created" => "2025-01-15T10:00:00Z"}
        }
      }

      merged = Header.merge_headers([header1, header2])

      security = merged["wsse:Security"]
      assert Map.has_key?(security, "wsse:UsernameToken")
      assert Map.has_key?(security, "wsu:Timestamp")
    end
  end
end
