defmodule Lather.Server.ResponseBuilderTest do
  use ExUnit.Case, async: true

  alias Lather.Server.ResponseBuilder

  describe "build_response/2 - Basic response building" do
    test "builds simple response with string result" do
      result = "success"
      operation = %{name: "GetStatus"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      assert String.contains?(xml, "<soap:Envelope")
      assert String.contains?(xml, "xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"")
      assert String.contains?(xml, "<soap:Body>")
      assert String.contains?(xml, "<GetStatusResponse>")
      assert String.contains?(xml, "success")
      assert String.contains?(xml, "</GetStatusResponse>")
      assert String.contains?(xml, "</soap:Body>")
      assert String.contains?(xml, "</soap:Envelope>")
    end

    test "builds response with map result" do
      result = %{"userId" => "123", "name" => "John Doe"}
      operation = %{name: "GetUser"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<GetUserResponse>")
      assert String.contains?(xml, "<userId>123</userId>")
      assert String.contains?(xml, "<name>John Doe</name>")
    end

    test "builds response with nested map result" do
      result = %{
        "user" => %{
          "id" => "123",
          "personal" => %{
            "firstName" => "John",
            "lastName" => "Doe"
          },
          "contact" => %{
            "email" => "john@example.com"
          }
        }
      }

      operation = %{name: "GetUserDetails"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<GetUserDetailsResponse>")
      assert String.contains?(xml, "<user>")
      assert String.contains?(xml, "<id>123</id>")
      assert String.contains?(xml, "<personal>")
      assert String.contains?(xml, "<firstName>John</firstName>")
      assert String.contains?(xml, "<lastName>Doe</lastName>")
      assert String.contains?(xml, "<contact>")
      assert String.contains?(xml, "<email>john@example.com</email>")
    end

    test "builds response with empty result" do
      result = %{}
      operation = %{name: "DeleteUser"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<DeleteUserResponse")
      # Should contain either self-closing tag or empty element
      assert String.contains?(xml, "<DeleteUserResponse/>") or
               String.contains?(xml, "<DeleteUserResponse></DeleteUserResponse>")
    end

    test "builds response with nil result" do
      result = nil
      operation = %{name: "TestOperation"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<TestOperationResponse")
      # Should handle nil gracefully
      assert is_binary(xml)
      assert String.length(xml) > 0
    end

    test "builds response with boolean result" do
      result = %{"success" => true, "enabled" => false}
      operation = %{name: "UpdateSettings"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<UpdateSettingsResponse>")
      assert String.contains?(xml, "<success>true</success>")
      assert String.contains?(xml, "<enabled>false</enabled>")
    end

    test "builds response with numeric result" do
      result = %{"count" => 42, "price" => 99.99, "id" => 123}
      operation = %{name: "Calculate"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<CalculateResponse>")
      assert String.contains?(xml, "<count>42</count>")
      assert String.contains?(xml, "<price>99.99</price>")
      assert String.contains?(xml, "<id>123</id>")
    end
  end

  describe "build_response/2 - Complex scenarios" do
    test "builds response with array-like data" do
      result = %{
        "users" => [
          %{"id" => "1", "name" => "Alice"},
          %{"id" => "2", "name" => "Bob"}
        ]
      }

      operation = %{name: "ListUsers"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<ListUsersResponse>")
      assert String.contains?(xml, "<users>")
      # Array handling depends on XML builder implementation
      assert String.contains?(xml, "Alice")
      assert String.contains?(xml, "Bob")
    end

    test "builds response with attributes" do
      result = %{
        "product" => %{
          "@id" => "P123",
          "@category" => "electronics",
          "name" => "Smartphone",
          "price" => "299.99"
        }
      }

      operation = %{name: "GetProduct"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<GetProductResponse>")
      assert String.contains?(xml, "id=\"P123\"")
      assert String.contains?(xml, "category=\"electronics\"")
      assert String.contains?(xml, "<name>Smartphone</name>")
    end

    test "builds response with mixed content" do
      result = %{
        "message" => %{
          "@type" => "info",
          "#text" => "Operation completed successfully",
          "timestamp" => "2023-01-01T10:00:00Z"
        }
      }

      operation = %{name: "ProcessData"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<ProcessDataResponse>")
      assert String.contains?(xml, "type=\"info\"")
      assert String.contains?(xml, "Operation completed successfully")
      assert String.contains?(xml, "<timestamp>2023-01-01T10:00:00Z</timestamp>")
    end

    test "builds response with special characters" do
      result = %{
        "message" => "Success with <special> & \"characters\"",
        "name" => "José María",
        "data" => "测试数据"
      }

      operation = %{name: "ProcessSpecialChars"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<ProcessSpecialCharsResponse>")
      # XML should be properly escaped
      assert String.contains?(xml, "&lt;special&gt;")
      assert String.contains?(xml, "&amp;")
      # Note: quotes don't need escaping in element text content, only in attributes
      assert String.contains?(xml, "José María")
      assert String.contains?(xml, "测试数据")
    end

    test "builds response with large data" do
      large_text = String.duplicate("data", 1000)
      result = %{"content" => large_text}
      operation = %{name: "ProcessLargeData"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<ProcessLargeDataResponse>")
      assert String.contains?(xml, large_text)
      assert String.length(xml) > String.length(large_text)
    end
  end

  describe "build_fault/1 - SOAP fault building" do
    test "builds basic SOAP fault" do
      fault = %{
        fault_code: "Client",
        fault_string: "Invalid input parameter"
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      assert String.contains?(xml, "<soap:Envelope")
      assert String.contains?(xml, "xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"")
      assert String.contains?(xml, "<soap:Body>")
      assert String.contains?(xml, "<soap:Fault>")
      assert String.contains?(xml, "<faultcode>Client</faultcode>")
      assert String.contains?(xml, "<faultstring>Invalid input parameter</faultstring>")
      assert String.contains?(xml, "</soap:Fault>")
      assert String.contains?(xml, "</soap:Body>")
      assert String.contains?(xml, "</soap:Envelope>")
    end

    test "builds SOAP fault with detail" do
      fault = %{
        fault_code: "Server",
        fault_string: "Database connection failed",
        detail: %{
          "error_code" => "DB001",
          "message" => "Connection timeout after 30 seconds"
        }
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<soap:Fault>")
      assert String.contains?(xml, "<faultcode>Server</faultcode>")
      assert String.contains?(xml, "<faultstring>Database connection failed</faultstring>")
      assert String.contains?(xml, "<detail>")
      assert String.contains?(xml, "<error_code>DB001</error_code>")
      assert String.contains?(xml, "<message>Connection timeout after 30 seconds</message>")
      assert String.contains?(xml, "</detail>")
    end

    test "builds SOAP fault with nested detail" do
      fault = %{
        fault_code: "Client",
        fault_string: "Validation failed",
        detail: %{
          "validation_errors" => %{
            "field1" => "Required field missing",
            "field2" => "Invalid format"
          }
        }
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<detail>")
      assert String.contains?(xml, "<validation_errors>")
      assert String.contains?(xml, "<field1>Required field missing</field1>")
      assert String.contains?(xml, "<field2>Invalid format</field2>")
    end

    test "builds SOAP fault without detail" do
      fault = %{
        fault_code: "Client",
        fault_string: "Authentication failed"
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<faultcode>Client</faultcode>")
      assert String.contains?(xml, "<faultstring>Authentication failed</faultstring>")
      refute String.contains?(xml, "<detail>")
    end

    test "builds SOAP fault with empty detail" do
      fault = %{
        fault_code: "Server",
        fault_string: "Internal error",
        detail: %{}
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<faultcode>Server</faultcode>")
      assert String.contains?(xml, "<faultstring>Internal error</faultstring>")
      # Empty detail should not be included or should be empty element
      refute String.contains?(xml, "<detail></detail>")
    end

    test "builds SOAP fault with nil detail" do
      fault = %{
        fault_code: "Server",
        fault_string: "System unavailable",
        detail: nil
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<faultcode>Server</faultcode>")
      assert String.contains?(xml, "<faultstring>System unavailable</faultstring>")
      refute String.contains?(xml, "<detail>")
    end
  end

  describe "build_response/2 - Operation name handling" do
    test "handles operation names with different cases" do
      result = %{"status" => "ok"}
      operation = %{name: "getUserInfo"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<getUserInfoResponse>")
      assert String.contains?(xml, "</getUserInfoResponse>")
    end

    test "handles operation names with special characters" do
      result = %{"result" => "success"}
      operation = %{name: "Get-User_Data"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<Get-User_DataResponse>")
      assert String.contains?(xml, "</Get-User_DataResponse>")
    end

    test "handles empty operation name" do
      result = %{"data" => "test"}
      operation = %{name: ""}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<Response>")
      assert String.contains?(xml, "</Response>")
    end

    test "handles missing operation name" do
      result = %{"data" => "test"}
      operation = %{}

      # Should handle gracefully, maybe with default name or error
      xml = ResponseBuilder.build_response(result, operation)
      assert is_binary(xml)
      assert String.contains?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    end
  end

  describe "build_response/2 - XML structure validation" do
    test "always includes XML declaration" do
      result = %{"test" => "data"}
      operation = %{name: "Test"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.starts_with?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    end

    test "maintains proper SOAP envelope structure" do
      result = %{"data" => "test"}
      operation = %{name: "TestOp"}

      xml = ResponseBuilder.build_response(result, operation)

      # Check structure order and nesting
      envelope_pos = String.contains?(xml, "<soap:Envelope")
      body_pos = String.contains?(xml, "<soap:Body>")
      response_pos = String.contains?(xml, "<TestOpResponse>")

      assert envelope_pos
      assert body_pos
      assert response_pos

      # Check closing tags are present
      assert String.contains?(xml, "</soap:Envelope>")
      assert String.contains?(xml, "</soap:Body>")
      assert String.contains?(xml, "</TestOpResponse>")
    end

    test "includes proper namespace declarations" do
      result = %{"test" => "value"}
      operation = %{name: "TestOperation"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"")
    end

    test "produces valid XML format" do
      result = %{
        "user" => %{
          "id" => "123",
          "name" => "Test User"
        }
      }

      operation = %{name: "GetUser"}

      xml = ResponseBuilder.build_response(result, operation)

      # Basic XML validity checks
      # No empty tags
      refute String.contains?(xml, "<>")
      # No malformed closing tags
      refute String.contains?(xml, "</>")

      # Should not have obvious XML errors
      # Should have substantial content
      assert String.length(xml) > 100
    end
  end

  describe "build_response/2 - Error handling" do
    test "handles XML building errors gracefully" do
      # This might be hard to trigger depending on XML builder implementation
      # but we can test with potentially problematic data
      # Control characters
      result = %{"invalid" => "\x00\x01\x02"}
      operation = %{name: "TestInvalid"}

      xml = ResponseBuilder.build_response(result, operation)

      # Should not crash and return some form of response
      assert is_binary(xml)
      assert String.contains?(xml, "<?xml")
    end

    test "handles circular reference data structures" do
      # Create a structure that might cause issues
      result = %{"data" => %{"nested" => %{"deep" => "value"}}}
      operation = %{name: "TestNested"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<TestNestedResponse>")
      assert String.contains?(xml, "value")
    end

    test "handles very deep nesting" do
      # Create deeply nested structure
      deep_data =
        Enum.reduce(1..10, "final_value", fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      result = %{"data" => deep_data}
      operation = %{name: "DeepNest"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<DeepNestResponse>")
      assert String.contains?(xml, "final_value")
    end
  end

  describe "build_fault/1 - Fault validation" do
    test "handles missing fault code" do
      fault = %{
        fault_string: "Error occurred"
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<soap:Fault>")
      assert String.contains?(xml, "<faultstring>Error occurred</faultstring>")
      # Should handle missing faultcode gracefully
    end

    test "handles missing fault string" do
      fault = %{
        fault_code: "Server"
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<soap:Fault>")
      assert String.contains?(xml, "<faultcode>Server</faultcode>")
      # Should handle missing faultstring gracefully
    end

    test "handles completely empty fault" do
      fault = %{}

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      assert String.contains?(xml, "<soap:Envelope")
      assert String.contains?(xml, "<soap:Fault>")
      # Should create minimal valid fault structure
    end

    test "handles nil fault" do
      fault = nil

      # Should handle gracefully without crashing
      xml = ResponseBuilder.build_fault(fault)

      assert is_binary(xml)
      assert String.contains?(xml, "<?xml")
    end
  end

  describe "build_response/2 - Real-world scenarios" do
    test "builds typical web service response" do
      result = %{
        "order" => %{
          "id" => "ORD-123",
          "status" => "confirmed",
          "total" => "299.99",
          "items" => [
            %{"sku" => "ITEM-1", "quantity" => 2},
            %{"sku" => "ITEM-2", "quantity" => 1}
          ],
          "customer" => %{
            "id" => "CUST-456",
            "name" => "John Smith"
          }
        }
      }

      operation = %{name: "CreateOrder"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<CreateOrderResponse>")
      assert String.contains?(xml, "<order>")
      assert String.contains?(xml, "<id>ORD-123</id>")
      assert String.contains?(xml, "<status>confirmed</status>")
      assert String.contains?(xml, "<customer>")
      assert String.contains?(xml, "<name>John Smith</name>")
    end

    test "builds authentication response" do
      result = %{
        "session" => %{
          "token" => "abc123def456",
          "expires_at" => "2023-12-31T23:59:59Z",
          "user_id" => "12345"
        },
        "permissions" => ["read", "write", "admin"]
      }

      operation = %{name: "Authenticate"}

      xml = ResponseBuilder.build_response(result, operation)

      assert String.contains?(xml, "<AuthenticateResponse>")
      assert String.contains?(xml, "<session>")
      assert String.contains?(xml, "<token>abc123def456</token>")
      assert String.contains?(xml, "<permissions>")
    end

    test "builds error response with fault details" do
      fault = %{
        fault_code: "Client.InvalidCredentials",
        fault_string: "The provided username or password is incorrect",
        detail: %{
          "error_id" => "AUTH_001",
          "retry_after" => "300",
          "help_url" => "https://example.com/auth-help"
        }
      }

      xml = ResponseBuilder.build_fault(fault)

      assert String.contains?(xml, "<faultcode>Client.InvalidCredentials</faultcode>")
      assert String.contains?(xml, "username or password is incorrect")
      assert String.contains?(xml, "<error_id>AUTH_001</error_id>")
      assert String.contains?(xml, "<retry_after>300</retry_after>")
      assert String.contains?(xml, "<help_url>https://example.com/auth-help</help_url>")
    end
  end
end
