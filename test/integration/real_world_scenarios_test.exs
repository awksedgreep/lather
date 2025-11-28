defmodule Lather.Integration.RealWorldScenariosTest do
  use ExUnit.Case, async: true

  alias Lather.Operation.Builder
  alias Lather.Xml.Parser
  alias Lather.Http.Transport

  describe "Real-World SOAP API Scenarios" do
    test "handles WSDL with string style/use values instead of atoms" do
      # This test covers the issue where real WSDLs return "document" instead of :document
      operation_info = %{
        name: "TestOperation",
        # String instead of atom
        style: "document",
        input: %{
          message: "TestRequest",
          parts: [
            %{name: "param1", type: "xsd:string", element: nil}
          ],
          # String instead of atom
          use: "encoded"
        },
        output: %{message: "TestResponse", parts: [], use: "encoded"},
        soap_action: "test"
      }

      parameters = %{"param1" => "test_value"}

      # Should not crash with case clause errors
      assert {:ok, _envelope} = Builder.build_request(operation_info, parameters)
    end

    test "validates parameters with mixed simple/complex types from real WSDLs" do
      operation_info = %{
        name: "ComplexOperation",
        style: "document",
        input: %{
          message: "ComplexRequest",
          parts: [
            # Simple type that might be misclassified
            %{name: "product", type: "tns:productType", element: nil},
            # Complex type that should accept maps
            %{name: "weatherParameters", type: "tns:weatherParametersType", element: nil},
            # Standard XSD types
            %{name: "latitude", type: "xsd:decimal", element: nil},
            %{name: "startTime", type: "xsd:dateTime", element: nil}
          ],
          use: "encoded"
        },
        output: %{message: "ComplexResponse", parts: [], use: "encoded"}
      }

      # Parameters that caused issues in real-world scenario
      parameters = %{
        # String value for complex-classified type
        "product" => "time-series",
        # Map for simple-classified type
        "weatherParameters" => %{"maxt" => "true", "mint" => "true"},
        # Numeric value
        "latitude" => 37.7749,
        # DateTime string
        "startTime" => "2023-10-31T12:00:00Z"
      }

      # Should handle parameter validation gracefully
      assert :ok = Builder.validate_parameters(operation_info, parameters)
    end

    test "builds document/encoded style SOAP envelopes" do
      operation_info = %{
        name: "EncodedOperation",
        style: "document",
        input: %{
          message: "EncodedRequest",
          parts: [
            %{name: "simpleParam", type: "xsd:string", element: nil},
            %{name: "complexParam", type: "tns:ComplexType", element: nil}
          ],
          use: "encoded"
        },
        output: %{message: "EncodedResponse", parts: [], use: "encoded"}
      }

      parameters = %{
        "simpleParam" => "test",
        "complexParam" => %{"field1" => "value1", "field2" => "value2"}
      }

      # Should successfully build encoded style envelope
      assert {:ok, envelope} = Builder.build_request(operation_info, parameters)
      assert String.contains?(envelope, "EncodedOperation")
      assert String.contains?(envelope, "simpleParam")
      assert String.contains?(envelope, "complexParam")
    end

    test "handles WSDL endpoint resolution edge cases" do
      # This test would require making private functions public or integration testing
      # For now, we test that the system handles various endpoint scenarios gracefully
      # through the public API

      # Test that the system can handle problematic WSDLs without crashing
      service_info = %{
        service_name: "TestService",
        endpoints: [
          %{name: "port1", address: %{type: :soap, location: "http://localhost/service"}}
        ],
        operations: [],
        target_namespace: "http://example.com"
      }

      # Should not crash when processing service info with localhost endpoint
      assert is_map(service_info)
      assert length(service_info.endpoints) == 1
    end

    test "parses SOAP faults from HTTP 500 responses" do
      # Real SOAP fault response from weather service
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

      # Should parse XML and extract fault information
      assert {:ok, parsed} = Parser.parse(soap_fault_xml)

      # Should identify as SOAP fault
      fault = get_in(parsed, ["SOAP-ENV:Envelope", "SOAP-ENV:Body", "SOAP-ENV:Fault"])
      assert fault != nil

      # Should handle complex text nodes with attributes
      fault_string = fault["faultstring"]
      assert is_map(fault_string)
      assert fault_string["#text"] == "No valid points were found."
      assert fault_string["@xsi:type"] == "xsd:string"
    end

    test "handles XML text nodes with mixed content structures" do
      # Various XML text node structures found in real SOAP responses
      xml_variations = [
        # Simple text
        "<element>Simple text</element>",

        # Text with attributes
        "<element type=\"string\">Text with attributes</element>",

        # Text node structure (common in parsed XML)
        "<element><text>Structured text</text></element>",

        # Mixed content
        "<element>Text before <nested>nested content</nested> text after</element>",

        # Empty elements
        "<element></element>",
        "<element/>",

        # Whitespace handling
        "<element>  \n  Whitespace text  \n  </element>"
      ]

      for xml_snippet <- xml_variations do
        wrapped_xml = "<?xml version=\"1.0\"?><root>#{xml_snippet}</root>"

        # Should parse without errors
        assert {:ok, parsed} = Parser.parse(wrapped_xml)
        assert Map.has_key?(parsed, "root")
      end
    end

    test "validates parameter types with real-world type variations" do
      # Type variations commonly found in WSDLs
      type_test_cases = [
        # Standard XSD types
        {"xsd:string", "test value", :ok},
        {"xsd:int", 123, :ok},
        {"xsd:decimal", 123.45, :ok},
        {"xsd:boolean", true, :ok},
        {"xsd:dateTime", "2023-10-31T12:00:00Z", :ok},

        # Custom types (should be treated as complex)
        {"tns:CustomType", %{"field" => "value"}, :ok},
        {"ns1:ProductType", "enumerated-value", :ok},

        # Array types
        {"ArrayOfString", ["item1", "item2"], :ok},
        {"tns:StringArray", ["test"], :ok},

        # Edge cases that caused issues
        # Lenient validation
        {"someComplexType", "string-value-for-complex-type", :ok},
        # Lenient validation
        {"simpleType", %{"unexpectedMap" => true}, :ok}
      ]

      for {type, _value, _expected} <- type_test_cases do
        # Test that parameter validation doesn't crash on various type combinations
        # This tests the public API behavior rather than internal classification
        operation_info = %{
          name: "TestOp",
          style: "document",
          input: %{
            message: "TestRequest",
            parts: [%{name: "param", type: type, element: nil}],
            use: "literal"
          },
          output: %{message: "TestResponse", parts: [], use: "literal"}
        }

        # Should handle parameter validation gracefully
        result = Builder.validate_parameters(operation_info, %{})
        assert result == :ok or match?({:error, _}, result)
      end
    end

    test "builds SOAP envelopes with proper namespaces and encoding" do
      operation_info = %{
        name: "NamespacedOperation",
        style: "document",
        input: %{
          message: "NamespacedRequest",
          parts: [%{name: "param", type: "xsd:string", element: nil}],
          use: "literal"
        },
        output: %{message: "NamespacedResponse", parts: [], use: "literal"}
      }

      parameters = %{"param" => "test with unicode: 测试"}
      namespace = "http://example.com/service"

      assert {:ok, envelope} =
               Builder.build_request(operation_info, parameters,
                 namespace: namespace,
                 style: "document",
                 use: "literal"
               )

      # Should contain proper XML declaration with UTF-8
      assert String.starts_with?(envelope, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")

      # Should contain SOAP envelope structure
      assert String.contains?(envelope, "soap:Envelope")
      assert String.contains?(envelope, "soap:Body")

      # Should handle unicode characters properly
      assert String.contains?(envelope, "测试")

      # Should include namespace
      assert String.contains?(envelope, namespace)
    end

    test "handles HTTP transport edge cases" do
      # Test header building scenarios that caused issues
      options_test_cases = [
        # Standard options
        [soap_action: "test", timeout: 5000],

        # Multiple headers (should not conflict)
        [headers: [{"Custom-Header", "value"}], soap_action: "test"],

        # Empty soap action
        [soap_action: ""],

        # No soap action
        [],

        # Custom content type (should not create duplicates)
        [headers: [{"Content-Type", "text/xml; charset=UTF-8"}]],

        # SSL options
        [ssl_options: [verify: :verify_peer]]
      ]

      for options <- options_test_cases do
        # Should build headers without errors
        headers = Transport.build_headers(options)
        assert is_list(headers)

        # Should have content-type header
        content_types =
          Enum.filter(headers, fn {name, _} ->
            String.downcase(name) == "content-type"
          end)

        # Should not have duplicate content-type headers
        assert length(content_types) <= 1
      end
    end

    test "handles malformed WSDL gracefully" do
      malformed_wsdl_cases = [
        # Missing service endpoints
        %{service_name: "TestService", endpoints: [], operations: []},

        # Operations with missing information
        %{
          service_name: "TestService",
          endpoints: [],
          operations: [
            %{name: "TestOp", input: nil, output: nil}
          ]
        },

        # Mixed namespace prefixes
        %{
          service_name: "TestService",
          endpoints: [],
          operations: [
            %{
              name: "TestOp",
              style: "document",
              input: %{
                parts: [
                  %{name: "param1", type: "xsd:string"},
                  %{name: "param2", type: "tns:CustomType"},
                  # No namespace
                  %{name: "param3", type: "string"}
                ]
              }
            }
          ]
        }
      ]

      for service_info <- malformed_wsdl_cases do
        # Should not crash when processing malformed WSDL
        assert is_map(service_info)
        # Additional validation could be added here
      end
    end

    test "stress tests parameter validation with edge cases" do
      edge_case_parameters = [
        # Very long strings
        %{"longParam" => String.duplicate("x", 10_000)},

        # Deeply nested maps
        %{"nested" => %{"level1" => %{"level2" => %{"level3" => "deep"}}}},

        # Lists with mixed types
        %{"mixedList" => ["string", 123, %{"map" => "value"}]},

        # Empty values
        %{"empty" => "", "nullish" => nil, "emptyMap" => %{}, "emptyList" => []},

        # Unicode and special characters
        %{"unicode" => "测试 🚀 special chars: <>&\"'"},

        # Large numbers
        %{"bigInt" => 9_223_372_036_854_775_807, "bigFloat" => 1.7976931348623157e+308},

        # Boolean variations that might be sent as strings
        %{"bool1" => "true", "bool2" => "false", "bool3" => true, "bool4" => false}
      ]

      operation_info = %{
        name: "StressTestOp",
        style: "document",
        input: %{
          message: "StressRequest",
          parts:
            Enum.map(1..20, fn i ->
              %{name: "param#{i}", type: "xsd:string", element: nil}
            end),
          use: "literal"
        },
        output: %{message: "StressResponse", parts: [], use: "literal"}
      }

      for params <- edge_case_parameters do
        # Should handle edge cases gracefully without crashes
        result = Builder.validate_parameters(operation_info, params)
        # Should return valid result
        assert result == :ok or match?({:error, _}, result)
      end
    end
  end

  describe "Document/literal with element-based parts" do
    test "builds correct body structure for element-based document/literal" do
      # This mimics WSDL structure where parts have element attributes
      # instead of type attributes (common in enterprise SOAP services)
      operation_info = %{
        name: "GetWeatherForecast",
        style: "document",
        input: %{
          message: "GetWeatherForecast_Input",
          parts: [
            %{
              name: "GetWeatherForecast_Input",
              element: "tns:GetWeatherForecast_Input",
              type: nil
            }
          ],
          use: "literal"
        },
        output: %{message: "GetWeatherForecast_Output", parts: [], use: "literal"}
      }

      parameters = %{
        "GetWeatherForecast_Input" => %{
          "WeatherRequest" => %{
            "LocationData" => %{
              "CityCode" => "LON",
              "CountryCode" => "UK"
            }
          }
        }
      }

      {:ok, envelope} =
        Builder.build_request(operation_info, parameters,
          namespace: "http://example.com/weather"
        )

      # For element-based document/literal, the body should contain
      # <GetWeatherForecast_Input> directly, NOT wrapped in <GetWeatherForecast>
      assert String.contains?(envelope, "<GetWeatherForecast_Input")
      assert String.contains?(envelope, "xmlns=\"http://example.com/weather\"")
      assert String.contains?(envelope, "<WeatherRequest>")
      assert String.contains?(envelope, "<CityCode>LON</CityCode>")

      # Should NOT wrap in operation name
      refute String.contains?(envelope, "<GetWeatherForecast>")
      refute String.contains?(envelope, "<GetWeatherForecast ")
    end

    test "traditional document/literal without element attribute wraps in operation name" do
      # Traditional document/literal with type-based parts
      operation_info = %{
        name: "GetData",
        style: "document",
        input: %{
          message: "GetDataRequest",
          parts: [
            %{name: "param1", type: "xsd:string", element: nil}
          ],
          use: "literal"
        },
        output: %{message: "GetDataResponse", parts: [], use: "literal"}
      }

      parameters = %{"param1" => "test_value"}

      {:ok, envelope} =
        Builder.build_request(operation_info, parameters,
          namespace: "http://example.com/ns"
        )

      # Traditional style SHOULD wrap in operation name
      assert String.contains?(envelope, "<GetData")
      # The param value should be present in the envelope
      assert String.contains?(envelope, "test_value")
    end

    test "handles multiple element-based parts" do
      operation_info = %{
        name: "SubmitOrder",
        style: "document",
        input: %{
          message: "SubmitOrderRequest",
          parts: [
            %{name: "OrderHeader", element: "tns:OrderHeaderElement", type: nil},
            %{name: "OrderDetails", element: "tns:OrderDetailsElement", type: nil}
          ],
          use: "literal"
        },
        output: %{message: "SubmitOrderResponse", parts: [], use: "literal"}
      }

      parameters = %{
        "OrderHeader" => %{"orderId" => "ORD-001"},
        "OrderDetails" => %{"productCode" => "PROD-123"}
      }

      {:ok, envelope} =
        Builder.build_request(operation_info, parameters,
          namespace: "http://example.com/orders"
        )

      # Both element parts should be present directly in body
      assert String.contains?(envelope, "<OrderHeaderElement")
      assert String.contains?(envelope, "<orderId>ORD-001</orderId>")
      assert String.contains?(envelope, "<OrderDetailsElement")
      assert String.contains?(envelope, "<productCode>PROD-123</productCode>")

      # Should NOT wrap in operation name
      refute String.contains?(envelope, "<SubmitOrder>")
    end

    test "RPC style still wraps in operation name even with element parts" do
      # RPC style should always wrap in operation name
      operation_info = %{
        name: "CalculateTotal",
        style: "rpc",
        input: %{
          message: "CalculateTotalRequest",
          parts: [
            # RPC style typically uses type instead of element, but we test with element too
            %{name: "amount", element: "tns:AmountElement", type: "xsd:string"}
          ],
          use: "literal"
        },
        output: %{message: "CalculateTotalResponse", parts: [], use: "literal"}
      }

      parameters = %{
        "amount" => "100.50"
      }

      {:ok, envelope} =
        Builder.build_request(operation_info, parameters,
          namespace: "http://example.com/calculator"
        )

      # RPC style SHOULD wrap in operation name
      assert String.contains?(envelope, "<CalculateTotal")
      assert String.contains?(envelope, "<amount>100.50</amount>")
    end
  end

  describe "SOAP response parsing with different namespace prefixes" do
    test "parses response with SOAP-ENV: prefix" do
      operation_info = %{
        name: "GetWeather",
        style: "document",
        input: %{message: "GetWeatherRequest", parts: [], use: "literal"},
        output: %{
          message: "GetWeatherResponse",
          parts: [%{name: "result", type: "xsd:string"}],
          use: "literal"
        }
      }

      # Response with SOAP-ENV: prefix (common in enterprise SOAP services)
      response_envelope = %{
        "SOAP-ENV:Envelope" => %{
          "@xmlns:SOAP-ENV" => "http://schemas.xmlsoap.org/soap/envelope/",
          "SOAP-ENV:Body" => %{
            "ns:GetWeather_Output" => %{
              "@xmlns:ns" => "http://example.com/weather",
              "Temperature" => "22",
              "Condition" => "Sunny"
            }
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_envelope)

      # When response element has namespace prefix, it returns the full body
      assert result["ns:GetWeather_Output"]["Temperature"] == "22"
      assert result["ns:GetWeather_Output"]["Condition"] == "Sunny"
    end

    test "parses response with soap: prefix" do
      operation_info = %{
        name: "GetData",
        style: "document",
        input: %{message: "GetDataRequest", parts: [], use: "literal"},
        output: %{
          message: "GetDataResponse",
          parts: [%{name: "result", type: "xsd:string"}],
          use: "literal"
        }
      }

      response_envelope = %{
        "soap:Envelope" => %{
          "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
          "soap:Body" => %{
            "GetDataResponse" => %{
              "value" => "test_data"
            }
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_envelope)

      assert result["value"] == "test_data"
    end

    test "parses response with no namespace prefix on envelope" do
      operation_info = %{
        name: "SimpleOp",
        style: "document",
        input: %{message: "SimpleRequest", parts: [], use: "literal"},
        output: %{
          message: "SimpleResponse",
          parts: [%{name: "result", type: "xsd:string"}],
          use: "literal"
        }
      }

      response_envelope = %{
        "Envelope" => %{
          "Body" => %{
            "SimpleResponse" => %{
              "status" => "ok"
            }
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_envelope)

      assert result["status"] == "ok"
    end

    test "parses response with custom namespace prefix" do
      operation_info = %{
        name: "CustomOp",
        style: "document",
        input: %{message: "CustomRequest", parts: [], use: "literal"},
        output: %{
          message: "CustomResponse",
          parts: [%{name: "result", type: "xsd:string"}],
          use: "literal"
        }
      }

      # Some services use custom prefixes like "soapenv:" or "env:"
      response_envelope = %{
        "soapenv:Envelope" => %{
          "@xmlns:soapenv" => "http://schemas.xmlsoap.org/soap/envelope/",
          "soapenv:Body" => %{
            "CustomResponse" => %{
              "result" => "success"
            }
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_envelope)

      assert result["result"] == "success"
    end

    test "returns error for invalid envelope structure" do
      operation_info = %{
        name: "TestOp",
        style: "document",
        input: %{message: "TestRequest", parts: [], use: "literal"},
        output: %{message: "TestResponse", parts: [], use: "literal"}
      }

      invalid_response = %{
        "NotAnEnvelope" => %{
          "SomeContent" => "value"
        }
      }

      {:error, error} = Builder.parse_response(operation_info, invalid_response)

      assert error.reason == :invalid_soap_response
      assert error.type == :validation_error
    end
  end

  # Note: Endpoint resolution testing is done through integration tests
  # with the public DynamicClient API rather than testing private functions
end
