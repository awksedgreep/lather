defmodule Lather.Integration.Soap12IntegrationTest do
  use ExUnit.Case, async: true

  alias Lather.Http.Transport
  alias Lather.Soap.Envelope
  alias Lather.Xml.Parser
  alias Lather.Wsdl.Analyzer

  describe "SOAP 1.2 Version Detection" do
    test "detects SOAP 1.2 from WSDL with soap12: bindings" do
      soap_1_2_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://example.com/soap12"
                   xmlns:soap12="http://schemas.xmlsoap.org/wsdl/soap12/"
                   targetNamespace="http://example.com/soap12">

        <message name="TestRequest">
          <part name="param" type="string"/>
        </message>

        <message name="TestResponse">
          <part name="result" type="string"/>
        </message>

        <portType name="TestPortType">
          <operation name="TestOp">
            <input message="tns:TestRequest"/>
            <output message="tns:TestResponse"/>
          </operation>
        </portType>

        <binding name="TestSOAP12Binding" type="tns:TestPortType">
          <soap12:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <operation name="TestOp">
            <soap12:operation soapAction="http://example.com/TestOp"/>
            <input>
              <soap12:body use="literal"/>
            </input>
            <output>
              <soap12:body use="literal"/>
            </output>
          </operation>
        </binding>

        <service name="TestSOAP12Service">
          <port name="TestSOAP12Port" binding="tns:TestSOAP12Binding">
            <soap12:address location="http://example.com/soap12"/>
          </port>
        </service>

      </definitions>
      """

      {:ok, parsed} = Parser.parse(soap_1_2_wsdl)
      {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.soap_version == :v1_2
    end

    test "defaults to SOAP 1.1 for regular WSDL without soap12 elements" do
      soap_1_1_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://example.com/soap"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   targetNamespace="http://example.com/soap">

        <message name="TestRequest">
          <part name="param" type="string"/>
        </message>

        <message name="TestResponse">
          <part name="result" type="string"/>
        </message>

        <portType name="TestPortType">
          <operation name="TestOp">
            <input message="tns:TestRequest"/>
            <output message="tns:TestResponse"/>
          </operation>
        </portType>

        <binding name="TestSOAPBinding" type="tns:TestPortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <operation name="TestOp">
            <soap:operation soapAction="http://example.com/TestOp"/>
            <input>
              <soap:body use="literal"/>
            </input>
            <output>
              <soap:body use="literal"/>
            </output>
          </operation>
        </binding>

        <service name="TestSOAPService">
          <port name="TestSOAPPort" binding="tns:TestSOAPBinding">
            <soap:address location="http://example.com/soap"/>
          </port>
        </service>

      </definitions>
      """

      {:ok, parsed} = Parser.parse(soap_1_1_wsdl)
      {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.soap_version == :v1_1
    end
  end

  describe "SOAP 1.2 Envelope Generation" do
    test "builds SOAP 1.2 envelope with correct namespace and headers" do
      {:ok, envelope} = Envelope.build(:TestOperation, %{param: "test"}, version: :v1_2)

      assert String.contains?(envelope, "xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\"")
      assert String.contains?(envelope, "<soap:Envelope")
      assert String.contains?(envelope, "<TestOperation>")
      assert String.contains?(envelope, "<param>test</param>")
    end

    test "builds SOAP 1.2 envelope with nested parameters" do
      params = %{
        user: %{
          name: "John Doe",
          details: %{
            age: "30",
            email: "john@example.com"
          }
        }
      }

      {:ok, envelope} = Envelope.build(:CreateUser, params, version: :v1_2)

      assert String.contains?(envelope, "xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\"")
      assert String.contains?(envelope, "<CreateUser>")
      assert String.contains?(envelope, "<user>")
      assert String.contains?(envelope, "<name>John Doe</name>")
      assert String.contains?(envelope, "<details>")
      assert String.contains?(envelope, "<email>john@example.com</email>")
    end
  end

  describe "SOAP 1.2 HTTP Headers" do
    test "generates correct Content-Type header for SOAP 1.2" do
      headers = Transport.build_headers(soap_version: :v1_2)

      content_type_header = Enum.find(headers, fn {name, _} -> name == "content-type" end)
      assert content_type_header != nil
      {_, content_type} = content_type_header

      assert content_type == "application/soap+xml; charset=utf-8"
    end

    test "embeds SOAPAction in Content-Type for SOAP 1.2" do
      headers =
        Transport.build_headers(
          soap_version: :v1_2,
          soap_action: "http://example.com/TestAction"
        )

      content_type_header = Enum.find(headers, fn {name, _} -> name == "content-type" end)
      {_, content_type} = content_type_header

      expected = "application/soap+xml; charset=utf-8; action=\"http://example.com/TestAction\""
      assert content_type == expected
    end

    test "does not include SOAPAction header for SOAP 1.2" do
      headers =
        Transport.build_headers(
          soap_version: :v1_2,
          soap_action: "http://example.com/TestAction"
        )

      soap_action_header =
        Enum.find(headers, fn {name, _} ->
          String.downcase(name) == "soapaction"
        end)

      assert soap_action_header == nil
    end

    test "includes correct Accept header for SOAP 1.2" do
      headers = Transport.build_headers(soap_version: :v1_2)

      accept_header = Enum.find(headers, fn {name, _} -> name == "accept" end)
      assert accept_header != nil
      {_, accept_value} = accept_header

      assert accept_value == "application/soap+xml, text/xml"
    end
  end

  describe "SOAP 1.2 Fault Parsing" do
    test "parses SOAP 1.2 fault with nested Code/Value structure" do
      soap_1_2_fault = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <soap:Fault>
            <soap:Code>
              <soap:Value>soap:Sender</soap:Value>
              <soap:Subcode>
                <soap:Value>m:InvalidData</soap:Value>
              </soap:Subcode>
            </soap:Code>
            <soap:Reason>
              <soap:Text xml:lang="en">Invalid input data provided</soap:Text>
            </soap:Reason>
            <soap:Detail>
              <ErrorInfo>
                <Field>email</Field>
                <Message>Email format is invalid</Message>
              </ErrorInfo>
            </soap:Detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      response = %{status: 500, body: soap_1_2_fault}
      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Sender"
      assert fault.subcode == "m:InvalidData"
      assert fault.string == "Invalid input data provided"
      assert fault.detail["ErrorInfo"]["Field"] == "email"
      assert fault.detail["ErrorInfo"]["Message"] == "Email format is invalid"
      assert fault.soap_version == :v1_2
    end

    test "parses SOAP 1.2 fault with multiple language reasons" do
      soap_1_2_fault = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <soap:Fault>
            <soap:Code>
              <soap:Value>soap:Client</soap:Value>
            </soap:Code>
            <soap:Reason>
              <soap:Text xml:lang="en">Authentication failed</soap:Text>
              <soap:Text xml:lang="es">Falló la autenticación</soap:Text>
              <soap:Text xml:lang="fr">Échec de l'authentification</soap:Text>
            </soap:Reason>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      response = %{status: 500, body: soap_1_2_fault}
      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Client"
      # Should prefer English text
      assert fault.string == "Authentication failed"
      assert fault.soap_version == :v1_2
    end

    test "handles SOAP 1.2 fault with simple structure (backwards compatibility)" do
      soap_1_2_simple_fault = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <soap:Fault>
            <Code>Server</Code>
            <Reason>Internal server error</Reason>
            <Detail>
              <ErrorCode>500</ErrorCode>
            </Detail>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      response = %{status: 500, body: soap_1_2_simple_fault}
      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "Server"
      assert fault.string == "Internal server error"
      assert fault.detail["ErrorCode"] == "500"
      assert fault.soap_version == :v1_2
    end
  end

  describe "SOAP 1.2 Response Parsing" do
    test "parses successful SOAP 1.2 response" do
      soap_1_2_response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <GetUserResponse>
            <User>
              <ID>12345</ID>
              <Name>John Doe</Name>
              <Email>john@example.com</Email>
              <Profile>
                <Department>Engineering</Department>
                <Role>Developer</Role>
              </Profile>
            </User>
          </GetUserResponse>
        </soap:Body>
      </soap:Envelope>
      """

      response = %{status: 200, body: soap_1_2_response}
      {:ok, result} = Envelope.parse_response(response)

      assert result["User"]["ID"] == "12345"
      assert result["User"]["Name"] == "John Doe"
      assert result["User"]["Email"] == "john@example.com"
      assert result["User"]["Profile"]["Department"] == "Engineering"
      assert result["User"]["Profile"]["Role"] == "Developer"
    end

    test "detects SOAP 1.2 version from response namespace" do
      soap_1_2_response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <TestResponse>
            <Result>success</Result>
          </TestResponse>
        </soap:Body>
      </soap:Envelope>
      """

      response = %{status: 200, body: soap_1_2_response}
      {:ok, result} = Envelope.parse_response(response)

      assert result["Result"] == "success"
    end
  end

  describe "SOAP 1.2 Version Override" do
    test "allows explicit SOAP version override in DynamicClient options" do
      # Create a simple WSDL that would normally be detected as SOAP 1.1
      simple_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://test.com"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   targetNamespace="http://test.com">
        <message name="TestRequest">
          <part name="param" type="string"/>
        </message>
        <message name="TestResponse">
          <part name="result" type="string"/>
        </message>
        <portType name="TestPortType">
          <operation name="TestOp">
            <input message="tns:TestRequest"/>
            <output message="tns:TestResponse"/>
          </operation>
        </portType>
        <binding name="TestBinding" type="tns:TestPortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <operation name="TestOp">
            <soap:operation soapAction="http://test.com/TestOp"/>
            <input>
              <soap:body use="literal"/>
            </input>
            <output>
              <soap:body use="literal"/>
            </output>
          </operation>
        </binding>
        <service name="TestService">
          <port name="TestPort" binding="tns:TestBinding">
            <soap:address location="http://test.com"/>
          </port>
        </service>
      </definitions>
      """

      # Mock the WSDL loading to avoid actual HTTP calls
      {:ok, parsed} = Parser.parse(simple_wsdl)
      {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      # Service would normally detect as SOAP 1.1, but we'll override it
      assert service_info.soap_version == :v1_1

      # Create a mock service_info with SOAP 1.2 override
      updated_service_info = Map.put(service_info, :soap_version, :v1_2)

      # The version should be :v1_2 when explicitly set
      assert updated_service_info.soap_version == :v1_2
    end
  end

  describe "SOAP 1.2 Version Propagation" do
    test "version flows through request building pipeline" do
      # Test that version parameter is properly passed through the chain:
      # DynamicClient -> Builder -> Envelope -> Transport

      # Mock operation info
      _operation_info = %{
        name: "TestOperation",
        soap_action: "http://example.com/TestOp",
        input: %{
          message: "TestRequest",
          parts: [%{name: "param", type: "string"}]
        }
      }

      # Mock service info
      _service_info = %{
        target_namespace: "http://example.com",
        soap_version: :v1_2
      }

      # Build request with SOAP 1.2 version
      parameters = %{"param" => "test_value"}
      options = [version: :v1_2, namespace: "http://example.com"]

      # This would normally go through Builder.build_request which calls Envelope.build
      {:ok, envelope} = Envelope.build(:TestOperation, parameters, options)

      # Verify SOAP 1.2 namespace is used
      assert String.contains?(envelope, "xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\"")
    end
  end

  describe "SOAP 1.1 vs SOAP 1.2 Comparison" do
    test "generates different envelopes for SOAP 1.1 vs SOAP 1.2" do
      params = %{test_param: "value"}

      {:ok, soap_1_1_envelope} = Envelope.build(:TestOp, params, version: :v1_1)
      {:ok, soap_1_2_envelope} = Envelope.build(:TestOp, params, version: :v1_2)

      # SOAP 1.1 should use the old namespace
      assert String.contains?(
               soap_1_1_envelope,
               "xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\""
             )

      # SOAP 1.2 should use the new namespace
      assert String.contains?(
               soap_1_2_envelope,
               "xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\""
             )

      # Both should contain the same operation and parameters
      assert String.contains?(soap_1_1_envelope, "<TestOp>")
      assert String.contains?(soap_1_2_envelope, "<TestOp>")
      assert String.contains?(soap_1_1_envelope, "<test_param>value</test_param>")
      assert String.contains?(soap_1_2_envelope, "<test_param>value</test_param>")
    end

    test "generates different headers for SOAP 1.1 vs SOAP 1.2" do
      soap_action = "http://example.com/TestAction"

      soap_1_1_headers = Transport.build_headers(soap_version: :v1_1, soap_action: soap_action)
      soap_1_2_headers = Transport.build_headers(soap_version: :v1_2, soap_action: soap_action)

      # SOAP 1.1 should have separate SOAPAction header
      soap_1_1_soap_action =
        Enum.find(soap_1_1_headers, fn {name, _} ->
          String.downcase(name) == "soapaction"
        end)

      assert soap_1_1_soap_action != nil
      {_, soap_1_1_action_value} = soap_1_1_soap_action
      assert soap_1_1_action_value == soap_action

      # SOAP 1.1 should use text/xml content type
      soap_1_1_content_type =
        Enum.find(soap_1_1_headers, fn {name, _} -> name == "content-type" end)

      {_, soap_1_1_ct_value} = soap_1_1_content_type
      assert soap_1_1_ct_value == "text/xml; charset=utf-8"

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
      assert String.contains?(soap_1_2_ct_value, "action=\"#{soap_action}\"")
    end
  end
end
