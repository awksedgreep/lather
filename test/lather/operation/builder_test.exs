defmodule Lather.Operation.BuilderTest do
  use ExUnit.Case

  alias Lather.Operation.Builder

  describe "build_request/3 - document/literal style" do
    test "builds SOAP request with properly named parameter elements" do
      operation_info = %{
        name: "Add",
        soap_action: "Add",
        input: %{
          message: "AddRequest",
          parts: [
            %{name: "a", type: "xsd:decimal", required: true},
            %{name: "b", type: "xsd:decimal", required: true}
          ]
        },
        output: %{
          message: "AddResponse",
          parts: [%{name: "result", type: "xsd:decimal"}]
        }
      }

      params = %{"a" => 5, "b" => 3}

      {:ok, envelope} =
        Builder.build_request(operation_info, params, namespace: "http://example.com/calculator")

      # Should contain proper parameter elements
      assert String.contains?(envelope, "<a>5</a>")
      assert String.contains?(envelope, "<b>3</b>")

      # Should NOT contain #content as literal element
      refute String.contains?(envelope, "<#content>")
      refute String.contains?(envelope, "</#content>")

      # Should be valid XML structure
      assert String.contains?(envelope, "<Add")
      assert String.contains?(envelope, "</Add>")
      assert String.contains?(envelope, "soap:Envelope")
      assert String.contains?(envelope, "soap:Body")
    end

    test "builds SOAP request that can be parsed by server RequestParser" do
      operation_info = %{
        name: "Multiply",
        soap_action: "Multiply",
        input: %{
          message: "MultiplyRequest",
          parts: [
            %{name: "x", type: "xsd:int"},
            %{name: "y", type: "xsd:int"}
          ]
        },
        output: %{
          message: "MultiplyResponse",
          parts: [%{name: "result", type: "xsd:int"}]
        }
      }

      params = %{"x" => 7, "y" => 8}

      {:ok, envelope} =
        Builder.build_request(operation_info, params, namespace: "http://example.com/math")

      # Parse with server's RequestParser
      {:ok, parsed} = Lather.Server.RequestParser.parse(envelope)

      assert parsed.operation == "Multiply"
      assert parsed.params["x"] == "7"
      assert parsed.params["y"] == "8"
    end

    test "handles string parameter values" do
      operation_info = %{
        name: "Greet",
        input: %{
          message: "GreetRequest",
          parts: [%{name: "name", type: "xsd:string"}]
        },
        output: %{
          message: "GreetResponse",
          parts: [%{name: "greeting", type: "xsd:string"}]
        }
      }

      params = %{"name" => "World"}

      {:ok, envelope} =
        Builder.build_request(operation_info, params, namespace: "http://example.com")

      assert String.contains?(envelope, "<name>World</name>")
    end

    test "handles missing optional parameters" do
      operation_info = %{
        name: "Search",
        input: %{
          message: "SearchRequest",
          parts: [
            %{name: "query", type: "xsd:string"},
            %{name: "limit", type: "xsd:int"}
          ]
        },
        output: %{
          message: "SearchResponse",
          parts: []
        }
      }

      # Only provide query, not limit
      params = %{"query" => "test"}

      {:ok, envelope} =
        Builder.build_request(operation_info, params, namespace: "http://example.com")

      assert String.contains?(envelope, "<query>test</query>")
      # limit should not appear since it wasn't provided
      refute String.contains?(envelope, "<limit>")
    end
  end

  describe "parse_response/3 - response parsing" do
    test "parses response when output.message has namespace prefix" do
      # WSDL analyzer produces output.message like "tns:AddResponse"
      # but the actual XML response has just "AddResponse"
      operation_info = %{
        name: "Add",
        output: %{
          message: "tns:AddResponse",
          parts: [%{name: "result", type: "xsd:decimal"}]
        }
      }

      response_body = %{
        "soap:Envelope" => %{
          "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
          "soap:Body" => %{"AddResponse" => %{"result" => "15.0"}}
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_body, style: :document)

      # Should extract the inner response, not return the wrapped version
      assert result == %{"result" => "15.0"}
    end

    test "parses response when output.message has no namespace prefix" do
      operation_info = %{
        name: "Subtract",
        output: %{
          message: "SubtractResponse",
          parts: [%{name: "result", type: "xsd:decimal"}]
        }
      }

      response_body = %{
        "soap:Envelope" => %{
          "soap:Body" => %{"SubtractResponse" => %{"result" => "37.5"}}
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_body, style: :document)
      assert result == %{"result" => "37.5"}
    end
  end

  describe "build_request/3 - round-trip compatibility" do
    test "client request can be parsed by server" do
      # Simulates what happens in the livebook: client builds request, server parses it
      operation_info = %{
        name: "Divide",
        soap_action: "Divide",
        input: %{
          message: "DivideRequest",
          parts: [
            %{name: "dividend", type: "xsd:decimal"},
            %{name: "divisor", type: "xsd:decimal"}
          ]
        },
        output: %{
          message: "DivideResponse",
          parts: [%{name: "quotient", type: "xsd:decimal"}]
        }
      }

      params = %{"dividend" => 100, "divisor" => 4}

      {:ok, envelope} =
        Builder.build_request(operation_info, params, namespace: "http://example.com/calculator")

      # This should NOT fail with parse error
      result = Lather.Server.RequestParser.parse(envelope)
      assert {:ok, parsed} = result

      # Verify the parsed data
      assert parsed.operation == "Divide"
      assert parsed.params["dividend"] == "100"
      assert parsed.params["divisor"] == "4"
    end
  end
end
