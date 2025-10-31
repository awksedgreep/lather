defmodule Lather.Integration.WsdlParsingEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Lather.Wsdl.Analyzer
  alias Lather.Xml.Parser

  describe "WSDL Parsing Edge Cases" do
    test "parses WSDL with localhost endpoints (should trigger fallback)" do
      wsdl_with_localhost = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://example.com/service"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   targetNamespace="http://example.com/service">
        <service name="TestService">
          <port name="TestPort" binding="tns:TestBinding">
            <soap:address location="http://localhost:8080/service"/>
          </port>
        </service>
      </definitions>
      """

      assert {:ok, parsed} = Parser.parse(wsdl_with_localhost)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      # Should have localhost endpoint
      assert length(service_info.endpoints) == 1
      endpoint = List.first(service_info.endpoints)
      assert String.contains?(endpoint.address.location, "localhost")
    end

    test "parses WSDL with mixed namespace prefixes" do
      mixed_namespace_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
                        xmlns:tns="http://example.com/service"
                        xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                        targetNamespace="http://example.com/service">
        <wsdl:types>
          <xsd:schema targetNamespace="http://example.com/service">
            <xsd:element name="TestRequest">
              <xsd:complexType>
                <xsd:sequence>
                  <xsd:element name="param1" type="xsd:string"/>
                  <xsd:element name="param2" type="tns:CustomType"/>
                </xsd:sequence>
              </xsd:complexType>
            </xsd:element>
          </xsd:schema>
        </wsdl:types>

        <wsdl:message name="TestRequestMessage">
          <wsdl:part name="parameters" element="tns:TestRequest"/>
        </wsdl:message>

        <wsdl:message name="TestResponseMessage">
          <wsdl:part name="parameters" type="xsd:string"/>
        </wsdl:message>

        <wsdl:portType name="TestPortType">
          <wsdl:operation name="TestOperation">
            <wsdl:input message="tns:TestRequestMessage"/>
            <wsdl:output message="tns:TestResponseMessage"/>
          </wsdl:operation>
        </wsdl:portType>

        <wsdl:binding name="TestBinding" type="tns:TestPortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <wsdl:operation name="TestOperation">
            <soap:operation soapAction="http://example.com/TestOperation"/>
            <wsdl:input>
              <soap:body use="literal"/>
            </wsdl:input>
            <wsdl:output>
              <soap:body use="literal"/>
            </wsdl:output>
          </wsdl:operation>
        </wsdl:binding>

        <wsdl:service name="TestService">
          <wsdl:port name="TestPort" binding="tns:TestBinding">
            <soap:address location="https://example.com/soap"/>
          </wsdl:port>
        </wsdl:service>
      </wsdl:definitions>
      """

      assert {:ok, parsed} = Parser.parse(mixed_namespace_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.service_name == "TestService"
      assert service_info.target_namespace == "http://example.com/service"
      assert length(service_info.operations) == 1
      assert length(service_info.endpoints) == 1

      operation = List.first(service_info.operations)
      assert operation.name == "TestOperation"
      assert operation.soap_action == "http://example.com/TestOperation"
      assert operation.style == "document"
    end

    test "parses WSDL without namespace prefixes" do
      no_prefix_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://example.com/service"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   targetNamespace="http://example.com/service">
        <message name="SimpleRequestMessage">
          <part name="param" type="string"/>
        </message>

        <message name="SimpleResponseMessage">
          <part name="result" type="string"/>
        </message>

        <portType name="SimplePortType">
          <operation name="SimpleOperation">
            <input message="tns:SimpleRequestMessage"/>
            <output message="tns:SimpleResponseMessage"/>
          </operation>
        </portType>

        <binding name="SimpleBinding" type="tns:SimplePortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="rpc"/>
          <operation name="SimpleOperation">
            <soap:operation soapAction="simple"/>
            <input>
              <soap:body use="encoded" encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
            </input>
            <output>
              <soap:body use="encoded" encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
            </output>
          </operation>
        </binding>

        <service name="SimpleService">
          <port name="SimplePort" binding="tns:SimpleBinding">
            <soap:address location="https://api.example.com/simple"/>
          </port>
        </service>
      </definitions>
      """

      assert {:ok, parsed} = Parser.parse(no_prefix_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.service_name == "SimpleService"
      assert length(service_info.operations) == 1

      operation = List.first(service_info.operations)
      assert operation.name == "SimpleOperation"
      assert operation.style == "rpc"
      assert operation.input.use == "encoded"
    end

    test "handles WSDL with complex type definitions" do
      complex_types_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
                        xmlns:tns="http://weather.gov/xml"
                        xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                        xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                        targetNamespace="http://weather.gov/xml">
        <wsdl:types>
          <xsd:schema targetNamespace="http://weather.gov/xml">
            <xsd:simpleType name="productType">
              <xsd:restriction base="xsd:string">
                <xsd:enumeration value="time-series"/>
                <xsd:enumeration value="glance"/>
              </xsd:restriction>
            </xsd:simpleType>

            <xsd:simpleType name="unitType">
              <xsd:restriction base="xsd:string">
                <xsd:enumeration value="e"/>
                <xsd:enumeration value="m"/>
              </xsd:restriction>
            </xsd:simpleType>

            <xsd:complexType name="weatherParametersType">
              <xsd:all>
                <xsd:element name="maxt" type="xsd:boolean" minOccurs="0"/>
                <xsd:element name="mint" type="xsd:boolean" minOccurs="0"/>
                <xsd:element name="temp" type="xsd:boolean" minOccurs="0"/>
              </xsd:all>
            </xsd:complexType>
          </xsd:schema>
        </wsdl:types>

        <wsdl:message name="NDFDgenRequest">
          <wsdl:part name="latitude" type="xsd:decimal"/>
          <wsdl:part name="longitude" type="xsd:decimal"/>
          <wsdl:part name="product" type="tns:productType"/>
          <wsdl:part name="XMLformat" type="xsd:string"/>
          <wsdl:part name="startTime" type="xsd:dateTime"/>
          <wsdl:part name="endTime" type="xsd:dateTime"/>
          <wsdl:part name="Unit" type="tns:unitType"/>
          <wsdl:part name="weatherParameters" type="tns:weatherParametersType"/>
        </wsdl:message>

        <wsdl:message name="NDFDgenResponse">
          <wsdl:part name="XMLOut" type="xsd:string"/>
        </wsdl:message>

        <wsdl:portType name="ndfdXMLPortType">
          <wsdl:operation name="NDFDgen">
            <wsdl:documentation>Returns National Weather Service digital weather forecast data.</wsdl:documentation>
            <wsdl:input message="tns:NDFDgenRequest"/>
            <wsdl:output message="tns:NDFDgenResponse"/>
          </wsdl:operation>
        </wsdl:portType>

        <wsdl:binding name="ndfdXMLBinding" type="tns:ndfdXMLPortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <wsdl:operation name="NDFDgen">
            <soap:operation soapAction="https://digital.weather.gov/xml/wsdl/ndfdXML.wsdl#NDFDgen"/>
            <wsdl:input>
              <soap:body use="encoded" encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
            </wsdl:input>
            <wsdl:output>
              <soap:body use="encoded" encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
            </wsdl:output>
          </wsdl:operation>
        </wsdl:binding>

        <wsdl:service name="ndfdXML">
          <wsdl:port name="ndfdXMLPort" binding="tns:ndfdXMLBinding">
            <soap:address location="http://localhost/xml/wsdl/ndfdXML.wsdl"/>
          </wsdl:port>
        </wsdl:service>
      </wsdl:definitions>
      """

      assert {:ok, parsed} = Parser.parse(complex_types_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.service_name == "ndfdXML"
      assert length(service_info.operations) == 1

      operation = List.first(service_info.operations)
      assert operation.name == "NDFDgen"
      assert String.contains?(operation.documentation, "weather forecast")
      assert operation.style == "document"
      assert operation.input.use == "encoded"

      # Should have 8 input parameters
      assert length(operation.input.parts) == 8

      # Check specific parameter types that caused issues
      product_param = Enum.find(operation.input.parts, &(&1.name == "product"))
      assert product_param.type == "tns:productType"

      weather_params = Enum.find(operation.input.parts, &(&1.name == "weatherParameters"))
      assert weather_params.type == "tns:weatherParametersType"

      # Endpoint should be localhost (will trigger fallback logic)
      endpoint = List.first(service_info.endpoints)
      assert String.contains?(endpoint.address.location, "localhost")
    end

    test "parses WSDL with multiple services and ports" do
      multi_service_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://example.com/multi"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   targetNamespace="http://example.com/multi">

        <message name="Request">
          <part name="param" type="string"/>
        </message>

        <message name="Response">
          <part name="result" type="string"/>
        </message>

        <portType name="TestPortType">
          <operation name="TestOp">
            <input message="tns:Request"/>
            <output message="tns:Response"/>
          </operation>
        </portType>

        <binding name="TestBinding" type="tns:TestPortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <operation name="TestOp">
            <soap:operation soapAction="test"/>
            <input><soap:body use="literal"/></input>
            <output><soap:body use="literal"/></output>
          </operation>
        </binding>

        <service name="FirstService">
          <port name="HttpPort" binding="tns:TestBinding">
            <soap:address location="http://example.com/service1"/>
          </port>
          <port name="HttpsPort" binding="tns:TestBinding">
            <soap:address location="https://example.com/service1"/>
          </port>
        </service>

        <service name="SecondService">
          <port name="MainPort" binding="tns:TestBinding">
            <soap:address location="https://api.example.com/service2"/>
          </port>
        </service>
      </definitions>
      """

      assert {:ok, parsed} = Parser.parse(multi_service_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      # Should extract all endpoints from all services
      assert length(service_info.endpoints) == 3

      # Check endpoint addresses
      locations = Enum.map(service_info.endpoints, & &1.address.location)
      assert "http://example.com/service1" in locations
      assert "https://example.com/service1" in locations
      assert "https://api.example.com/service2" in locations
    end

    test "handles WSDL with authentication indicators" do
      auth_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://example.com/auth"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
                   targetNamespace="http://example.com/auth">

        <message name="AuthRequest">
          <part name="credentials" type="wsse:Security"/>
          <part name="data" type="string"/>
        </message>

        <message name="AuthResponse">
          <part name="result" type="string"/>
        </message>

        <portType name="AuthPortType">
          <operation name="AuthenticatedOp">
            <input message="tns:AuthRequest"/>
            <output message="tns:AuthResponse"/>
          </operation>
        </portType>

        <binding name="AuthBinding" type="tns:AuthPortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <operation name="AuthenticatedOp">
            <soap:operation soapAction="auth"/>
            <input>
              <soap:body use="literal"/>
              <soap:header message="tns:AuthRequest" part="credentials" use="literal"/>
            </input>
            <output><soap:body use="literal"/></output>
          </operation>
        </binding>

        <service name="AuthService">
          <port name="AuthPort" binding="tns:AuthBinding">
            <soap:address location="https://secure.example.com/auth"/>
          </port>
        </service>
      </definitions>
      """

      assert {:ok, parsed} = Parser.parse(auth_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.service_name == "AuthService"

      # Should detect some form of authentication requirement
      # (The specific detection logic would depend on implementation)
      assert service_info.authentication != nil
    end

    test "handles malformed WSDL gracefully" do
      malformed_cases = [
        # Missing required elements
        """
        <?xml version="1.0"?>
        <definitions xmlns="http://schemas.xmlsoap.org/wsdl/">
          <!-- Missing service and other required elements -->
        </definitions>
        """,

        # Invalid XML structure
        """
        <?xml version="1.0"?>
        <definitions xmlns="http://schemas.xmlsoap.org/wsdl/">
          <service name="Test">
            <!-- Unclosed port element -->
            <port name="TestPort" binding="test">
          </service>
        </definitions>
        """,

        # Mixed up element order
        """
        <?xml version="1.0"?>
        <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                     xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/">
          <service name="TestService">
            <port name="TestPort" binding="TestBinding">
              <soap:address location="http://example.com"/>
            </port>
          </service>
          <!-- binding defined after service -->
          <binding name="TestBinding" type="TestPortType">
            <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          </binding>
        </definitions>
        """
      ]

      for malformed_wsdl <- malformed_cases do
        case Parser.parse(malformed_wsdl) do
          {:ok, parsed} ->
            # If parsing succeeds, extraction should handle missing elements gracefully
            result = Analyzer.extract_service_info(parsed, [])
            # Should return either success with limited info or controlled error
            assert match?({:ok, _}, result) or match?({:error, _}, result)

          {:error, _reason} ->
            # XML parsing errors are expected for malformed XML
            assert true
        end
      end
    end

    test "parses WSDL with different SOAP versions" do
      soap12_wsdl = """
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

      assert {:ok, parsed} = Parser.parse(soap12_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.service_name == "TestSOAP12Service"
      assert length(service_info.endpoints) == 1

      operation = List.first(service_info.operations)
      assert operation.name == "TestOp"
      assert operation.soap_action == "http://example.com/TestOp"
    end

    test "extracts operation documentation and metadata" do
      documented_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                   xmlns:tns="http://example.com/docs"
                   xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                   targetNamespace="http://example.com/docs">

        <message name="DocumentedRequest">
          <part name="input" type="string"/>
        </message>

        <message name="DocumentedResponse">
          <part name="output" type="string"/>
        </message>

        <portType name="DocumentedPortType">
          <operation name="DocumentedOperation">
            <documentation>This operation performs documented functionality. It accepts input parameters and returns processed results. Supports various input formats and handles errors gracefully.</documentation>
            <input message="tns:DocumentedRequest"/>
            <output message="tns:DocumentedResponse"/>
          </operation>
        </portType>

        <binding name="DocumentedBinding" type="tns:DocumentedPortType">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <operation name="DocumentedOperation">
            <soap:operation soapAction="http://example.com/documented"/>
            <input><soap:body use="literal"/></input>
            <output><soap:body use="literal"/></output>
          </operation>
        </binding>

        <service name="DocumentedService">
          <port name="DocumentedPort" binding="tns:DocumentedBinding">
            <soap:address location="http://example.com/documented"/>
          </port>
        </service>
      </definitions>
      """

      assert {:ok, parsed} = Parser.parse(documented_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      operation = List.first(service_info.operations)
      assert operation.name == "DocumentedOperation"
      assert String.contains?(operation.documentation, "documented functionality")
      assert String.contains?(operation.documentation, "accepts input parameters")
    end

    test "handles WSDL with unusual but valid XML structures" do
      unusual_wsdl = """
      <?xml version="1.0" encoding="UTF-8"?>
      <definitions
          xmlns="http://schemas.xmlsoap.org/wsdl/"
          xmlns:tns="http://example.com/unusual"
          xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
          targetNamespace="http://example.com/unusual">

        <!-- Self-closing message parts -->
        <message name="UnusualRequest">
          <part name="param1" type="string"/>
          <part name="param2" type="int"/>
        </message>

        <message name="UnusualResponse">
          <part name="result" type="string"/>
        </message>

        <!-- Operation with unusual formatting -->
        <portType name="UnusualPortType">
          <operation
              name="UnusualOperation">
            <input
                message="tns:UnusualRequest"/>
            <output
                message="tns:UnusualResponse"/>
          </operation>
        </portType>

        <!-- Binding with mixed attributes and elements -->
        <binding name="UnusualBinding" type="tns:UnusualPortType">
          <soap:binding
              transport="http://schemas.xmlsoap.org/soap/http"
              style="rpc"/>
          <operation name="UnusualOperation">
            <soap:operation soapAction="unusual"/>
            <input>
              <soap:body
                  use="encoded"
                  encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
            </input>
            <output>
              <soap:body
                  use="encoded"
                  encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
            </output>
          </operation>
        </binding>

        <service name="UnusualService">
          <port
              name="UnusualPort"
              binding="tns:UnusualBinding">
            <soap:address
                location="http://example.com/unusual/service"/>
          </port>
        </service>
      </definitions>
      """

      assert {:ok, parsed} = Parser.parse(unusual_wsdl)
      assert {:ok, service_info} = Analyzer.extract_service_info(parsed, [])

      assert service_info.service_name == "UnusualService"
      assert length(service_info.operations) == 1

      operation = List.first(service_info.operations)
      assert operation.name == "UnusualOperation"
      assert operation.style == "rpc"
      assert operation.input.use == "encoded"
    end
  end
end
