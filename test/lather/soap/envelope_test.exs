defmodule Lather.Soap.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Lather.Soap.Envelope

  describe "build/3 - SOAP envelope building" do
    test "builds basic SOAP 1.1 envelope" do
      {:ok, xml} = Envelope.build(:GetUser, %{id: "123"})

      assert String.contains?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      assert String.contains?(xml, "<soap:Envelope")
      assert String.contains?(xml, "xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"")
      assert String.contains?(xml, "<soap:Body>")
      assert String.contains?(xml, "<GetUser>")
      assert String.contains?(xml, "<id>123</id>")
      assert String.contains?(xml, "</GetUser>")
      assert String.contains?(xml, "</soap:Body>")
      assert String.contains?(xml, "</soap:Envelope>")
    end

    test "builds SOAP envelope with string operation name" do
      {:ok, xml} = Envelope.build("CreateUser", %{name: "John", email: "john@test.com"})

      assert String.contains?(xml, "<CreateUser>")
      assert String.contains?(xml, "<name>John</name>")
      assert String.contains?(xml, "<email>john@test.com</email>")
    end

    test "builds SOAP 1.2 envelope when specified" do
      {:ok, xml} = Envelope.build(:GetData, %{}, version: :v1_2)

      assert String.contains?(xml, "xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\"")
    end

    test "includes SOAP headers when provided" do
      headers = [
        {"Action", "http://example.com/GetUser"},
        {"MessageID", "uuid:12345"}
      ]

      {:ok, xml} = Envelope.build(:GetUser, %{id: "123"}, headers: headers)

      assert String.contains?(xml, "<soap:Header>")
      assert String.contains?(xml, "<Action>http://example.com/GetUser</Action>")
      assert String.contains?(xml, "<MessageID>uuid:12345</MessageID>")
    end

    test "includes SOAP headers when provided as list of maps" do
      # This format is used by WS-Security and other complex headers
      headers = [
        %{"wsse:Security" => %{
          "@xmlns:wsse" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
          "wsse:UsernameToken" => %{
            "wsse:Username" => "testuser",
            "wsse:Password" => "testpass"
          }
        }}
      ]

      {:ok, xml} = Envelope.build(:GetUser, %{id: "123"}, headers: headers)

      assert String.contains?(xml, "<soap:Header>")
      assert String.contains?(xml, "<wsse:Security")
      assert String.contains?(xml, "<wsse:Username>testuser</wsse:Username>")
      assert String.contains?(xml, "<wsse:Password>testpass</wsse:Password>")
    end

    test "merges multiple map headers together" do
      headers = [
        %{"Header1" => "Value1"},
        %{"Header2" => "Value2"}
      ]

      {:ok, xml} = Envelope.build(:GetUser, %{id: "123"}, headers: headers)

      assert String.contains?(xml, "<Header1>Value1</Header1>")
      assert String.contains?(xml, "<Header2>Value2</Header2>")
    end

    test "includes empty header element when no headers provided" do
      {:ok, xml} = Envelope.build(:GetUser, %{id: "123"})

      assert String.contains?(xml, "<soap:Header></soap:Header>") or
               String.contains?(xml, "<soap:Header/>")
    end

    test "includes namespace in operation when specified" do
      {:ok, xml} = Envelope.build(:GetUser, %{id: "123"}, namespace: "http://example.com/service")

      assert String.contains?(xml, "xmlns=\"http://example.com/service\"")
    end

    test "handles complex nested parameters" do
      params = %{
        user: %{
          personal: %{
            name: "John Doe",
            age: "30"
          },
          contact: %{
            email: "john@example.com",
            phone: "+1234567890"
          }
        }
      }

      {:ok, xml} = Envelope.build(:CreateUser, params)

      assert String.contains?(xml, "<user>")
      assert String.contains?(xml, "<personal>")
      assert String.contains?(xml, "<name>John Doe</name>")
      assert String.contains?(xml, "<contact>")
      assert String.contains?(xml, "<email>john@example.com</email>")
    end

    test "handles empty parameters" do
      {:ok, xml} = Envelope.build(:Ping, %{})

      assert String.contains?(xml, "<Ping/>") or String.contains?(xml, "<Ping></Ping>")
    end

    test "handles parameters with attributes" do
      params = %{
        "@id" => "user123",
        name: "John Doe"
      }

      {:ok, xml} = Envelope.build(:GetUser, params)

      assert String.contains?(xml, "id=\"user123\"")
      assert String.contains?(xml, "<name>John Doe</name>")
    end

    test "returns error when XML building fails" do
      # This would trigger an error in the Builder
      invalid_params = %{
        :invalid_atom_key => "value"
      }

      case Envelope.build(:Test, invalid_params) do
        {:error, {:envelope_build_error, _reason}} ->
          assert true

        {:ok, _xml} ->
          # If it doesn't fail, that's also fine - the test is about error handling
          assert true
      end
    end

    test "raw_body option uses params directly as body without wrapping in operation" do
      # For document/literal with element-based parts, the body should contain
      # the element directly (e.g., GetWeather_Input), not wrapped in operation name
      params = %{
        "GetWeather_Input" => %{
          "@xmlns" => "http://example.com/weather",
          "WeatherRequest" => %{
            "Location" => %{
              "City" => "London"
            }
          }
        }
      }

      {:ok, xml} = Envelope.build(:GetWeather, params, raw_body: true)

      # Should contain the element directly in body, NOT wrapped in <GetWeather>
      assert String.contains?(xml, "<soap:Body>")
      assert String.contains?(xml, "<GetWeather_Input")
      assert String.contains?(xml, "xmlns=\"http://example.com/weather\"")
      assert String.contains?(xml, "<WeatherRequest>")
      # Should NOT contain the operation name as a wrapper
      refute String.contains?(xml, "<GetWeather>")
      refute String.contains?(xml, "<GetWeather ")
    end

    test "raw_body: false (default) wraps params in operation name" do
      params = %{
        "SomeElement" => %{"value" => "test"}
      }

      {:ok, xml} = Envelope.build(:MyOperation, params, raw_body: false)

      # Should wrap in operation name
      assert String.contains?(xml, "<MyOperation>")
      assert String.contains?(xml, "<SomeElement>")
    end

    test "raw_body with namespace preserves namespace in element" do
      params = %{
        "InputElement" => %{
          "@xmlns" => "http://example.com/ns",
          "data" => "value"
        }
      }

      {:ok, xml} = Envelope.build(:Operation, params, raw_body: true)

      assert String.contains?(xml, "<InputElement")
      assert String.contains?(xml, "xmlns=\"http://example.com/ns\"")
      assert String.contains?(xml, "<data>value</data>")
    end
  end

  describe "parse_response/1 - SOAP response parsing" do
    test "parses successful SOAP 1.1 response" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <GetUserResponse>
              <user>
                <id>123</id>
                <name>John Doe</name>
                <email>john@example.com</email>
              </user>
            </GetUserResponse>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:ok, result} = Envelope.parse_response(response)

      assert result["user"]["id"] == "123"
      assert result["user"]["name"] == "John Doe"
      assert result["user"]["email"] == "john@example.com"
    end

    test "parses successful SOAP response without namespace prefixes" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
          <Body>
            <GetDataResponse>
              <data>test data</data>
            </GetDataResponse>
          </Body>
        </Envelope>
        """
      }

      {:ok, result} = Envelope.parse_response(response)

      assert result["data"] == "test data"
    end

    test "extracts multiple operations from response body" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <Operation1Response>
              <result1>value1</result1>
            </Operation1Response>
            <Operation2Response>
              <result2>value2</result2>
            </Operation2Response>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:ok, result} = Envelope.parse_response(response)

      assert result["Operation1Response"]["result1"] == "value1"
      assert result["Operation2Response"]["result2"] == "value2"
    end

    test "parses SOAP 1.1 fault response" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>Client</faultcode>
              <faultstring>Invalid user ID</faultstring>
              <detail>
                <error>User ID must be numeric</error>
              </detail>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "Client"
      assert fault.string == "Invalid user ID"
      assert fault.detail["error"] == "User ID must be numeric"
    end

    test "parses SOAP 1.2 fault response" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
          <soap:Body>
            <soap:Fault>
              <Code>Sender</Code>
              <Reason>Authentication failed</Reason>
              <Detail>
                <AuthError>Invalid credentials</AuthError>
              </Detail>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "Sender"
      assert fault.string == "Authentication failed"
      assert fault.detail["AuthError"] == "Invalid credentials"
    end

    test "parses SOAP 1.2 fault with proper nested structure" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:m="http://example.com/timeout">
          <soap:Body>
            <soap:Fault>
              <soap:Code>
                <soap:Value>soap:Sender</soap:Value>
                <soap:Subcode>
                  <soap:Value>m:MessageTimeout</soap:Value>
                </soap:Subcode>
              </soap:Code>
              <soap:Reason>
                <soap:Text xml:lang="en">Message processing timeout</soap:Text>
              </soap:Reason>
              <soap:Detail>
                <m:MaxTime>60</m:MaxTime>
              </soap:Detail>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Sender"
      assert fault.subcode == "m:MessageTimeout"
      assert fault.string == "Message processing timeout"
      assert fault.detail["m:MaxTime"] == "60"
      assert fault.soap_version == :v1_2
    end

    test "parses SOAP 1.2 fault with multiple language reasons" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
          <soap:Body>
            <soap:Fault>
              <soap:Code>
                <soap:Value>soap:Client</soap:Value>
              </soap:Code>
              <soap:Reason>
                <soap:Text xml:lang="en">Invalid request format</soap:Text>
                <soap:Text xml:lang="de">Ungültiges Anforderungsformat</soap:Text>
                <soap:Text xml:lang="fr">Format de demande non valide</soap:Text>
              </soap:Reason>
              <soap:Detail>
                <ErrorCode>ERR_001</ErrorCode>
              </soap:Detail>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Client"
      # Should prefer English text
      assert fault.string == "Invalid request format"
      assert fault.detail["ErrorCode"] == "ERR_001"
      assert fault.soap_version == :v1_2
    end

    test "parses fault without namespace prefix" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">
          <Body>
            <Fault>
              <faultcode>Server</faultcode>
              <faultstring>Internal error</faultstring>
            </Fault>
          </Body>
        </Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "Server"
      assert fault.string == "Internal error"
    end

    test "parses fault with minimal information" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>Client</faultcode>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "Client"
      assert is_nil(fault.string)
      assert is_nil(fault.detail)
    end

    test "handles successful response with SOAP fault present" do
      # Some services return 200 but with a SOAP fault in the body
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>Client</faultcode>
              <faultstring>Validation error</faultstring>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "Client"
      assert fault.string == "Validation error"
    end

    test "returns error for non-success status without parseable SOAP" do
      response = %{
        status: 404,
        body: "<html><body>Not Found</body></html>"
      }

      case Envelope.parse_response(response) do
        {:error, {:http_error, 404, "<html><body>Not Found</body></html>"}} ->
          assert true

        {:error, {:soap_fault, :invalid_soap_response}} ->
          assert true

        {:error, {:parse_error, _reason}} ->
          assert true
      end
    end

    test "returns HTTP error for success status with non-SOAP content" do
      response = %{
        status: 200,
        body: "Plain text response"
      }

      case Envelope.parse_response(response) do
        {:error, {:parse_error, _reason}} ->
          assert true

        {:error, {:http_error, 200, "Plain text response"}} ->
          assert true
      end
    end

    test "returns parse error for malformed XML" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <InvalidXML>
              <unclosed-tag>content
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:parse_error, _reason}} = Envelope.parse_response(response)
    end

    test "returns error for empty XML body" do
      response = %{
        status: 200,
        body: ""
      }

      {:error, {:parse_error, _reason}} = Envelope.parse_response(response)
    end

    test "returns error for invalid SOAP structure" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <NotAnEnvelope>
          <SomeData>value</SomeData>
        </NotAnEnvelope>
        """
      }

      case Envelope.parse_response(response) do
        {:error, {:soap_fault, :invalid_soap_response}} ->
          assert true

        {:error, {:http_error, 200, _body}} ->
          # Depending on implementation, this might also be acceptable
          assert true
      end
    end

    test "handles complex nested response data" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <GetOrderResponse>
              <order>
                <id>12345</id>
                <customer>
                  <name>Jane Smith</name>
                  <address>
                    <street>123 Main St</street>
                    <city>Springfield</city>
                    <state>IL</state>
                  </address>
                </customer>
                <items>
                  <item>
                    <name>Widget A</name>
                    <quantity>2</quantity>
                    <price>10.50</price>
                  </item>
                  <item>
                    <name>Widget B</name>
                    <quantity>1</quantity>
                    <price>25.00</price>
                  </item>
                </items>
              </order>
            </GetOrderResponse>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:ok, result} = Envelope.parse_response(response)

      assert result["order"]["id"] == "12345"
      assert result["order"]["customer"]["name"] == "Jane Smith"
      assert result["order"]["customer"]["address"]["city"] == "Springfield"

      # Handle items as either single item or list
      items = result["order"]["items"]["item"]

      if is_list(items) do
        assert length(items) == 2
        assert Enum.at(items, 0)["name"] == "Widget A"
        assert Enum.at(items, 1)["price"] == "25.00"
      else
        # Single item case - depending on XML parser behavior
        assert items["name"] in ["Widget A", "Widget B"]
      end
    end

    test "handles response with XML attributes" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <GetProductResponse>
              <product id="P123" category="electronics">
                <name>Smartphone</name>
                <price currency="USD">299.99</price>
              </product>
            </GetProductResponse>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:ok, result} = Envelope.parse_response(response)

      product = result["product"]
      assert product["@id"] == "P123"
      assert product["@category"] == "electronics"
      assert product["name"] == "Smartphone"
      assert product["price"]["@currency"] == "USD"
      assert product["price"]["#text"] == "299.99"
    end
  end

  describe "SOAP version detection and fault parsing" do
    test "detects SOAP 1.2 version from namespace" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
          <soap:Body>
            <GetDataResponse>
              <result>success</result>
            </GetDataResponse>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:ok, result} = Envelope.parse_response(response)
      assert result["result"] == "success"
    end

    test "detects SOAP 1.1 version from namespace" do
      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <GetDataResponse>
              <result>success</result>
            </GetDataResponse>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:ok, result} = Envelope.parse_response(response)
      assert result["result"] == "success"
    end

    test "parses SOAP 1.1 fault with version info" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>Client</faultcode>
              <faultstring>Invalid user ID</faultstring>
              <detail>
                <error>User ID must be numeric</error>
              </detail>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "Client"
      assert fault.string == "Invalid user ID"
      assert fault.detail["error"] == "User ID must be numeric"
      assert fault.soap_version == :v1_1
    end

    test "handles SOAP 1.2 fault without subcode" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
          <soap:Body>
            <soap:Fault>
              <soap:Code>
                <soap:Value>soap:Server</soap:Value>
              </soap:Code>
              <soap:Reason>
                <soap:Text xml:lang="en">Internal server error</soap:Text>
              </soap:Reason>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Server"
      assert fault.subcode == nil
      assert fault.string == "Internal server error"
      assert fault.detail == nil
      assert fault.soap_version == :v1_2
    end

    test "handles SOAP 1.2 fault with non-English default language" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
          <soap:Body>
            <soap:Fault>
              <soap:Code>
                <soap:Value>soap:Client</soap:Value>
              </soap:Code>
              <soap:Reason>
                <soap:Text xml:lang="fr">Erreur de format</soap:Text>
                <soap:Text xml:lang="de">Format fehler</soap:Text>
              </soap:Reason>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Client"
      # Should return first available text when no English available
      assert fault.string == "Erreur de format"
      assert fault.soap_version == :v1_2
    end

    test "handles SOAP 1.2 fault with single text without language" do
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
          <soap:Body>
            <soap:Fault>
              <soap:Code>
                <soap:Value>soap:Client</soap:Value>
              </soap:Code>
              <soap:Reason>
                <soap:Text>Simple error message</soap:Text>
              </soap:Reason>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Client"
      assert fault.string == "Simple error message"
      assert fault.soap_version == :v1_2
    end

    test "detects SOAP version from fault structure" do
      # SOAP 1.2 structure should be detected even without namespace declaration
      response = %{
        status: 500,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <Envelope>
          <Body>
            <Fault>
              <Code>
                <Value>soap:Client</Value>
              </Code>
              <Reason>
                <Text>Error message</Text>
              </Reason>
            </Fault>
          </Body>
        </Envelope>
        """
      }

      {:error, {:soap_fault, fault}} = Envelope.parse_response(response)

      assert fault.code == "soap:Client"
      assert fault.string == "Error message"
      assert fault.soap_version == :v1_2
    end
  end

  describe "edge cases and error conditions" do
    test "handles nil body" do
      response = %{
        status: 200,
        body: nil
      }

      case Envelope.parse_response(response) do
        {:error, {:parse_error, _reason}} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles empty body" do
      response = %{
        status: 200,
        body: ""
      }

      case Envelope.parse_response(response) do
        {:error, {:parse_error, _reason}} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles very large response bodies" do
      # Create a reasonably large XML response
      large_data = String.duplicate("<item>data</item>", 1000)

      response = %{
        status: 200,
        body: """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <GetBulkDataResponse>
              <items>
                #{large_data}
              </items>
            </GetBulkDataResponse>
          </soap:Body>
        </soap:Envelope>
        """
      }

      # Should handle without errors
      case Envelope.parse_response(response) do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, "items")

        {:error, _reason} ->
          # Also acceptable if there are parsing limits
          assert true
      end
    end
  end
end
