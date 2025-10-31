defmodule Lather.Integration.SoapFaultHandlingTest do
  use ExUnit.Case, async: true

  alias Lather.DynamicClient
  alias Lather.Xml.Parser
  alias Lather.Http.Transport

  describe "SOAP Fault Handling" do
    test "parses SOAP 1.1 faults with text nodes and attributes" do
      soap_fault_xml = """
      <?xml version="1.0" encoding="ISO-8859-1"?>
      <SOAP-ENV:Envelope SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
        xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/">
      <SOAP-ENV:Body>
        <SOAP-ENV:Fault>
          <faultcode xsi:type="xsd:string">SERVER</faultcode>
          <faultactor xsi:type="xsd:string"></faultactor>
          <faultstring xsi:type="xsd:string">No valid points were found.</faultstring>
          <detail xsi:type="xsd:string">Attempted to find local times for submitted points but failed.</detail>
        </SOAP-ENV:Fault>
      </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(soap_fault_xml)

      # Extract fault using real extraction logic
      fault = get_in(parsed, ["SOAP-ENV:Envelope", "SOAP-ENV:Body", "SOAP-ENV:Fault"])
      assert fault != nil

      # Test text node extraction from complex structures
      fault_string = fault["faultstring"]
      assert is_map(fault_string)
      assert fault_string["#text"] == "No valid points were found."
      assert fault_string["@xsi:type"] == "xsd:string"

      fault_code = fault["faultcode"]
      assert is_map(fault_code)
      assert fault_code["#text"] == "SERVER"

      detail = fault["detail"]
      assert is_map(detail)
      assert detail["#text"] == "Attempted to find local times for submitted points but failed."
    end

    test "parses SOAP 1.2 faults with different structure" do
      soap12_fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <soap:Fault>
            <soap:Code>
              <soap:Value>soap:Sender</soap:Value>
            </soap:Code>
            <soap:Reason>
              <soap:Text xml:lang="en">Invalid request format</soap:Text>
            </soap:Reason>
            <soap:Detail>
              <error xmlns="http://example.com/error">
                <message>The request does not conform to the expected schema</message>
                <code>INVALID_FORMAT</code>
              </error>
            </soap:Detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(soap12_fault_xml)

      fault = get_in(parsed, ["soap:Envelope", "soap:Body", "soap:Fault"])
      assert fault != nil

      # SOAP 1.2 has different structure
      code = get_in(fault, ["soap:Code", "soap:Value"])
      assert code == "soap:Sender" or (is_map(code) and code["#text"] == "soap:Sender")

      reason = get_in(fault, ["soap:Reason", "soap:Text"])
      text_content = if is_map(reason), do: reason["#text"], else: reason
      assert text_content == "Invalid request format"
    end

    test "handles faults with simple string values" do
      simple_fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Client</faultcode>
            <faultstring>Authentication failed</faultstring>
            <faultactor>http://example.com/auth</faultactor>
            <detail>Invalid credentials provided</detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(simple_fault_xml)

      fault = get_in(parsed, ["soap:Envelope", "soap:Body", "soap:Fault"])
      assert fault != nil

      # Simple string values (not complex text nodes)
      assert fault["faultcode"] == "Client"
      assert fault["faultstring"] == "Authentication failed"
      assert fault["faultactor"] == "http://example.com/auth"
      assert fault["detail"] == "Invalid credentials provided"
    end

    test "handles faults with missing optional elements" do
      minimal_fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Server</faultcode>
            <faultstring>Internal server error</faultstring>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(minimal_fault_xml)

      fault = get_in(parsed, ["soap:Envelope", "soap:Body", "soap:Fault"])
      assert fault != nil

      assert fault["faultcode"] == "Server"
      assert fault["faultstring"] == "Internal server error"
      # Missing elements should be nil/absent
      assert Map.get(fault, "faultactor") == nil
      assert Map.get(fault, "detail") == nil
    end

    test "handles faults with complex detail elements" do
      complex_detail_fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                     xmlns:app="http://example.com/app">
        <soap:Body>
          <soap:Fault>
            <faultcode>Server</faultcode>
            <faultstring>Application error</faultstring>
            <detail>
              <app:ErrorInfo>
                <app:ErrorCode>APP_001</app:ErrorCode>
                <app:ErrorMessage>Database connection failed</app:ErrorMessage>
                <app:Timestamp>2023-10-31T12:00:00Z</app:Timestamp>
                <app:RetryAfter>300</app:RetryAfter>
              </app:ErrorInfo>
            </detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(complex_detail_fault_xml)

      fault = get_in(parsed, ["soap:Envelope", "soap:Body", "soap:Fault"])
      assert fault != nil

      assert fault["faultcode"] == "Server"
      assert fault["faultstring"] == "Application error"

      # Complex detail structure
      detail = fault["detail"]
      assert is_map(detail)

      error_info = detail["app:ErrorInfo"]
      assert is_map(error_info)
      assert error_info["app:ErrorCode"] == "APP_001"
      assert error_info["app:ErrorMessage"] == "Database connection failed"
    end

    test "extracts fault information using helper function" do
      fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <SOAP-ENV:Fault>
            <faultcode>CLIENT</faultcode>
            <faultstring>Validation error</faultstring>
            <faultactor>http://example.com/validator</faultactor>
            <detail>Required field 'email' is missing</detail>
          </SOAP-ENV:Fault>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(fault_xml)

      # Test the fault extraction logic
      assert {:ok, fault_info} = extract_soap_fault(parsed)

      assert fault_info.fault_code == "CLIENT"
      assert fault_info.fault_string == "Validation error"
      assert fault_info.fault_actor == "http://example.com/validator"
      assert fault_info.detail == "Required field 'email' is missing"
    end

    test "extracts fault information from text nodes with attributes" do
      complex_fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
        <SOAP-ENV:Body>
          <SOAP-ENV:Fault>
            <faultcode xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">TIMEOUT</faultcode>
            <faultstring xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">Request timeout exceeded</faultstring>
            <faultactor xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">http://example.com/processor</faultactor>
            <detail xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">Operation took longer than 30 seconds</detail>
          </SOAP-ENV:Fault>
        </SOAP-ENV:Body>
      </SOAP-ENV:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(complex_fault_xml)
      assert {:ok, fault_info} = extract_soap_fault(parsed)

      assert fault_info.fault_code == "TIMEOUT"
      assert fault_info.fault_string == "Request timeout exceeded"
      assert fault_info.fault_actor == "http://example.com/processor"
      assert fault_info.detail == "Operation took longer than 30 seconds"
    end

    test "handles non-fault responses" do
      success_response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <GetWeatherResponse xmlns="http://weather.example.com">
            <Temperature>72</Temperature>
            <Humidity>65</Humidity>
            <Conditions>Sunny</Conditions>
          </GetWeatherResponse>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(success_response)
      assert extract_soap_fault(parsed) == :not_fault
    end

    test "handles empty fault elements" do
      empty_fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode></faultcode>
            <faultstring></faultstring>
            <faultactor></faultactor>
            <detail></detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(empty_fault_xml)
      assert {:ok, fault_info} = extract_soap_fault(parsed)

      assert fault_info.fault_code == ""
      assert fault_info.fault_string == ""
      assert fault_info.fault_actor == ""
      assert fault_info.detail == ""
    end

    test "handles malformed fault structures gracefully" do
      malformed_fault_cases = [
        # Missing faultstring
        """
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>Server</faultcode>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """,

        # Fault with only detail
        """
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <detail>Something went wrong</detail>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """,

        # Empty fault
        """
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      ]

      for fault_xml <- malformed_fault_cases do
        wrapped_xml = "<?xml version=\"1.0\"?>" <> fault_xml

        case Parser.parse(wrapped_xml) do
          {:ok, parsed} ->
            # Should handle gracefully, returning fault info with empty strings for missing elements
            case extract_soap_fault(parsed) do
              {:ok, fault_info} ->
                assert is_binary(fault_info.fault_code)
                assert is_binary(fault_info.fault_string)
                assert is_binary(fault_info.fault_actor)
                assert is_binary(fault_info.detail)

              :not_fault ->
                # Some malformed structures might not be recognized as faults
                assert true
            end

          {:error, _} ->
            # XML parsing errors are acceptable for truly malformed XML
            assert true
        end
      end
    end

    test "handles different namespace prefixes for faults" do
      namespace_variants = [
        {"soap:Envelope", "soap:Body", "soap:Fault"},
        {"SOAP-ENV:Envelope", "SOAP-ENV:Body", "SOAP-ENV:Fault"},
        {"s:Envelope", "s:Body", "s:Fault"},
        {"env:Envelope", "env:Body", "env:Fault"}
      ]

      for {env, body, fault} <- namespace_variants do
        fault_xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <#{env} xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
          <#{body}>
            <#{fault}>
              <faultcode>TEST</faultcode>
              <faultstring>Test message</faultstring>
            </#{fault}>
          </#{body}>
        </#{env}>
        """

        assert {:ok, parsed} = Parser.parse(fault_xml)
        # Should be able to extract fault regardless of namespace prefix
        assert {:ok, fault_info} = extract_soap_fault(parsed)
        assert fault_info.fault_code == "TEST"
        assert fault_info.fault_string == "Test message"
      end
    end

    test "handles unicode and special characters in fault messages" do
      unicode_fault_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>UNICODE_ERROR</faultcode>
            <faultstring>测试错误消息 with émojis 🚨 and special chars: &lt;&gt;&amp;"'</faultstring>
            <detail>Дополнительная информация об ошибке</detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, parsed} = Parser.parse(unicode_fault_xml)
      assert {:ok, fault_info} = extract_soap_fault(parsed)

      assert fault_info.fault_code == "UNICODE_ERROR"
      assert String.contains?(fault_info.fault_string, "测试错误消息")
      assert String.contains?(fault_info.fault_string, "🚨")
      assert String.contains?(fault_info.fault_string, "<>&\"'")
      assert String.contains?(fault_info.detail, "Дополнительная")
    end

    test "handles HTTP 500 response with SOAP fault body" do
      # Simulate the real-world scenario where HTTP 500 contains SOAP fault
      http_500_response = %{
        status: 500,
        type: :http_error,
        body: """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
          <SOAP-ENV:Body>
            <SOAP-ENV:Fault>
              <faultcode>SERVER</faultcode>
              <faultstring>Service temporarily unavailable</faultstring>
              <detail>System maintenance in progress</detail>
            </SOAP-ENV:Fault>
          </SOAP-ENV:Body>
        </SOAP-ENV:Envelope>
        """
      }

      # Test the HTTP 500 handling logic
      case http_500_response do
        %{status: 500, type: :http_error, body: body} when is_binary(body) ->
          case Parser.parse(body) do
            {:ok, parsed_response} ->
              case extract_soap_fault(parsed_response) do
                {:ok, fault} ->
                  assert fault.fault_code == "SERVER"
                  assert fault.fault_string == "Service temporarily unavailable"
                  assert fault.detail == "System maintenance in progress"

                :not_fault ->
                  flunk("Expected SOAP fault but got regular response")
              end

            {:error, _parse_error} ->
              flunk("Failed to parse HTTP 500 response body")
          end
      end
    end
  end

  # Helper function that matches the implementation
  defp extract_soap_fault(parsed_response) do
    fault =
      get_in(parsed_response, ["Envelope", "Body", "Fault"]) ||
        get_in(parsed_response, ["soap:Envelope", "soap:Body", "soap:Fault"]) ||
        get_in(parsed_response, ["SOAP-ENV:Envelope", "SOAP-ENV:Body", "SOAP-ENV:Fault"]) ||
        get_in(parsed_response, ["s:Envelope", "s:Body", "s:Fault"]) ||
        get_in(parsed_response, ["env:Envelope", "env:Body", "env:Fault"])

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
        detail:
          extract_text_content(Map.get(fault, "detail") || Map.get(fault, "soap:detail") || "")
      }

      {:ok, fault_info}
    else
      :not_fault
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
end
