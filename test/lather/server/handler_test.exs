defmodule Lather.Server.HandlerTest do
  use ExUnit.Case, async: true

  alias Lather.Server.Handler

  defmodule TestService do
    use Lather.Server

    @service_name "HandlerTestService"

    soap_operation "Echo" do
      input do
        parameter("message", "string", required: true)
      end

      output do
        parameter("echo", "string")
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  @headers [{"content-type", "text/xml"}]

  defp envelope(inner) do
    ~s(<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body>#{inner}</soap:Body></soap:Envelope>)
  end

  describe "malformed requests (issue #12)" do
    test "malformed XML returns a 400 Client fault instead of raising" do
      assert {:error, 400, _headers, xml} =
               Handler.handle_request("POST", "/soap", @headers, "<not xml", TestService)

      assert xml =~ "<faultcode>Client</faultcode>"
      assert xml =~ "Invalid SOAP request"
    end

    test "structural errors keep their message" do
      assert {:error, 400, _headers, xml} =
               Handler.handle_request("POST", "/soap", @headers, "<Nope/>", TestService)

      assert xml =~ "No SOAP envelope found"
    end

    test "fault strings are XML-escaped" do
      assert {:error, 400, _headers, xml} =
               Handler.handle_request("POST", "/soap", @headers, "", TestService)

      {:ok, _} = Lather.Xml.Parser.parse(xml)
    end
  end

  describe "response shape (issue #13)" do
    test "successful responses are wrapped once, in <EchoResponse>" do
      body = envelope("<Echo><message>hi</message></Echo>")

      assert {:ok, 200, _headers, xml} =
               Handler.handle_request("POST", "/soap", @headers, body, TestService)

      refute xml =~ "<Response>"
      assert xml =~ "<EchoResponse>"
      assert xml =~ "<echo>hi</echo>"

      {:ok, parsed} = Lather.Xml.Parser.parse(xml)
      assert parsed["soap:Envelope"]["soap:Body"] == %{"EchoResponse" => %{"echo" => "hi"}}
    end

    test "Handler and Plug produce identical bodies for the same request" do
      import Plug.Test
      body = envelope("<Echo><message>hi</message></Echo>")

      {:ok, 200, _headers, handler_xml} =
        Handler.handle_request("POST", "/soap", @headers, body, TestService)

      conn =
        conn(:post, "/soap", body)
        |> Plug.Conn.put_req_header("content-type", "text/xml")
        |> Lather.Server.Plug.call(Lather.Server.Plug.init(service: TestService))

      assert conn.resp_body == handler_xml
    end
  end

  describe "routing (issue #14)" do
    test "POST to a path containing wsdl is still a SOAP call" do
      body = envelope("<Echo><message>hi</message></Echo>")

      assert {:ok, 200, _headers, xml} =
               Handler.handle_request("POST", "/wsdlgateway/soap", @headers, body, TestService)

      assert xml =~ "<EchoResponse>"
    end

    test "GET serves the WSDL regardless of path" do
      assert {:ok, 200, _headers, wsdl} =
               Handler.handle_request("GET", "/soap", @headers, "", TestService)

      assert wsdl =~ "<definitions" or wsdl =~ "<wsdl:definitions"
    end

    test "GET returns 405 when WSDL generation is disabled" do
      assert {:error, 405, _, _} =
               Handler.handle_request("GET", "/soap?wsdl", @headers, "", TestService,
                 generate_wsdl: false
               )
    end

    test "other methods return 405" do
      assert {:error, 405, _, xml} =
               Handler.handle_request("PUT", "/soap", @headers, "", TestService)

      assert xml =~ "Method not allowed"
    end
  end

  describe "parameter type validation (issue #16)" do
    defmodule TypedService do
      use Lather.Server

      soap_operation "Typed" do
        input do
          parameter("n", :integer, required: true)
          parameter("d", "decimal")
          parameter("b", :boolean)
          parameter("when", "xsd:dateTime")
          parameter("day", :date)
          parameter("s", :string)
        end

        output do
          parameter("ok", :string)
        end
      end

      def typed(params), do: {:ok, %{"ok" => inspect(params)}}
    end

    defp typed(inner) do
      Handler.handle_request(
        "POST",
        "/soap",
        @headers,
        envelope("<Typed>#{inner}</Typed>"),
        TypedService
      )
    end

    test "valid lexical values pass" do
      assert {:ok, 200, _, _} =
               typed(
                 "<n>42</n><d>1.5</d><b>true</b><when>2026-01-02T03:04:05Z</when><day>2026-01-02</day><s></s>"
               )

      assert {:ok, 200, _, _} =
               typed("<n>-7</n><d>10</d><b>0</b><when>2026-01-02T03:04:05</when>")
    end

    test "non-numeric integers and decimals are rejected with a Client fault" do
      assert {:error, 500, _, xml} = typed("<n>abc</n>")
      assert xml =~ "<faultcode>Client</faultcode>"
      assert xml =~ "Invalid n: invalid integer format"

      assert {:error, 500, _, xml} = typed("<n>1</n><d>1,5</d>")
      assert xml =~ "Invalid d: invalid decimal format"
    end

    test "bad booleans and dates are rejected" do
      assert {:error, 500, _, xml} = typed("<n>1</n><b>yes</b>")
      assert xml =~ "invalid boolean format"

      assert {:error, 500, _, xml} = typed("<n>1</n><day>02/01/2026</day>")
      assert xml =~ "invalid date format"
    end

    test "structured content for a simple type is a Client fault, not a crash" do
      assert {:error, 500, _, xml} = typed("<n>1</n><when><y/></when>")
      assert xml =~ "<faultcode>Client</faultcode>"
      assert xml =~ "Invalid when: expected a dateTime value, got an element with children"

      assert {:error, 500, _, xml} = typed("<n>1</n><s><b/></s>")
      assert xml =~ "Invalid s: expected a string value"
    end
  end
end
