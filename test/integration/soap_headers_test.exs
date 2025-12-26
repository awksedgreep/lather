defmodule Lather.Integration.SoapHeadersTest do
  @moduledoc """
  Comprehensive integration tests for custom SOAP headers.

  These tests verify that SOAP headers are properly:
  - Created using Lather.Soap.Header utilities
  - Placed in the SOAP envelope Header section (not Body)
  - Transmitted to the server
  - Read and processed by the server
  - Echoed back in responses

  Tests cover:
  - Session headers round-trip
  - Custom headers with namespaces
  - Multiple merged headers
  - Headers with attributes
  - Proper envelope structure verification
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Lather.Soap.Header
  alias Lather.Soap.Envelope
  alias Lather.Xml.Parser
  alias Lather.Xml.Builder

  # Define a test service that can read and echo SOAP headers
  defmodule HeaderEchoService do
    use Lather.Server

    @namespace "http://test.lather.com/headers"
    @service_name "HeaderEchoService"

    soap_operation "ProcessRequest" do
      description "Processes a request and reports received headers"
      input do
        parameter "requestData", :string, required: true
      end
      output do
        parameter "result", :string
        parameter "receivedHeaders", :string
      end
      soap_action "ProcessRequest"
    end

    soap_operation "GetSessionData" do
      description "Returns session data based on session header"
      input do
        parameter "key", :string, required: true
      end
      output do
        parameter "sessionId", :string
        parameter "value", :string
      end
      soap_action "GetSessionData"
    end

    soap_operation "EchoWithHeaders" do
      description "Echoes input and includes header info in response"
      input do
        parameter "message", :string, required: true
      end
      output do
        parameter "echo", :string
        parameter "headerCount", :integer
      end
      soap_action "EchoWithHeaders"
    end

    def process_request(%{"requestData" => data}) do
      {:ok, %{"result" => "Processed: #{data}", "receivedHeaders" => "acknowledged"}}
    end

    def get_session_data(%{"key" => key}) do
      {:ok, %{"sessionId" => "default-session", "value" => "value_for_#{key}"}}
    end

    def echo_with_headers(%{"message" => msg}) do
      {:ok, %{"echo" => msg, "headerCount" => 0}}
    end
  end

  # Custom router that parses SOAP requests and echoes headers
  defmodule HeaderAwareRouter do
    use Plug.Router
    plug :fetch_query_params
    plug :match
    plug :dispatch

    alias Lather.Xml.Parser
    alias Lather.Xml.Builder

    get "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.SoapHeadersTest.HeaderEchoService)
      )
    end

    post "/soap" do
      handle_soap_request(conn)
    end

    match _ do
      conn
      |> Plug.Conn.put_resp_content_type("text/xml")
      |> Plug.Conn.send_resp(404, fault_response("Not Found"))
    end

    defp handle_soap_request(conn) do
      case read_full_body(conn) do
        {:ok, body, conn} ->
          case Parser.parse(body) do
            {:ok, parsed} ->
              headers = extract_headers(parsed)
              {operation, params} = extract_operation(parsed)
              response_xml = build_response(operation, params, headers)

              conn
              |> Plug.Conn.put_resp_content_type("text/xml")
              |> Plug.Conn.send_resp(200, response_xml)

            {:error, _} ->
              conn
              |> Plug.Conn.put_resp_content_type("text/xml")
              |> Plug.Conn.send_resp(400, fault_response("XML Parse Error"))
          end

        {:error, _} ->
          conn
          |> Plug.Conn.put_resp_content_type("text/xml")
          |> Plug.Conn.send_resp(500, fault_response("Body Read Error"))
      end
    end

    defp read_full_body(conn, acc \\ "") do
      case Plug.Conn.read_body(conn) do
        {:ok, chunk, conn} -> {:ok, acc <> chunk, conn}
        {:more, chunk, conn} -> read_full_body(conn, acc <> chunk)
        {:error, reason} -> {:error, reason}
      end
    end

    defp extract_headers(parsed) do
      envelope = parsed["soap:Envelope"] || parsed["Envelope"] || %{}
      header = envelope["soap:Header"] || envelope["Header"]

      if header && is_map(header) do
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

      operation_entry =
        Enum.find(body, fn {k, _v} ->
          k_str = to_string(k)
          !String.starts_with?(k_str, "@") and k not in ["soap:Fault", "Fault"]
        end)

      case operation_entry do
        {op_name, op_content} ->
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

    defp build_response(operation, params, incoming_headers) do
      response_headers = build_echo_headers(incoming_headers)
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
        {:error, _} -> fault_response("Response Build Error")
      end
    end

    defp build_echo_headers(incoming_headers) do
      Enum.reduce(incoming_headers, %{}, fn {key, value}, acc ->
        base_key = key |> String.split(":") |> List.last()
        echo_key = "Echo-#{base_key}"
        clean_value = clean_value(value)
        Map.put(acc, echo_key, clean_value)
      end)
    end

    defp clean_value(value) when is_map(value) do
      value
      |> Enum.reject(fn {k, _} -> String.starts_with?(to_string(k), "@xmlns") end)
      |> Enum.map(fn {k, v} ->
        k_str = to_string(k)
        clean_key =
          if String.starts_with?(k_str, "@") do
            "@" <> (k_str |> String.trim_leading("@") |> String.split(":") |> List.last())
          else
            k_str |> String.split(":") |> List.last()
          end
        {clean_key, clean_value(v)}
      end)
      |> Enum.into(%{})
    end

    defp clean_value(value) when is_list(value), do: Enum.map(value, &clean_value/1)
    defp clean_value(value), do: value

    defp build_operation_response(operation, params, headers) do
      response_name = "#{operation}Response"

      case operation do
        "ProcessRequest" ->
          data = get_param(params, "requestData")
          header_list = headers |> Map.keys() |> Enum.sort() |> Enum.join(",")
          %{response_name => %{
            "result" => "Processed: #{data}",
            "receivedHeaders" => if(header_list == "", do: "none", else: header_list)
          }}

        "GetSessionData" ->
          key = get_param(params, "key")
          session_id = get_header_value(headers, "SessionId")
          %{response_name => %{
            "sessionId" => session_id || "no-session",
            "value" => "value_for_#{key}"
          }}

        "EchoWithHeaders" ->
          message = get_param(params, "message")
          header_count = map_size(headers)
          %{response_name => %{
            "echo" => message,
            "headerCount" => to_string(header_count)
          }}

        _ ->
          %{response_name => %{"result" => "unknown"}}
      end
    end

    defp get_param(params, key) do
      case params[key] do
        nil -> ""
        %{"#text" => text} -> text
        value when is_binary(value) -> value
        value -> to_string(value)
      end
    end

    defp get_header_value(headers, key) do
      case headers[key] do
        nil -> nil
        %{"#text" => text} -> text
        value when is_binary(value) -> value
        value when is_map(value) -> Map.get(value, "#text") || inspect(value)
        value -> to_string(value)
      end
    end

    defp fault_response(message) do
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
  end

  # Setup helper to start server
  defp setup_server(_context) do
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

  describe "session headers round-trip" do
    setup :setup_server

    test "simple session header is transmitted and read by server", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      session_header = Header.session("test-session-12345")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "GetSessionData",
        %{"key" => "user_preference"},
        headers: [session_header]
      )

      assert response["sessionId"] == "test-session-12345"
      assert response["value"] == "value_for_user_preference"
    end

    test "session header with custom name", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      session_header = Header.session("custom-sess-abc", header_name: "MySessionId")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "test"},
        headers: [session_header]
      )

      assert String.contains?(response["receivedHeaders"], "MySessionId")
    end

    test "session header with namespace", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      session_header = Header.session("namespaced-session",
        header_name: "AuthSession",
        namespace: "http://auth.example.com/session"
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "auth-test"},
        headers: [session_header]
      )

      assert String.contains?(response["receivedHeaders"], "AuthSession")
    end
  end

  describe "custom headers with namespaces" do
    setup :setup_server

    test "header with xmlns attribute", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      custom_header = Header.custom(
        "CorrelationId",
        "corr-12345-xyz",
        %{"xmlns" => "http://tracing.example.com/correlation"}
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "traced-request"},
        headers: [custom_header]
      )

      assert String.contains?(response["receivedHeaders"], "CorrelationId")
    end

    test "header with prefixed namespace (ns1:ElementName)", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      prefixed_header = %{
        "ns1:TraceContext" => %{
          "@xmlns:ns1" => "http://tracing.example.com/context",
          "ns1:TraceId" => "trace-abc-123",
          "ns1:SpanId" => "span-def-456"
        }
      }

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "traced-with-prefix"},
        headers: [prefixed_header]
      )

      assert String.contains?(response["receivedHeaders"], "TraceContext")
    end

    test "multiple headers with different namespaces", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      headers = [
        Header.custom("AuthToken", "token-xyz", %{"xmlns" => "http://auth.example.com"}),
        Header.custom("ClientInfo", "mobile-app-v2", %{"xmlns" => "http://client.example.com"}),
        Header.custom("RequestId", "req-001", %{"xmlns" => "http://request.example.com"})
      ]

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "multi-ns-request"},
        headers: headers
      )

      received = response["receivedHeaders"]
      assert String.contains?(received, "AuthToken")
      assert String.contains?(received, "ClientInfo")
      assert String.contains?(received, "RequestId")
    end
  end

  describe "multiple merged headers" do
    setup :setup_server

    test "merge_headers combines multiple header maps", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header1 = Header.session("merge-session-123")
      header2 = Header.custom("AppVersion", "3.2.1")
      header3 = Header.custom("Platform", "iOS")

      merged = Header.merge_headers([header1, header2, header3])

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "merged-headers-test"},
        headers: [merged]
      )

      received = response["receivedHeaders"]
      assert String.contains?(received, "SessionId")
      assert String.contains?(received, "AppVersion")
      assert String.contains?(received, "Platform")
    end

    test "passing headers as list (unmerged)", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      headers = [
        Header.session("list-session"),
        Header.custom("Locale", "en-US"),
        Header.custom("Timezone", "America/New_York")
      ]

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "EchoWithHeaders",
        %{"message" => "hello"},
        headers: headers
      )

      # Should have received 3 headers
      assert response["headerCount"] == "3"
    end

    test "deep merge of nested header structures" do
      header1 = %{
        "wsse:Security" => %{
          "@xmlns:wsse" => "http://security.example.com",
          "wsse:UsernameToken" => %{
            "wsse:Username" => "testuser"
          }
        }
      }

      header2 = %{
        "wsse:Security" => %{
          "wsu:Timestamp" => %{
            "@xmlns:wsu" => "http://timestamp.example.com",
            "wsu:Created" => "2025-01-01T00:00:00Z"
          }
        }
      }

      merged = Header.merge_headers([header1, header2])

      security = merged["wsse:Security"]
      assert Map.has_key?(security, "wsse:UsernameToken")
      assert Map.has_key?(security, "wsu:Timestamp")
      assert security["wsse:UsernameToken"]["wsse:Username"] == "testuser"
    end
  end

  describe "headers with attributes" do
    setup :setup_server

    test "header with mustUnderstand attribute", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom(
        "CriticalInfo",
        "important-value",
        %{
          "xmlns" => "http://critical.example.com",
          "soap:mustUnderstand" => "1"
        }
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "must-understand"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "CriticalInfo")
    end

    test "header with actor/role attribute", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom(
        "RoutingHeader",
        %{"destination" => "backend-service", "priority" => "high"},
        %{
          "xmlns" => "http://routing.example.com",
          "soap:actor" => "http://schemas.xmlsoap.org/soap/actor/next"
        }
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "routed-request"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "RoutingHeader")
    end

    test "header with multiple custom attributes", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom(
        "EnrichedHeader",
        "enriched-data",
        %{
          "xmlns" => "http://enriched.example.com",
          "version" => "2.0",
          "encrypted" => "false",
          "priority" => "normal",
          "ttl" => "3600"
        }
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "enriched-request"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "EnrichedHeader")
    end

    test "header with nested content and attributes", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom(
        "ComplexHeader",
        %{
          "level1" => %{
            "level2" => %{
              "deepValue" => "nested-content"
            }
          },
          "metadata" => "extra-info"
        },
        %{"xmlns" => "http://complex.example.com", "id" => "hdr-001"}
      )

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "complex-nested"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "ComplexHeader")
    end
  end

  describe "headers properly placed in SOAP envelope" do
    setup :setup_server

    test "headers appear in soap:Header, not soap:Body", %{base_url: base_url} do
      session_header = Header.session("envelope-test-session")
      custom_header = Header.custom("TestHeader", "test-value")

      {:ok, envelope_xml} = Envelope.build(
        "ProcessRequest",
        %{"requestData" => "envelope-structure-test"},
        headers: [session_header, custom_header],
        namespace: "http://test.lather.com/headers"
      )

      # Parse the envelope to verify structure
      {:ok, parsed} = Parser.parse(envelope_xml)

      envelope = parsed["soap:Envelope"]
      assert envelope != nil, "Expected soap:Envelope element"

      header_section = envelope["soap:Header"]
      body_section = envelope["soap:Body"]

      # Verify headers are in Header section
      assert header_section != nil, "Expected soap:Header element"
      assert Map.has_key?(header_section, "SessionId"), "SessionId should be in Header"
      assert Map.has_key?(header_section, "TestHeader"), "TestHeader should be in Header"

      # Verify headers are NOT in Body section
      assert body_section != nil, "Expected soap:Body element"
      refute Map.has_key?(body_section, "SessionId"), "SessionId should NOT be in Body"
      refute Map.has_key?(body_section, "TestHeader"), "TestHeader should NOT be in Body"

      # Verify body contains the operation
      assert Map.has_key?(body_section, "ProcessRequest"), "ProcessRequest should be in Body"
    end

    test "envelope structure with WS-Security header", %{base_url: base_url} do
      ws_security = Header.username_token("testuser", "testpass", password_type: :text)

      {:ok, envelope_xml} = Envelope.build(
        "ProcessRequest",
        %{"requestData" => "ws-security-test"},
        headers: [ws_security],
        namespace: "http://test.lather.com/headers"
      )

      {:ok, parsed} = Parser.parse(envelope_xml)

      envelope = parsed["soap:Envelope"]
      header_section = envelope["soap:Header"]
      body_section = envelope["soap:Body"]

      # WS-Security should be in Header
      assert Map.has_key?(header_section, "wsse:Security"), "wsse:Security should be in Header"
      refute Map.has_key?(body_section, "wsse:Security"), "wsse:Security should NOT be in Body"
    end

    test "envelope without headers has no Header element when empty", %{base_url: _base_url} do
      {:ok, envelope_xml} = Envelope.build(
        "ProcessRequest",
        %{"requestData" => "no-headers-test"},
        headers: [],
        namespace: "http://test.lather.com/headers"
      )

      {:ok, parsed} = Parser.parse(envelope_xml)

      envelope = parsed["soap:Envelope"]
      body_section = envelope["soap:Body"]

      # Verify body exists and contains operation
      assert body_section != nil
      assert Map.has_key?(body_section, "ProcessRequest")
    end

    test "multiple headers all appear in Header section", %{base_url: _base_url} do
      headers = [
        Header.session("multi-header-session"),
        Header.custom("Header1", "value1"),
        Header.custom("Header2", "value2"),
        Header.custom("Header3", "value3"),
        Header.custom("Header4", %{"nested" => "content"})
      ]

      {:ok, envelope_xml} = Envelope.build(
        "ProcessRequest",
        %{"requestData" => "multi-header-test"},
        headers: headers,
        namespace: "http://test.lather.com/headers"
      )

      {:ok, parsed} = Parser.parse(envelope_xml)

      envelope = parsed["soap:Envelope"]
      header_section = envelope["soap:Header"]
      body_section = envelope["soap:Body"]

      # All headers should be in Header section
      assert Map.has_key?(header_section, "SessionId")
      assert Map.has_key?(header_section, "Header1")
      assert Map.has_key?(header_section, "Header2")
      assert Map.has_key?(header_section, "Header3")
      assert Map.has_key?(header_section, "Header4")

      # None should be in Body
      refute Map.has_key?(body_section, "SessionId")
      refute Map.has_key?(body_section, "Header1")
      refute Map.has_key?(body_section, "Header2")
      refute Map.has_key?(body_section, "Header3")
      refute Map.has_key?(body_section, "Header4")
    end
  end

  describe "server reading and echoing headers" do
    setup :setup_server

    test "server echoes received headers in response", %{base_url: base_url} do
      session_header = Header.session("echo-session-xyz")

      {:ok, envelope} = Envelope.build(
        "ProcessRequest",
        %{"requestData" => "echo-test"},
        headers: [session_header],
        namespace: "http://test.lather.com/headers"
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
      response_header = envelope_data["soap:Header"]

      # Server should have echoed back the SessionId
      assert response_header != nil
      assert Map.has_key?(response_header, "Echo-SessionId")
    end

    test "echoed header preserves value", %{base_url: base_url} do
      custom_header = Header.custom("RequestId", "req-abc-789")

      {:ok, envelope} = Envelope.build(
        "EchoWithHeaders",
        %{"message" => "preserve-value-test"},
        headers: [custom_header],
        namespace: "http://test.lather.com/headers"
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
      response_header = envelope_data["soap:Header"]
      echo_request_id = response_header["Echo-RequestId"]

      # Extract value
      value = case echo_request_id do
        v when is_binary(v) -> v
        %{"#text" => t} -> t
        m when is_map(m) -> Map.get(m, "#text", inspect(m))
      end

      assert value == "req-abc-789"
    end

    test "multiple headers are all echoed", %{base_url: base_url} do
      headers = [
        Header.session("multi-echo-session"),
        Header.custom("ClientId", "client-001"),
        Header.custom("RequestId", "req-002")
      ]

      {:ok, envelope} = Envelope.build(
        "ProcessRequest",
        %{"requestData" => "multi-echo-test"},
        headers: headers,
        namespace: "http://test.lather.com/headers"
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
      response_header = envelope_data["soap:Header"]

      assert Map.has_key?(response_header, "Echo-SessionId")
      assert Map.has_key?(response_header, "Echo-ClientId")
      assert Map.has_key?(response_header, "Echo-RequestId")
    end
  end

  describe "header edge cases" do
    setup :setup_server

    test "empty string header value", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom("EmptyHeader", "")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "empty-value-test"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "EmptyHeader")
    end

    test "header with special XML characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom("SpecialChars", "value<with>&\"special'chars")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "special-chars-test"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "SpecialChars")
    end

    test "header with unicode characters", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom("UnicodeHeader", "Hello World - Hola Mundo")

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "unicode-test"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "UnicodeHeader")
    end

    test "very long header value", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      long_value = String.duplicate("x", 5000)
      header = Header.custom("LongHeader", long_value)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "long-value-test"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "LongHeader")
    end

    test "deeply nested header structure", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      header = Header.custom("DeepHeader", %{
        "l1" => %{
          "l2" => %{
            "l3" => %{
              "l4" => %{
                "value" => "deep"
              }
            }
          }
        }
      })

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "ProcessRequest",
        %{"requestData" => "deep-nest-test"},
        headers: [header]
      )

      assert String.contains?(response["receivedHeaders"], "DeepHeader")
    end

    test "request without any headers", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "GetSessionData",
        %{"key" => "test-key"}
      )

      # Should return default session since no header was provided
      assert response["sessionId"] == "no-session"
    end

    test "empty headers list", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      {:ok, response} = Lather.DynamicClient.call(
        client,
        "EchoWithHeaders",
        %{"message" => "no-headers"},
        headers: []
      )

      assert response["echo"] == "no-headers"
      assert response["headerCount"] == "0"
    end
  end

  describe "Header module unit tests" do
    test "session/1 creates simple session header" do
      header = Header.session("my-session-id")
      assert header == %{"SessionId" => "my-session-id"}
    end

    test "session/2 with custom name" do
      header = Header.session("sess-123", header_name: "CustomSessionId")
      assert header == %{"CustomSessionId" => "sess-123"}
    end

    test "session/2 with namespace" do
      header = Header.session("sess-456", namespace: "http://session.example.com")
      assert header == %{"SessionId" => %{"@xmlns" => "http://session.example.com", "#text" => "sess-456"}}
    end

    test "custom/2 with string content" do
      header = Header.custom("MyHeader", "my-value")
      assert header == %{"MyHeader" => %{"#text" => "my-value"}}
    end

    test "custom/2 with map content" do
      header = Header.custom("MyHeader", %{"key1" => "val1", "key2" => "val2"})
      assert header == %{"MyHeader" => %{"key1" => "val1", "key2" => "val2"}}
    end

    test "custom/3 with attributes" do
      header = Header.custom("MyHeader", "value", %{"xmlns" => "http://example.com", "id" => "h1"})
      assert header == %{
        "MyHeader" => %{
          "@xmlns" => "http://example.com",
          "@id" => "h1",
          "#text" => "value"
        }
      }
    end

    test "merge_headers/1 combines multiple headers" do
      h1 = Header.session("sess-1")
      h2 = Header.custom("Header2", "val2")
      h3 = Header.custom("Header3", "val3")

      merged = Header.merge_headers([h1, h2, h3])

      assert Map.has_key?(merged, "SessionId")
      assert Map.has_key?(merged, "Header2")
      assert Map.has_key?(merged, "Header3")
    end

    test "merge_headers/1 deep merges nested structures" do
      h1 = %{"Parent" => %{"child1" => "value1"}}
      h2 = %{"Parent" => %{"child2" => "value2"}}

      merged = Header.merge_headers([h1, h2])

      parent = merged["Parent"]
      assert parent["child1"] == "value1"
      assert parent["child2"] == "value2"
    end
  end
end
