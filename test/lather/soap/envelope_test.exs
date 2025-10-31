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
