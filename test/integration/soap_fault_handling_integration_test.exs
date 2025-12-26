defmodule Lather.Integration.SoapFaultHandlingIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for SOAP Fault and HTTP Error Handling.

  These tests verify the complete error handling flow including:
  1. HTTP 500 with SOAP Fault Response (SOAP 1.1 and 1.2)
  2. HTTP Error Codes Without SOAP Fault
  3. HTTP 500 with Malformed Fault
  4. SOAP Fault Detail Extraction
  5. Error Recovery Detection
  6. DynamicClient Error Handling
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Lather.DynamicClient
  alias Lather.Error

  # Test service module
  defmodule FaultTestService do
    use Lather.Server

    @namespace "http://test.example.com/faulttest"
    @service_name "FaultTestService"

    soap_operation "TestOperation" do
      description "A test operation that can return various fault types"

      input do
        parameter "request_type", :string, required: true
      end

      output do
        parameter "result", :string
      end

      soap_action "TestOperation"
    end

    def test_operation(%{"request_type" => "success"}) do
      {:ok, %{"result" => "Operation succeeded"}}
    end

    def test_operation(%{"request_type" => _}) do
      {:error, "Unsupported request type"}
    end
  end

  # ETS-based configuration storage for cross-process access
  defmodule ErrorConfig do
    @table_name :soap_fault_integration_test_config

    def init do
      if :ets.whereis(@table_name) == :undefined do
        :ets.new(@table_name, [:named_table, :public, :set])
      end

      :ok
    end

    def set(error_type, opts \\ []) do
      init()
      :ets.insert(@table_name, {:config, error_type, opts})
    end

    def get do
      init()

      case :ets.lookup(@table_name, :config) do
        [{:config, error_type, opts}] -> {error_type, opts}
        [] -> {:success, []}
      end
    end
  end

  # Router that returns various error responses based on configuration
  defmodule FaultTestRouter do
    use Plug.Router

    plug(:fetch_query_params)
    plug(:match)
    plug(:dispatch)

    # WSDL endpoint - always works
    get "/soap" do
      if conn.query_params["wsdl"] != nil do
        Lather.Server.Plug.call(
          conn,
          Lather.Server.Plug.init(
            service: Lather.Integration.SoapFaultHandlingIntegrationTest.FaultTestService
          )
        )
      else
        send_resp(conn, 400, "Invalid request")
      end
    end

    # SOAP endpoint - returns configured error response
    post "/soap" do
      {error_type, opts} = Lather.Integration.SoapFaultHandlingIntegrationTest.ErrorConfig.get()
      handle_error_response(conn, error_type, opts)
    end

    # Handle different error scenarios
    defp handle_error_response(conn, :success, _opts) do
      response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <TestOperationResponse xmlns="http://test.example.com/faulttest">
            <result>Operation succeeded</result>
          </TestOperationResponse>
        </soap:Body>
      </soap:Envelope>
      """

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(200, response)
    end

    # HTTP 500 with SOAP 1.1 Fault
    defp handle_error_response(conn, :soap_1_1_fault, opts) do
      fault_code = Keyword.get(opts, :fault_code, "Server")
      fault_string = Keyword.get(opts, :fault_string, "Internal server error")
      fault_actor = Keyword.get(opts, :fault_actor)
      detail = Keyword.get(opts, :detail)

      detail_xml =
        if detail do
          case detail do
            detail when is_binary(detail) ->
              "<detail>#{escape_xml(detail)}</detail>"

            %{} = detail_map ->
              detail_content =
                Enum.map_join(detail_map, "", fn {key, value} ->
                  "<#{key}>#{escape_xml(to_string(value))}</#{key}>"
                end)

              "<detail>#{detail_content}</detail>"
          end
        else
          ""
        end

      actor_xml = if fault_actor, do: "<faultactor>#{escape_xml(fault_actor)}</faultactor>", else: ""

      fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>#{escape_xml(fault_code)}</faultcode>
            <faultstring>#{escape_xml(fault_string)}</faultstring>
            #{actor_xml}
            #{detail_xml}
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, fault_xml)
    end

    # HTTP 500 with SOAP 1.2 Fault
    defp handle_error_response(conn, :soap_1_2_fault, opts) do
      fault_code = Keyword.get(opts, :fault_code, "soap:Receiver")
      fault_reason = Keyword.get(opts, :fault_reason, "Internal server error")
      detail = Keyword.get(opts, :detail)
      subcode = Keyword.get(opts, :subcode)

      subcode_xml =
        if subcode do
          """
          <soap:Subcode>
            <soap:Value>#{escape_xml(subcode)}</soap:Value>
          </soap:Subcode>
          """
        else
          ""
        end

      detail_xml =
        if detail do
          case detail do
            detail when is_binary(detail) ->
              "<soap:Detail><message>#{escape_xml(detail)}</message></soap:Detail>"

            %{} = detail_map ->
              detail_content =
                Enum.map_join(detail_map, "", fn {key, value} ->
                  "<#{key}>#{escape_xml(to_string(value))}</#{key}>"
                end)

              "<soap:Detail>#{detail_content}</soap:Detail>"
          end
        else
          ""
        end

      fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <soap:Fault>
            <soap:Code>
              <soap:Value>#{escape_xml(fault_code)}</soap:Value>
              #{subcode_xml}
            </soap:Code>
            <soap:Reason>
              <soap:Text xml:lang="en">#{escape_xml(fault_reason)}</soap:Text>
            </soap:Reason>
            #{detail_xml}
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      conn
      |> put_resp_content_type("application/soap+xml")
      |> send_resp(500, fault_xml)
    end

    # HTTP 400 Bad Request with plain text body
    defp handle_error_response(conn, :http_400_plain_text, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "Bad Request: Invalid SOAP request format")
    end

    # HTTP 401 Unauthorized without body
    defp handle_error_response(conn, :http_401_no_body, _opts) do
      conn
      |> put_resp_header("www-authenticate", "Basic realm=\"SOAP Service\"")
      |> send_resp(401, "")
    end

    # HTTP 403 Forbidden
    defp handle_error_response(conn, :http_403, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "Access forbidden")
    end

    # HTTP 502 Bad Gateway
    defp handle_error_response(conn, :http_502, _opts) do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(502, "<html><body><h1>502 Bad Gateway</h1></body></html>")
    end

    # HTTP 503 Service Unavailable
    defp handle_error_response(conn, :http_503, opts) do
      retry_after = Keyword.get(opts, :retry_after, "300")

      conn
      |> put_resp_header("retry-after", retry_after)
      |> put_resp_content_type("text/plain")
      |> send_resp(503, "Service temporarily unavailable")
    end

    # HTTP 504 Gateway Timeout
    defp handle_error_response(conn, :http_504, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(504, "Gateway timeout")
    end

    # HTTP 500 with invalid XML in response
    defp handle_error_response(conn, :http_500_invalid_xml, _opts) do
      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, "<?xml version=\"1.0\"?><invalid><unclosed>")
    end

    # HTTP 500 with partial/truncated XML
    defp handle_error_response(conn, :http_500_truncated_xml, _opts) do
      truncated_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Server</faultcode>
            <faultstring>Error mes
      """

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, truncated_xml)
    end

    # HTTP 500 with empty body
    defp handle_error_response(conn, :http_500_empty_body, _opts) do
      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, "")
    end

    # HTTP 500 with HTML error page instead of SOAP fault
    defp handle_error_response(conn, :http_500_html_error, _opts) do
      html_error = """
      <!DOCTYPE html>
      <html>
      <head><title>500 Internal Server Error</title></head>
      <body>
        <h1>Internal Server Error</h1>
        <p>The server encountered an internal error and was unable to complete your request.</p>
        <p>Error ID: ABC123</p>
      </body>
      </html>
      """

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(500, html_error)
    end

    # SOAP fault with complex nested XML detail
    defp handle_error_response(conn, :soap_fault_complex_detail, _opts) do
      fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                     xmlns:app="http://example.com/app">
        <soap:Body>
          <soap:Fault>
            <faultcode>Server</faultcode>
            <faultstring>Application error occurred</faultstring>
            <detail>
              <app:ErrorInfo>
                <app:ErrorCode>APP_ERR_001</app:ErrorCode>
                <app:ErrorMessage>Database connection failed</app:ErrorMessage>
                <app:Timestamp>2024-01-15T12:30:00Z</app:Timestamp>
                <app:Context>
                  <app:Service>UserService</app:Service>
                  <app:Operation>GetUser</app:Operation>
                  <app:RequestId>req-12345</app:RequestId>
                </app:Context>
                <app:RetryInfo>
                  <app:Retryable>true</app:Retryable>
                  <app:RetryAfterSeconds>60</app:RetryAfterSeconds>
                </app:RetryInfo>
              </app:ErrorInfo>
            </detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, fault_xml)
    end

    # SOAP fault with multiple detail elements
    defp handle_error_response(conn, :soap_fault_multiple_details, _opts) do
      fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Client</faultcode>
            <faultstring>Validation failed</faultstring>
            <detail>
              <ValidationError>
                <Field>email</Field>
                <Message>Invalid email format</Message>
              </ValidationError>
              <ValidationError>
                <Field>phone</Field>
                <Message>Phone number is required</Message>
              </ValidationError>
              <ValidationError>
                <Field>birthDate</Field>
                <Message>Date must be in the past</Message>
              </ValidationError>
            </detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, fault_xml)
    end

    # SOAP 1.1 fault with typed elements (xsi:type attributes)
    defp handle_error_response(conn, :soap_1_1_typed_fault, _opts) do
      fault_xml = """
      <?xml version="1.0" encoding="ISO-8859-1"?>
      <SOAP-ENV:Envelope SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <SOAP-ENV:Body>
          <SOAP-ENV:Fault>
            <faultcode xsi:type="xsd:string">SERVER</faultcode>
            <faultactor xsi:type="xsd:string">http://example.com/service</faultactor>
            <faultstring xsi:type="xsd:string">No valid points were found.</faultstring>
            <detail xsi:type="xsd:string">Attempted to find local times for submitted points but failed.</detail>
          </SOAP-ENV:Fault>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
      """

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(500, fault_xml)
    end

    defp escape_xml(text) when is_binary(text) do
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\"", "&quot;")
      |> String.replace("'", "&apos;")
    end

    defp escape_xml(value), do: to_string(value)
  end

  # ============================================================================
  # Test: HTTP 500 with SOAP 1.1 Fault Response
  # ============================================================================

  describe "HTTP 500 with SOAP 1.1 Fault Response" do
    setup do
      start_test_server(:soap_1_1_fault,
        fault_code: "Server",
        fault_string: "Internal server error",
        fault_actor: "http://example.com/service",
        detail: "Database connection timeout"
      )
    end

    test "extracts fault code from SOAP 1.1 fault", %{base_url: base_url} do
      {:ok, response} = make_soap_request(base_url, build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.fault_code == "Server"
    end

    test "extracts fault string from SOAP 1.1 fault", %{base_url: base_url} do
      {:ok, response} = make_soap_request(base_url, build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.fault_string == "Internal server error"
    end

    test "extracts fault actor from SOAP 1.1 fault", %{base_url: base_url} do
      {:ok, response} = make_soap_request(base_url, build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.fault_actor == "http://example.com/service"
    end

    test "extracts detail from SOAP 1.1 fault", %{base_url: base_url} do
      {:ok, response} = make_soap_request(base_url, build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.detail == "Database connection timeout"
    end

    test "handles Client fault code", %{port: port} do
      ErrorConfig.set(:soap_1_1_fault,
        fault_code: "Client",
        fault_string: "Invalid request",
        detail: "Missing required parameter"
      )

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.fault_code == "Client"
      assert fault.fault_string == "Invalid request"
    end

    test "handles fault without optional elements", %{port: port} do
      ErrorConfig.set(:soap_1_1_fault,
        fault_code: "Server",
        fault_string: "Error occurred"
      )

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.fault_code == "Server"
      assert fault.fault_string == "Error occurred"
    end

    test "handles SOAP 1.1 fault with typed elements (xsi:type)", %{port: port} do
      ErrorConfig.set(:soap_1_1_typed_fault, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.fault_code == "SERVER"
      assert fault.fault_string == "No valid points were found."
      assert fault.fault_actor == "http://example.com/service"
    end
  end

  # ============================================================================
  # Test: HTTP 500 with SOAP 1.2 Fault Response
  # ============================================================================

  describe "HTTP 500 with SOAP 1.2 Fault Response" do
    setup do
      start_test_server(:soap_1_2_fault,
        fault_code: "soap:Receiver",
        fault_reason: "Internal processing error",
        detail: "The service encountered an unexpected error"
      )
    end

    test "extracts fault code from SOAP 1.2 fault", %{base_url: base_url} do
      {:ok, response} = make_soap_request(base_url, build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_1_2_fault_from_body(response.body)
      assert fault.code == "soap:Receiver"
    end

    test "extracts fault reason from SOAP 1.2 fault", %{base_url: base_url} do
      {:ok, response} = make_soap_request(base_url, build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_1_2_fault_from_body(response.body)
      assert fault.reason == "Internal processing error"
    end

    test "extracts detail from SOAP 1.2 fault", %{base_url: base_url} do
      {:ok, response} = make_soap_request(base_url, build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_1_2_fault_from_body(response.body)
      assert is_map(fault.detail)
    end

    test "handles Sender fault code (SOAP 1.2)", %{port: port} do
      ErrorConfig.set(:soap_1_2_fault,
        fault_code: "soap:Sender",
        fault_reason: "Invalid message format"
      )

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_1_2_fault_from_body(response.body)
      assert fault.code == "soap:Sender"
    end

    test "handles SOAP 1.2 fault with subcode", %{port: port} do
      ErrorConfig.set(:soap_1_2_fault,
        fault_code: "soap:Receiver",
        fault_reason: "Processing error",
        subcode: "app:DatabaseError"
      )

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_1_2_fault_from_body(response.body)
      assert fault.code == "soap:Receiver"
      assert fault.subcode == "app:DatabaseError"
    end
  end

  # ============================================================================
  # Test: HTTP Error Codes Without SOAP Fault
  # ============================================================================

  describe "HTTP Error Codes Without SOAP Fault" do
    setup do
      start_test_server(:success, [])
    end

    test "handles 400 Bad Request with plain text body", %{port: port} do
      ErrorConfig.set(:http_400_plain_text, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 400
      assert response.body == "Bad Request: Invalid SOAP request format"
      assert parse_soap_fault_from_body(response.body) == {:error, :not_xml}
    end

    test "handles 401 Unauthorized without body", %{port: port} do
      ErrorConfig.set(:http_401_no_body, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 401
      assert response.body == ""
      assert has_www_authenticate_header?(response)
    end

    test "handles 403 Forbidden", %{port: port} do
      ErrorConfig.set(:http_403, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 403
      assert response.body == "Access forbidden"
    end

    test "handles 502 Bad Gateway with HTML body", %{port: port} do
      ErrorConfig.set(:http_502, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 502
      assert String.contains?(response.body, "502 Bad Gateway")
      # HTML may parse as XML but will not contain a SOAP fault
      result = parse_soap_fault_from_body(response.body)
      assert result in [{:error, :not_xml}, {:error, :no_fault_found}]
    end

    test "handles 503 Service Unavailable with Retry-After header", %{port: port} do
      ErrorConfig.set(:http_503, retry_after: "120")

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 503
      assert response.body == "Service temporarily unavailable"
      assert has_header?(response, "retry-after", "120")
    end

    test "handles 504 Gateway Timeout", %{port: port} do
      ErrorConfig.set(:http_504, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 504
      assert response.body == "Gateway timeout"
    end
  end

  # ============================================================================
  # Test: HTTP 500 with Malformed Fault
  # ============================================================================

  describe "HTTP 500 with Malformed Fault" do
    setup do
      start_test_server(:success, [])
    end

    test "handles invalid XML in response", %{port: port} do
      ErrorConfig.set(:http_500_invalid_xml, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert parse_soap_fault_from_body(response.body) == {:error, :parse_error}
    end

    test "handles partial/truncated XML", %{port: port} do
      ErrorConfig.set(:http_500_truncated_xml, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert parse_soap_fault_from_body(response.body) == {:error, :parse_error}
    end

    test "handles empty body with 500 status", %{port: port} do
      ErrorConfig.set(:http_500_empty_body, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert response.body == ""
      assert parse_soap_fault_from_body(response.body) == {:error, :not_xml}
    end

    test "handles HTML error page instead of SOAP fault", %{port: port} do
      ErrorConfig.set(:http_500_html_error, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert String.contains?(response.body, "Internal Server Error")
      assert String.contains?(response.body, "Error ID: ABC123")
      # HTML may parse as XML but will not contain a SOAP fault
      result = parse_soap_fault_from_body(response.body)
      assert result in [{:error, :not_xml}, {:error, :no_fault_found}]
    end
  end

  # ============================================================================
  # Test: SOAP Fault Detail Extraction
  # ============================================================================

  describe "SOAP Fault Detail Extraction" do
    setup do
      start_test_server(:success, [])
    end

    test "extracts simple string detail", %{port: port} do
      ErrorConfig.set(:soap_1_1_fault,
        fault_code: "Server",
        fault_string: "Error",
        detail: "Simple error message"
      )

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.detail == "Simple error message"
    end

    test "extracts complex nested XML detail", %{port: port} do
      ErrorConfig.set(:soap_fault_complex_detail, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert is_map(fault.detail)

      # Verify nested structure is preserved
      error_info = fault.detail["app:ErrorInfo"]
      assert is_map(error_info)
      assert error_info["app:ErrorCode"] == "APP_ERR_001"
      assert error_info["app:ErrorMessage"] == "Database connection failed"

      # Verify deeply nested elements
      context = error_info["app:Context"]
      assert is_map(context)
      assert context["app:Service"] == "UserService"
      assert context["app:RequestId"] == "req-12345"
    end

    test "extracts multiple detail elements", %{port: port} do
      ErrorConfig.set(:soap_fault_multiple_details, [])

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert response.status == 500
      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert fault.fault_code == "Client"
      assert fault.fault_string == "Validation failed"
      assert is_map(fault.detail)

      # Multiple ValidationError elements should be captured
      validation_errors = fault.detail["ValidationError"]
      assert validation_errors != nil
    end

    test "handles detail with map of key-value pairs", %{port: port} do
      ErrorConfig.set(:soap_1_1_fault,
        fault_code: "Server",
        fault_string: "Error",
        detail: %{
          "errorCode" => "ERR_001",
          "errorMessage" => "Something went wrong",
          "timestamp" => "2024-01-15T10:00:00Z"
        }
      )

      {:ok, response} = make_soap_request("http://localhost:#{port}/soap", build_test_request())

      assert {:ok, fault} = parse_soap_fault_from_body(response.body)
      assert is_map(fault.detail)
      assert fault.detail["errorCode"] == "ERR_001"
      assert fault.detail["errorMessage"] == "Something went wrong"
    end
  end

  # ============================================================================
  # Test: Error Recovery Detection
  # ============================================================================

  describe "Error Recovery Detection" do
    test "transport timeout errors are recoverable" do
      error = Error.transport_error(:timeout, %{message: "Request timed out"})
      assert Error.recoverable?(error) == true
    end

    test "transport connection_refused errors are recoverable" do
      error = Error.transport_error(:connection_refused, %{message: "Connection refused"})
      assert Error.recoverable?(error) == true
    end

    test "transport network_unreachable errors are recoverable" do
      error = Error.transport_error(:network_unreachable, %{message: "Network unreachable"})
      assert Error.recoverable?(error) == true
    end

    test "HTTP 500 errors are recoverable" do
      error = Error.http_error(500, "Internal Server Error", [])
      assert Error.recoverable?(error) == true
    end

    test "HTTP 502 errors are recoverable" do
      error = Error.http_error(502, "Bad Gateway", [])
      assert Error.recoverable?(error) == true
    end

    test "HTTP 503 errors are recoverable" do
      error = Error.http_error(503, "Service Unavailable", [])
      assert Error.recoverable?(error) == true
    end

    test "HTTP 504 errors are recoverable" do
      error = Error.http_error(504, "Gateway Timeout", [])
      assert Error.recoverable?(error) == true
    end

    test "HTTP 400 errors are NOT recoverable" do
      error = Error.http_error(400, "Bad Request", [])
      assert Error.recoverable?(error) == false
    end

    test "HTTP 401 errors are NOT recoverable" do
      error = Error.http_error(401, "Unauthorized", [])
      assert Error.recoverable?(error) == false
    end

    test "HTTP 403 errors are NOT recoverable" do
      error = Error.http_error(403, "Forbidden", [])
      assert Error.recoverable?(error) == false
    end

    test "HTTP 404 errors are NOT recoverable" do
      error = Error.http_error(404, "Not Found", [])
      assert Error.recoverable?(error) == false
    end

    test "SOAP faults with Server fault code are recoverable" do
      fault = %{fault_code: "Server", fault_string: "Internal error"}
      assert Error.recoverable?(fault) == true
    end

    test "SOAP faults with Client fault code are NOT recoverable" do
      fault = %{fault_code: "Client", fault_string: "Invalid request"}
      assert Error.recoverable?(fault) == false
    end

    test "validation errors are NOT recoverable" do
      error = Error.validation_error("email", :invalid_format, %{})
      assert Error.recoverable?(error) == false
    end

    test "WSDL errors are NOT recoverable" do
      error = Error.wsdl_error(:invalid_wsdl, %{})
      assert Error.recoverable?(error) == false
    end
  end

  # ============================================================================
  # Test: DynamicClient Error Handling
  # ============================================================================

  describe "DynamicClient Error Handling" do
    setup do
      start_test_server(:success, [])
    end

    test "DynamicClient returns error on HTTP 500 with SOAP fault", %{base_url: base_url} do
      {:ok, client} = DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      # Configure server to return SOAP fault
      ErrorConfig.set(:soap_1_1_fault,
        fault_code: "Server",
        fault_string: "Operation failed"
      )

      result = DynamicClient.call(client, "TestOperation", %{"request_type" => "test"})

      assert {:error, error} = result
      assert is_map(error) or is_tuple(error)
    end

    test "DynamicClient handles HTTP 400 errors", %{base_url: base_url} do
      {:ok, client} = DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      ErrorConfig.set(:http_400_plain_text, [])

      result = DynamicClient.call(client, "TestOperation", %{"request_type" => "test"})

      assert {:error, _error} = result
    end

    test "DynamicClient handles HTTP 401 errors", %{base_url: base_url} do
      {:ok, client} = DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      ErrorConfig.set(:http_401_no_body, [])

      result = DynamicClient.call(client, "TestOperation", %{"request_type" => "test"})

      assert {:error, _error} = result
    end

    test "DynamicClient handles HTTP 503 errors", %{base_url: base_url} do
      {:ok, client} = DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      ErrorConfig.set(:http_503, [])

      result = DynamicClient.call(client, "TestOperation", %{"request_type" => "test"})

      assert {:error, _error} = result
    end

    test "DynamicClient handles malformed XML responses", %{base_url: base_url} do
      {:ok, client} = DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      ErrorConfig.set(:http_500_invalid_xml, [])

      result = DynamicClient.call(client, "TestOperation", %{"request_type" => "test"})

      assert {:error, _error} = result
    end

    test "DynamicClient handles HTML error pages", %{base_url: base_url} do
      {:ok, client} = DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      ErrorConfig.set(:http_500_html_error, [])

      result = DynamicClient.call(client, "TestOperation", %{"request_type" => "test"})

      assert {:error, _error} = result
    end

    test "DynamicClient successful call after error configuration reset", %{base_url: base_url} do
      {:ok, client} = DynamicClient.new("#{base_url}?wsdl", timeout: 5000)

      # First, configure an error
      ErrorConfig.set(:http_500_html_error, [])
      assert {:error, _} = DynamicClient.call(client, "TestOperation", %{"request_type" => "test"})

      # Then reset to success
      ErrorConfig.set(:success, [])
      result = DynamicClient.call(client, "TestOperation", %{"request_type" => "success"})

      assert {:ok, response} = result
      assert Map.has_key?(response, "result")
    end
  end

  # ============================================================================
  # Test: Error Formatting
  # ============================================================================

  describe "Error Formatting" do
    test "formats SOAP fault error as string" do
      fault = %{
        fault_code: "Server",
        fault_string: "Internal server error",
        fault_actor: "http://example.com/service",
        detail: %{"code" => "ERR_001"}
      }

      formatted = Error.format_error(fault)

      assert is_binary(formatted)
      assert String.contains?(formatted, "SOAP Fault")
      assert String.contains?(formatted, "Server")
      assert String.contains?(formatted, "Internal server error")
    end

    test "formats HTTP error as string" do
      error = Error.http_error(503, "Service Unavailable", [{"retry-after", "120"}])

      formatted = Error.format_error(error)

      assert is_binary(formatted)
      assert String.contains?(formatted, "HTTP Error")
      assert String.contains?(formatted, "503")
    end

    test "formats transport error as string" do
      error = Error.transport_error(:timeout, %{timeout_ms: 30000})

      formatted = Error.format_error(error)

      assert is_binary(formatted)
      assert String.contains?(formatted, "Transport Error")
      assert String.contains?(formatted, "timeout")
    end

    test "formats validation error as string" do
      error = Error.validation_error("email", :invalid_format, %{expected: "email format"})

      formatted = Error.format_error(error)

      assert is_binary(formatted)
      assert String.contains?(formatted, "Validation Error")
      assert String.contains?(formatted, "email")
    end

    test "formats error as map when requested" do
      error = Error.http_error(500, "Error", [])

      formatted = Error.format_error(error, format: :map)

      assert is_map(formatted)
      assert formatted.type == :http_error
      assert formatted.status == 500
    end
  end

  # ============================================================================
  # Test: Debug Context Extraction
  # ============================================================================

  describe "Debug Context Extraction" do
    test "extracts debug context from SOAP fault" do
      fault = %{
        fault_code: "Server",
        fault_string: "Error occurred"
      }

      context = Error.extract_debug_context(fault)

      assert Map.has_key?(context, :timestamp)
      assert context.error_type == :soap_fault
      assert context.fault_code == "Server"
    end

    test "extracts debug context from HTTP error" do
      error = Error.http_error(500, "Error", [])

      context = Error.extract_debug_context(error)

      assert Map.has_key?(context, :timestamp)
      assert context.error_type == :http_error
      assert context.structured_type == :http_error
    end

    test "extracts debug context from transport error" do
      error = Error.transport_error(:timeout, %{timeout_ms: 30000})

      context = Error.extract_debug_context(error)

      assert Map.has_key?(context, :timestamp)
      assert context.error_type == :transport_error
      assert context.details == %{timeout_ms: 30000}
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp start_test_server(error_type, opts) do
    {:ok, _} = Application.ensure_all_started(:lather)

    port = Enum.random(10000..60000)
    ErrorConfig.set(error_type, opts)
    {:ok, server_pid} = Bandit.start_link(plug: FaultTestRouter, port: port, scheme: :http)

    on_exit(fn ->
      try do
        GenServer.stop(server_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    Process.sleep(50)

    {:ok, port: port, base_url: "http://localhost:#{port}/soap", server_pid: server_pid}
  end

  defp make_soap_request(url, body) do
    headers = [{"content-type", "text/xml; charset=utf-8"}, {"soapaction", "TestOperation"}]
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, Lather.Finch) do
      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body, headers: response.headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_test_request do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                   xmlns:tns="http://test.example.com/faulttest">
      <soap:Body>
        <tns:TestOperation>
          <request_type>test</request_type>
        </tns:TestOperation>
      </soap:Body>
    </soap:Envelope>
    """
  end

  defp parse_soap_fault_from_body(""), do: {:error, :not_xml}

  defp parse_soap_fault_from_body(body) when is_binary(body) do
    # Check if body looks like XML
    unless String.starts_with?(String.trim(body), "<") do
      {:error, :not_xml}
    else
      case Lather.Xml.Parser.parse(body) do
        {:ok, parsed} ->
          extract_soap_1_1_fault(parsed)

        {:error, _} ->
          {:error, :parse_error}
      end
    end
  end

  defp extract_soap_1_1_fault(parsed) do
    fault =
      get_in(parsed, ["Envelope", "Body", "Fault"]) ||
        get_in(parsed, ["soap:Envelope", "soap:Body", "soap:Fault"]) ||
        get_in(parsed, ["SOAP-ENV:Envelope", "SOAP-ENV:Body", "SOAP-ENV:Fault"]) ||
        get_in(parsed, ["s:Envelope", "s:Body", "s:Fault"]) ||
        get_in(parsed, ["env:Envelope", "env:Body", "env:Fault"])

    if fault && is_map(fault) do
      fault_info = %{
        fault_code:
          extract_text_content(
            Map.get(fault, "faultcode") || Map.get(fault, "soap:faultcode") || ""
          ),
        fault_string:
          extract_text_content(
            Map.get(fault, "faultstring") || Map.get(fault, "soap:faultstring") || ""
          ),
        fault_actor:
          extract_text_content(
            Map.get(fault, "faultactor") || Map.get(fault, "soap:faultactor") || ""
          ),
        detail: extract_detail_content(Map.get(fault, "detail") || Map.get(fault, "soap:detail"))
      }

      {:ok, fault_info}
    else
      {:error, :no_fault_found}
    end
  end

  defp parse_soap_1_2_fault_from_body(body) when is_binary(body) do
    case Lather.Xml.Parser.parse(body) do
      {:ok, parsed} ->
        extract_soap_1_2_fault(parsed)

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  defp extract_soap_1_2_fault(parsed) do
    fault = get_in(parsed, ["soap:Envelope", "soap:Body", "soap:Fault"])

    if fault && is_map(fault) do
      code = get_in(fault, ["soap:Code", "soap:Value"])
      subcode = get_in(fault, ["soap:Code", "soap:Subcode", "soap:Value"])
      reason = get_in(fault, ["soap:Reason", "soap:Text"])
      detail = fault["soap:Detail"]

      fault_info = %{
        code: extract_text_content(code || ""),
        subcode: extract_text_content(subcode || ""),
        reason: extract_text_content(reason || ""),
        detail: detail
      }

      {:ok, fault_info}
    else
      {:error, :no_fault_found}
    end
  end

  defp extract_text_content(value) when is_map(value) do
    Map.get(value, "#text", "")
  end

  defp extract_text_content(value) when is_binary(value) do
    value
  end

  defp extract_text_content(_) do
    ""
  end

  defp extract_detail_content(nil), do: nil

  defp extract_detail_content(detail) when is_binary(detail), do: detail

  defp extract_detail_content(detail) when is_map(detail) do
    # If detail has only #text, return the text
    case Map.keys(detail) do
      ["#text"] -> detail["#text"]
      _ -> detail
    end
  end

  defp has_www_authenticate_header?(response) do
    Enum.any?(response.headers, fn {name, _value} ->
      String.downcase(name) == "www-authenticate"
    end)
  end

  defp has_header?(response, header_name, expected_value) do
    Enum.any?(response.headers, fn {name, value} ->
      String.downcase(name) == String.downcase(header_name) && value == expected_value
    end)
  end
end
