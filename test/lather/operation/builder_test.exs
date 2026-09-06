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

    test "unwraps response element when body key has namespace prefix (SAP-style)" do
      # Enterprise SOAP servers use namespace-prefixed element names such as
      # "ns0:MT_Employee_Lookup_Rp" in the body, while the WSDL output
      # message is "tns:MT_Employee_Lookup_Rp". The local name matches but
      # the body prefix is different — the parser must use suffix matching.
      operation_info = %{
        name: "MT_Employee_Lookup",
        output: %{
          message: "tns:MT_Employee_Lookup_Rp",
          parts: [%{name: "MESSAGE", type: "xsd:string"}]
        }
      }

      response_body = %{
        "SOAP:Envelope" => %{
          "@xmlns:SOAP" => "http://schemas.xmlsoap.org/soap/envelope/",
          "SOAP:Body" => %{
            "ns0:MT_Employee_Lookup_Rp" => %{
              "@xmlns:ns0" => "http://example.com/HR/Employee/Lookup",
              "TENANT" => "ACME_CORP",
              "REQ_ID" => "001",
              "REQ_DATE" => "28042026",
              "MESSAGE" => "Employee not found"
            }
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_body, style: :document)

      assert result["TENANT"] == "ACME_CORP"
      assert result["REQ_ID"] == "001"
      assert result["REQ_DATE"] == "28042026"
      assert result["MESSAGE"] == "Employee not found"

      refute Map.has_key?(result, "ns0:MT_Employee_Lookup_Rp"),
             "response should be unwrapped from the operation element"
    end

    test "parses SAP PI/PO response with n0 prefix and nested complex structure" do
      # Real-world SAP PI/PO response: the body element carries a non-standard
      # prefix (n0:), two xmlns declarations on the same element, and a deeply
      # nested payload with repeated child structures.
      operation_info = %{
        name: "SI_Movilidad_Registro_SYN_OUT",
        output: %{
          message: "tns:MT_Movilidad_Registro_Rp",
          parts: [%{name: "MT_Movilidad_Registro_Rp", type: "tns:MT_Movilidad_Registro_Rp"}]
        }
      }

      response_body = %{
        "soap:Envelope" => %{
          "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
          "soap:Body" => %{
            "n0:MT_Movilidad_Registro_Rp" => %{
              "@xmlns:n0" => "http://fcc.es/HRSAPECC/HCM/PA/Movilidad/Registro",
              "@xmlns:prx" => "urn:sap.com:proxy:EHD:/1SAI/TAS820FE76BCF9B749B0AE4:750",
              "GROUPID" => "ACME",
              "ID_ENV" => "001",
              "FEC_ENV" => "05052026",
              "VIAJEROS" => %{
                "DATOS_PERSONALES" => %{
                  "ID_SAP" => "00015665",
                  "VORNA" => "JOHN",
                  "NACHN" => "DOE",
                  "NACH2" => "SMITH"
                },
                "ESTRUCTURA_ORGANIZATIVA" => %{
                  "BUKRS" => "S400",
                  "BUTXT" => "EXAMPLE CORP S.A.",
                  "GSBER" => "1KKR",
                  "GTEXT" => "IT SERVICES",
                  "NEGOCIO" => "TECH"
                }
              }
            }
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_body, style: :document)

      # Top-level fields are accessible directly after unwrapping the operation element
      assert result["GROUPID"] == "ACME"
      assert result["ID_ENV"] == "001"
      assert result["FEC_ENV"] == "05052026"

      # Nested structure is preserved intact
      assert result["VIAJEROS"]["DATOS_PERSONALES"]["ID_SAP"] == "00015665"
      assert result["VIAJEROS"]["DATOS_PERSONALES"]["VORNA"] == "JOHN"
      assert result["VIAJEROS"]["DATOS_PERSONALES"]["NACHN"] == "DOE"
      assert result["VIAJEROS"]["DATOS_PERSONALES"]["NACH2"] == "SMITH"

      assert result["VIAJEROS"]["ESTRUCTURA_ORGANIZATIVA"]["BUKRS"] == "S400"
      assert result["VIAJEROS"]["ESTRUCTURA_ORGANIZATIVA"]["BUTXT"] == "EXAMPLE CORP S.A."
      assert result["VIAJEROS"]["ESTRUCTURA_ORGANIZATIVA"]["GSBER"] == "1KKR"
      assert result["VIAJEROS"]["ESTRUCTURA_ORGANIZATIVA"]["GTEXT"] == "IT SERVICES"
      assert result["VIAJEROS"]["ESTRUCTURA_ORGANIZATIVA"]["NEGOCIO"] == "TECH"

      # The operation wrapper element must be unwrapped
      refute Map.has_key?(result, "n0:MT_Movilidad_Registro_Rp"),
             "response should be unwrapped from the n0-prefixed operation element"
    end

    test "unwraps response element with non-standard suffix (no Response/Output ending)" do
      # Ensures get_response_element_name uses base_name directly instead of
      # appending "Response" when the output message name doesn't match known suffixes.
      operation_info = %{
        name: "SendData",
        output: %{
          message: "tns:SendData_Rp",
          parts: [%{name: "status", type: "xsd:string"}]
        }
      }

      response_body = %{
        "soap:Envelope" => %{
          "soap:Body" => %{
            "SendData_Rp" => %{"status" => "ok"}
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_body, style: :document)

      assert result == %{"status" => "ok"}
    end
  end

  describe "build_request/3 - namespace_prefix option" do
    test "builds envelope with prefixed operation element when namespace_prefix is given" do
      operation_info = %{
        name: "GetOrder",
        soap_action: "http://example.com/orders/GetOrder",
        input: %{
          message: "GetOrderRequest",
          parts: [%{name: "orderId", type: "xsd:string"}]
        },
        output: %{
          message: "tns:GetOrderResponse",
          parts: [%{name: "status", type: "xsd:string"}]
        }
      }

      {:ok, envelope} =
        Builder.build_request(operation_info, %{"orderId" => "42"},
          namespace: "http://example.com/orders",
          namespace_prefix: "ns0"
        )

      assert String.contains?(envelope, "<ns0:GetOrder")
      assert String.contains?(envelope, "xmlns:ns0=\"http://example.com/orders\"")
      assert String.contains?(envelope, "<orderId>42</orderId>")
      refute String.contains?(envelope, "xmlns=\"http://example.com/orders\"")
    end

    test "build_request without namespace_prefix preserves default-namespace behaviour" do
      operation_info = %{
        name: "GetOrder",
        soap_action: "http://example.com/orders/GetOrder",
        input: %{
          message: "GetOrderRequest",
          parts: [%{name: "orderId", type: "xsd:string"}]
        },
        output: %{
          message: "tns:GetOrderResponse",
          parts: [%{name: "status", type: "xsd:string"}]
        }
      }

      {:ok, envelope} =
        Builder.build_request(operation_info, %{"orderId" => "42"},
          namespace: "http://example.com/orders"
        )

      assert String.contains?(envelope, "<GetOrder")
      assert String.contains?(envelope, "xmlns=\"http://example.com/orders\"")
      refute String.contains?(envelope, "xmlns:ns0")
    end

    test "prefixed request response still parses correctly via suffix matching" do
      operation_info = %{
        name: "GetOrder",
        soap_action: "http://example.com/orders/GetOrder",
        input: %{
          message: "GetOrderRequest",
          parts: [%{name: "orderId", type: "xsd:string"}]
        },
        output: %{
          message: "tns:GetOrderResponse",
          parts: [%{name: "status", type: "xsd:string"}]
        }
      }

      response_body = %{
        "soap:Envelope" => %{
          "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
          "soap:Body" => %{
            "ns0:GetOrderResponse" => %{
              "@xmlns:ns0" => "http://example.com/orders",
              "status" => "shipped"
            }
          }
        }
      }

      {:ok, result} = Builder.parse_response(operation_info, response_body, style: :document)

      assert result["status"] == "shipped"
    end
  end

  describe "build_request/3 - namespace_prefix with element-based document/literal" do
    @element_based_operation %{
      name: "SI_CreateOrder_SYN_OUT",
      soap_action: "http://example.com/orders",
      style: :document,
      documentation: "",
      input: %{
        message: "CreateOrderRequest",
        parts: [
          %{
            name: "CreateOrderRequest",
            type: "tns:CreateOrderRequest",
            element: "tns:CreateOrderRequest"
          }
        ],
        use: :literal
      },
      output: %{message: "CreateOrderResponse", parts: []}
    }

    @element_based_params %{
      "CreateOrderRequest" => %{
        "customerId" => "C-42",
        "item" => "widget"
      }
    }

    test "applies namespace_prefix to element-based body element" do
      {:ok, envelope} =
        Builder.build_request(@element_based_operation, @element_based_params,
          namespace: "http://example.com/orders",
          namespace_prefix: "ns0"
        )

      assert String.contains?(envelope, "<ns0:CreateOrderRequest")
      assert String.contains?(envelope, ~s(xmlns:ns0="http://example.com/orders"))
      assert String.contains?(envelope, "<customerId>C-42</customerId>")
      refute String.contains?(envelope, ~s(xmlns="http://example.com/orders"))
    end

    test "element-based operations without namespace_prefix preserve default behaviour" do
      {:ok, envelope} =
        Builder.build_request(@element_based_operation, @element_based_params,
          namespace: "http://example.com/orders"
        )

      assert String.contains?(envelope, "<CreateOrderRequest")
      assert String.contains?(envelope, ~s(xmlns="http://example.com/orders"))
      refute String.contains?(envelope, "ns0:")
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

  describe "build_request/3 - complex and array parameters (issue #17)" do
    @create_op %{
      name: "Create",
      input: %{message: "CreateReq", parts: [%{name: "order", type: "tns:Order"}]},
      output: %{message: "CreateResp", parts: []},
      soap_action: ""
    }

    test "nested maps become nested elements instead of raising" do
      params = %{"order" => %{"customer" => %{"name" => "A", "address" => %{"city" => "X"}}}}
      {:ok, xml} = Builder.build_request(@create_op, params, namespace: "http://x")
      {:ok, parsed} = Lather.Xml.Parser.parse(xml)

      assert get_in(parsed, ["soap:Envelope", "soap:Body", "Create", "order", "customer"]) ==
               %{"name" => "A", "address" => %{"city" => "X"}}
    end

    test "lists inside complex types render as repeated siblings" do
      params = %{
        "order" => %{"tags" => ["a", "b"], "lines" => [%{"sku" => "1"}, %{"sku" => "2"}]}
      }

      {:ok, xml} = Builder.build_request(@create_op, params, namespace: "http://x")

      assert xml =~ "<tags>a</tags>"
      assert xml =~ "<tags>b</tags>"
      refute xml =~ "<tags>ab</tags>"

      {:ok, parsed} = Lather.Xml.Parser.parse(xml)
      order = get_in(parsed, ["soap:Envelope", "soap:Body", "Create", "order"])
      assert order["tags"] == ["a", "b"]
      assert order["lines"] == [%{"sku" => "1"}, %{"sku" => "2"}]
    end

    test "dates, booleans and special characters are serialised" do
      params = %{"order" => %{"when" => ~D[2026-01-02], "rush" => true, "note" => "a < b & c"}}
      {:ok, xml} = Builder.build_request(@create_op, params, namespace: "http://x")

      assert xml =~ "<when>2026-01-02</when>"
      assert xml =~ "<rush>true</rush>"
      {:ok, parsed} = Lather.Xml.Parser.parse(xml)

      assert get_in(parsed, ["soap:Envelope", "soap:Body", "Create", "order", "note"]) ==
               "a < b & c"
    end

    @array_op %{
      name: "Tag",
      input: %{message: "TagReq", parts: [%{name: "names", type: "tns:ArrayOfString"}]},
      output: %{message: "TagResp", parts: []},
      soap_action: ""
    }

    test "array parts wrap items in <item> by default" do
      {:ok, xml} =
        Builder.build_request(@array_op, %{"names" => ["A", "B"]}, namespace: "http://x")

      {:ok, parsed} = Lather.Xml.Parser.parse(xml)

      assert get_in(parsed, ["soap:Envelope", "soap:Body", "Tag", "names"]) == %{
               "item" => ["A", "B"]
             }
    end

    test "array parts use the repeating element name from WSDL types when given" do
      types = [
        %{
          category: :complex_type,
          name: "ArrayOfString",
          elements: [
            %{name: "string", type: "xsd:string", min_occurs: "0", max_occurs: "unbounded"}
          ]
        }
      ]

      {:ok, xml} =
        Builder.build_request(@array_op, %{"names" => ["A", "B"]},
          namespace: "http://x",
          types: types
        )

      {:ok, parsed} = Lather.Xml.Parser.parse(xml)

      assert get_in(parsed, ["soap:Envelope", "soap:Body", "Tag", "names"]) == %{
               "string" => ["A", "B"]
             }
    end

    test "rpc/encoded array parts are not wrapped in a #text element" do
      op =
        Map.merge(@array_op, %{
          style: :rpc,
          input: %{
            message: "TagReq",
            use: :encoded,
            parts: [%{name: "names", type: "xsd:string[]"}]
          }
        })

      {:ok, xml} = Builder.build_request(op, %{"names" => ["A", "B"]}, namespace: "http://x")

      assert xml =~ "<item>A</item>"
      assert xml =~ "<item>B</item>"
      refute xml =~ "#text"
    end

    test "element-based parts accept scalar values" do
      op = %{
        name: "Ping",
        input: %{
          message: "PingReq",
          parts: [%{name: "body", type: "tns:PingRequest", element: "tns:PingRequest"}]
        },
        output: %{message: "PingResp", parts: []},
        soap_action: ""
      }

      {:ok, xml} = Builder.build_request(op, %{"body" => "hello"}, namespace: "http://x")
      assert xml =~ ~s(<PingRequest xmlns="http://x">hello</PingRequest>)
    end
  end

  describe "validate_parameters/2 - optional parts (issue #18)" do
    @opt_op %{
      name: "Get",
      input: %{
        message: "GetReq",
        parts: [
          %{name: "id", type: "xsd:string"},
          %{name: "opt", type: "xsd:string", min_occurs: "0"}
        ]
      },
      output: %{message: "GetResp", parts: []},
      soap_action: "",
      documentation: nil
    }

    test "parts with min_occurs 0 may be omitted" do
      assert :ok = Builder.validate_parameters(@opt_op, %{"id" => "1"})
    end

    test "parts without min_occurs are still required" do
      assert {:error, %{reason: :missing_required_parameter, field: "id"}} =
               Builder.validate_parameters(@opt_op, %{"opt" => "x"})
    end

    test "validation agrees with get_operation_metadata/1" do
      meta = Builder.get_operation_metadata(@opt_op)
      assert meta.required_parameters == ["id"]
      assert meta.optional_parameters == ["opt"]
    end
  end
end
