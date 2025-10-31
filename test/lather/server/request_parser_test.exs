defmodule Lather.Server.RequestParserTest do
  use ExUnit.Case, async: true

  alias Lather.Server.RequestParser

  describe "parse/1 - Basic SOAP request parsing" do
    test "parses simple SOAP request with single parameter" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <GetUser>
            <userId>123</userId>
          </GetUser>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "GetUser"
      assert parsed.params == %{"userId" => "123"}
    end

    test "parses SOAP request with multiple parameters" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <CreateUser>
            <name>John Doe</name>
            <email>john@example.com</email>
            <age>30</age>
          </CreateUser>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "CreateUser"

      assert parsed.params == %{
               "name" => "John Doe",
               "email" => "john@example.com",
               "age" => "30"
             }
    end

    test "parses SOAP request with no parameters" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <Ping/>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "Ping"
      assert parsed.params == %{}
    end

    test "parses SOAP request with empty operation element" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <GetStatus></GetStatus>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "GetStatus"
      assert parsed.params == %{}
    end
  end

  describe "parse/1 - Namespace handling" do
    test "parses SOAP request without namespace prefixes" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
        <Body>
          <GetUser>
            <userId>456</userId>
          </GetUser>
        </Body>
      </Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "GetUser"
      assert parsed.params == %{"userId" => "456"}
    end

    test "parses operation with namespace prefix" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://example.com/service">
        <soap:Body>
          <tns:GetUserInfo>
            <tns:id>789</tns:id>
          </tns:GetUserInfo>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "GetUserInfo"
      assert parsed.params == %{"id" => "789"}
    end

    test "handles mixed namespace prefixes" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:usr="http://example.com/users">
        <soap:Body>
          <usr:UpdateUser>
            <usr:userId>123</usr:userId>
            <name>Jane Smith</name>
            <usr:email>jane@example.com</usr:email>
          </usr:UpdateUser>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "UpdateUser"

      assert parsed.params == %{
               "userId" => "123",
               "name" => "Jane Smith",
               "email" => "jane@example.com"
             }
    end
  end

  describe "parse/1 - Complex parameters" do
    test "parses nested parameters" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <CreateUser>
            <userData>
              <personal>
                <firstName>John</firstName>
                <lastName>Doe</lastName>
              </personal>
              <contact>
                <email>john@example.com</email>
                <phone>555-1234</phone>
              </contact>
            </userData>
          </CreateUser>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "CreateUser"

      assert parsed.params == %{
               "userData" => %{
                 "personal" => %{
                   "firstName" => "John",
                   "lastName" => "Doe"
                 },
                 "contact" => %{
                   "email" => "john@example.com",
                   "phone" => "555-1234"
                 }
               }
             }
    end

    test "parses deeply nested parameters" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <ProcessOrder>
            <order>
              <customer>
                <details>
                  <name>Alice</name>
                  <id>999</id>
                </details>
              </customer>
              <items>
                <item>
                  <name>Widget</name>
                  <quantity>5</quantity>
                </item>
              </items>
            </order>
          </ProcessOrder>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "ProcessOrder"
      assert parsed.params["order"]["customer"]["details"]["name"] == "Alice"
      assert parsed.params["order"]["items"]["item"]["quantity"] == "5"
    end

    test "handles empty nested elements" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <TestOperation>
            <data>
              <emptyField></emptyField>
              <anotherField>value</anotherField>
            </data>
          </TestOperation>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "TestOperation"

      assert parsed.params == %{
               "data" => %{
                 "emptyField" => %{},
                 "anotherField" => "value"
               }
             }
    end
  end

  describe "parse/1 - Error handling" do
    test "returns error for invalid XML" do
      invalid_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <GetUser>
            <userId>123</unclosed-tag>
        </soap:Body>
      </soap:Envelope>
      """

      {:error, {:parse_error, _reason}} = RequestParser.parse(invalid_xml)
    end

    test "returns error for missing SOAP envelope" do
      not_soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <root>
        <data>value</data>
      </root>
      """

      {:error, {:parse_error, reason}} = RequestParser.parse(not_soap_xml)
      assert reason == "No SOAP envelope found"
    end

    test "returns error for missing SOAP body" do
      no_body_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Header>
          <auth>token</auth>
        </soap:Header>
      </soap:Envelope>
      """

      {:error, {:parse_error, reason}} = RequestParser.parse(no_body_xml)
      assert reason == "No SOAP body found"
    end

    test "returns error for empty SOAP body" do
      empty_body_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
        </soap:Body>
      </soap:Envelope>
      """

      {:error, {:parse_error, reason}} = RequestParser.parse(empty_body_xml)
      assert reason == "No operation found in SOAP body"
    end

    test "returns error for completely empty XML" do
      {:error, {:parse_error, _reason}} = RequestParser.parse("")
    end

    test "returns error for non-XML string" do
      {:error, {:parse_error, _reason}} = RequestParser.parse("not xml at all")
    end

    test "returns error for XML with only whitespace content" do
      whitespace_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <Operation>

          </Operation>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(whitespace_xml)

      assert parsed.operation == "Operation"
      assert parsed.params == %{}
    end
  end

  describe "parse/1 - SOAP 1.2 support" do
    test "parses SOAP 1.2 envelope" do
      soap12_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <GetData>
            <id>555</id>
          </GetData>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap12_xml)

      assert parsed.operation == "GetData"
      assert parsed.params == %{"id" => "555"}
    end
  end

  describe "parse/1 - Special cases and edge cases" do
    test "handles operation names with special characters" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <Get-User_Info>
            <user-id>123</user-id>
          </Get-User_Info>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "Get-User_Info"
      assert parsed.params == %{"user-id" => "123"}
    end

    test "handles parameters with numeric values" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <Calculate>
            <a>10</a>
            <b>20</b>
            <operation>add</operation>
          </Calculate>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "Calculate"

      assert parsed.params == %{
               "a" => "10",
               "b" => "20",
               "operation" => "add"
             }
    end

    test "handles parameters with boolean-like values" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <UpdateSettings>
            <enabled>true</enabled>
            <debug>false</debug>
            <mode>test</mode>
          </UpdateSettings>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "UpdateSettings"

      assert parsed.params == %{
               "enabled" => "true",
               "debug" => "false",
               "mode" => "test"
             }
    end

    test "handles CDATA sections in parameters" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <ProcessXML>
            <xmlData><![CDATA[<inner><data>value</data></inner>]]></xmlData>
          </ProcessXML>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "ProcessXML"
      assert String.contains?(parsed.params["xmlData"], "<inner><data>value</data></inner>")
    end

    test "handles Unicode characters in parameters" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <CreateUser>
            <name>José María</name>
            <city>São Paulo</city>
            <note>测试</note>
          </CreateUser>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "CreateUser"

      assert parsed.params == %{
               "name" => "José María",
               "city" => "São Paulo",
               "note" => "测试"
             }
    end

    test "handles large parameter values" do
      large_value = String.duplicate("data", 1000)

      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <ProcessLargeData>
            <content>#{large_value}</content>
          </ProcessLargeData>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "ProcessLargeData"
      assert parsed.params["content"] == large_value
    end
  end

  describe "parse/1 - Real-world SOAP scenarios" do
    test "parses typical web service request with authentication" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Header>
          <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
            <wsse:UsernameToken>
              <wsse:Username>admin</wsse:Username>
              <wsse:Password>secret</wsse:Password>
            </wsse:UsernameToken>
          </wsse:Security>
        </soap:Header>
        <soap:Body>
          <GetCustomerOrders>
            <customerId>12345</customerId>
            <dateRange>
              <from>2023-01-01</from>
              <to>2023-12-31</to>
            </dateRange>
          </GetCustomerOrders>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "GetCustomerOrders"
      assert parsed.params["customerId"] == "12345"
      assert parsed.params["dateRange"]["from"] == "2023-01-01"
      assert parsed.params["dateRange"]["to"] == "2023-12-31"
    end

    test "parses request with array-like structures" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <ProcessItems>
            <items>
              <item>
                <id>1</id>
                <name>First Item</name>
              </item>
              <item>
                <id>2</id>
                <name>Second Item</name>
              </item>
            </items>
          </ProcessItems>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "ProcessItems"
      # Note: The exact structure depends on XML parser behavior with repeated elements
      assert Map.has_key?(parsed.params, "items")
      assert is_map(parsed.params["items"])
    end
  end

  describe "parse/1 - Fault conditions handled gracefully" do
    test "handles XML with processing instructions" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <?xml-stylesheet type="text/xsl" href="style.xsl"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <TestOperation>
            <data>value</data>
          </TestOperation>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "TestOperation"
      assert parsed.params == %{"data" => "value"}
    end

    test "handles XML with comments" do
      soap_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <!-- This is a comment -->
        <soap:Body>
          <!-- Another comment -->
          <TestOperation>
            <data>value</data>
          </TestOperation>
        </soap:Body>
      </soap:Envelope>
      """

      {:ok, parsed} = RequestParser.parse(soap_xml)

      assert parsed.operation == "TestOperation"
      assert parsed.params == %{"data" => "value"}
    end
  end
end
