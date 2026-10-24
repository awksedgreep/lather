defmodule Lather.Regression.HighPriorityFixesTest do
  use ExUnit.Case, async: true

  alias Lather.{Error, Wsdl.Analyzer}
  alias Lather.Server.{WSDLGenerator, EnhancedWSDLGenerator}

  describe "WSDL analyzer with xs:-prefixed schemas (issue #30)" do
    test "discovers complex types declared with the xs: prefix" do
      wsdl = """
      <wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/" xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <wsdl:types>
          <xs:schema>
            <xs:complexType name="User">
              <xs:sequence>
                <xs:element name="id" type="xs:int"/>
                <xs:element name="name" type="xs:string"/>
              </xs:sequence>
            </xs:complexType>
          </xs:schema>
        </wsdl:types>
      </wsdl:definitions>
      """

      {:ok, info} = Analyzer.analyze(wsdl)
      assert [%{name: "User", elements: elements}] = info.types
      assert Enum.map(elements, & &1.name) == ["id", "name"]
    end
  end

  describe "format_error JSON encoding (issue #31)" do
    test "format: :json produces valid JSON" do
      json = Error.format_error(%{type: :x, message: "a & b"}, format: :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["message"] == "a & b"
    end
  end

  describe "WSDL generation XML escaping (issue #32)" do
    test "escapes special characters in descriptions and names" do
      info = %{
        name: "S&Service",
        target_namespace: "http://x/",
        namespace: "http://x/",
        types: [],
        operations: [
          %{
            name: "Get<script>alert(1)</script>",
            function_name: "get_script",
            description: "Fish & Chips <b>",
            soap_action: nil,
            input: [%{name: "q", type: "string", required: false}],
            output: []
          }
        ]
      }

      wsdl = WSDLGenerator.generate(info, "http://localhost:4000/soap")

      # Resulting document must be well-formed XML.
      assert {:ok, _} = Lather.Xml.Parser.parse(wsdl)
      assert wsdl =~ "Fish &amp; Chips &lt;b&gt;"
    end

    test "enhanced generator escapes special characters too" do
      info = %{
        name: "S&Service",
        target_namespace: "http://x/",
        namespace: "http://x/",
        types: [],
        operations: [
          %{
            name: "Get",
            function_name: "get",
            description: "Fish & Chips",
            soap_action: nil,
            input: [],
            output: []
          }
        ]
      }

      wsdl = EnhancedWSDLGenerator.generate(info, "http://localhost:4000/soap")
      assert {:ok, _} = Lather.Xml.Parser.parse(wsdl)
      assert wsdl =~ "Fish &amp; Chips"
    end
  end

  describe "SOAP 1.2 fault code/reason extraction (issue #34)" do    test "returns the fault code and reason as strings" do
      xml = """
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <soap:Fault>
            <faultcode>soap:Sender</faultcode>
            <Reason>
              <Text>bad request</Text>
            </Reason>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, fault} = Error.parse_soap_fault(xml)

      assert fault.fault_string == "bad request"
      assert is_binary(fault.fault_code)
      assert fault.fault_code =~ "Sender"
    end
  end

  describe "boolean form submission (issue #33)" do
    test "checkbox 'on'/'off' values are accepted as booleans" do
      op = %{
        name: "Test",
        function_name: "test",
        input: [%{name: "flag", type: "boolean", required: false}],
        output: []
      }

      assert :ok = Lather.Server.validate_param_types(%{"flag" => "on"}, op)
      assert :ok = Lather.Server.validate_param_types(%{"flag" => "off"}, op)
      assert {:error, _} = Lather.Server.validate_param_types(%{"flag" => "yes"}, op)
    end
  end
end
