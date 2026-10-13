defmodule Lather.Server.EnhancedPlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]

  alias Lather.Server.{EnhancedPlug, EnhancedWSDLGenerator}

  defmodule TestService do
    use Lather.Server

    @service_name "ExampleService"
    @namespace "urn:example:service"

    soap_operation "Echo" do
      description("Returns the supplied message")
      soap_action("urn:example:Echo")

      input do
        parameter("message", :string, required: true, description: "Text to echo")
      end

      output do
        parameter("echo", :string)
      end
    end

    soap_operation "Add" do
      input do
        parameter("a", :int, required: true)
        parameter("b", :int, required: true)
      end

      output do
        parameter("sum", :int)
      end
    end

    soap_type "Note" do
      type_description("A short note")
      element("text", :string, required: true, description: "Note text")
      element("tag", :string, required: false)
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}

    def add(%{"a" => a, "b" => b}) do
      {:ok, %{"sum" => String.to_integer(a) + String.to_integer(b)}}
    end
  end

  @config EnhancedPlug.init(service: TestService)

  test "the overview links to operation forms and both WSDL variants" do
    response = request(:get, "/soap")

    assert response.status == 200
    assert ["text/html; charset=utf-8"] = get_resp_header(response, "content-type")
    assert response.resp_body =~ "ExampleService - Service Overview"
    assert response.resp_body =~ "urn:example:service"
    assert response.resp_body =~ ~s(href="?op=Echo")
    assert response.resp_body =~ ~s(href="?op=Add")
    assert response.resp_body =~ ~s(href="?wsdl&enhanced=true")
  end

  test "an operation page shows its required inputs and protocol examples" do
    response = request(:get, "/soap?op=Echo")

    assert response.status == 200
    assert response.resp_body =~ "Returns the supplied message"
    assert response.resp_body =~ ~s(name="message")
    assert response.resp_body =~ ~s(data-soap-action="urn:example:Echo")
    assert response.resp_body =~ "SOAP 1.1"
    assert response.resp_body =~ "SOAP 1.2"
    assert response.resp_body =~ "Content-Type: application/json"

    numeric_form = request(:get, "/soap?op=Add")
    assert numeric_form.status == 200
    assert numeric_form.resp_body =~ ~s(type="number")
    assert numeric_form.resp_body =~ ~s(name="a")
    assert numeric_form.resp_body =~ ~s(name="b")
  end

  test "unknown operations have a 404 page and unsupported methods have a 405 page" do
    missing = request(:get, "/soap?op=Missing")
    unsupported = request(:put, "/soap")

    assert missing.status == 404
    assert missing.resp_body =~ "Operation 'Missing' not found"
    assert unsupported.status == 405
    assert unsupported.resp_body =~ "Method not allowed"
  end

  test "forms can be disabled while WSDL remains available" do
    config = EnhancedPlug.init(service: TestService, enable_forms: false)

    overview = request(:get, "/soap", "", config)
    operation = request(:get, "/soap?op=Echo", "", config)
    wsdl = request(:get, "/soap?wsdl", "", config)

    assert overview.status == 302
    assert get_resp_header(overview, "location") == ["?wsdl"]
    assert operation.status == 404
    assert operation.resp_body =~ "Form interface disabled"
    assert wsdl.status == 200
  end

  test "standard and enhanced WSDL routes return parseable documents" do
    standard = request(:get, "/soap?wsdl")
    enhanced = request(:get, "/soap?wsdl&enhanced=true")

    for response <- [standard, enhanced] do
      assert response.status == 200
      assert ["text/xml; charset=utf-8"] = get_resp_header(response, "content-type")

      assert get_resp_header(response, "content-disposition") ==
               [~s(attachment; filename="ExampleService.wsdl")]

      {root, _} = :xmerl_scan.string(String.to_charlist(response.resp_body))
      assert elem(root, 0) == :xmlElement
    end

    assert standard.resp_body =~ "Echo"
    assert enhanced.resp_body =~ ~s(name="ExampleServiceSOAP11Binding")
    assert enhanced.resp_body =~ ~s(name="ExampleServiceSOAP12Binding")
    assert enhanced.resp_body =~ ~s(name="ExampleServiceHTTPBinding")
    assert enhanced.resp_body =~ ~s(name="Note")
    assert enhanced.resp_body =~ ~s(minOccurs="0")
    assert enhanced.resp_body =~ ~s(soapAction="urn:example:Echo")
  end

  test "the enhanced WSDL protocol option controls advertised bindings and ports" do
    wsdl =
      EnhancedWSDLGenerator.generate(TestService.__soap_service__(), "https://example.test/",
        protocols: [:soap_1_2]
      )

    assert wsdl =~ ~s(name="ExampleServiceSOAP12Binding")
    assert wsdl =~ ~s(name="ExampleServiceSOAP12Port")
    refute wsdl =~ ~s(name="ExampleServiceSOAP11Binding")
    refute wsdl =~ ~s(name="ExampleServiceHTTPBinding")
    assert wsdl =~ "https://example.test/soap/v1.2/ExampleService"
  end

  test "SOAP 1.1 and 1.2 calls return the selected envelope and round-trip text" do
    for {path, namespace, content_type} <- [
          {"/soap", "http://schemas.xmlsoap.org/soap/envelope/", "text/xml; charset=utf-8"},
          {"/soap/v1.2", "http://www.w3.org/2003/05/soap-envelope",
           "application/soap+xml; charset=utf-8"}
        ] do
      body = """
      <soap:Envelope xmlns:soap="#{namespace}">
        <soap:Body><Echo><message>Fish &amp; Chips &lt;tag&gt;</message></Echo></soap:Body>
      </soap:Envelope>
      """

      response =
        conn(:post, path, body)
        |> put_req_header("content-type", content_type)
        |> EnhancedPlug.call(@config)

      assert response.status == 200
      assert get_resp_header(response, "content-type") == [content_type]
      assert response.resp_body =~ namespace
      assert response.resp_body =~ "Fish &amp; Chips &lt;tag&gt;"
      refute response.resp_body =~ "&amp;amp;"
    end
  end

  test "JSON calls return data and reject invalid JSON" do
    response =
      conn(:post, "/soap/api/Echo", Jason.encode!(%{message: "Fish & Chips"}))
      |> put_req_header("content-type", "application/json")
      |> EnhancedPlug.call(@config)

    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]

    assert Jason.decode!(response.resp_body) ==
             %{"success" => true, "data" => %{"echo" => "Fish & Chips"}}

    invalid =
      conn(:post, "/soap/api/Echo", "not JSON")
      |> put_req_header("content-type", "application/json")
      |> EnhancedPlug.call(@config)

    assert invalid.status == 400
    assert get_in(Jason.decode!(invalid.resp_body), ["error", "code"]) == "InvalidRequest"
  end

  test "missing JSON parameters return a client error without invoking the service" do
    response =
      conn(:post, "/soap/api/Echo", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> EnhancedPlug.call(@config)

    assert response.status == 400
    assert get_in(Jason.decode!(response.resp_body), ["error", "code"]) == "Client"

    assert get_in(Jason.decode!(response.resp_body), ["error", "message"]) =~
             "Missing required parameters: message"
  end

  test "JSON routes can be disabled" do
    config = EnhancedPlug.init(service: TestService, enable_json: false)

    response = request(:post, "/soap/api/Echo", Jason.encode!(%{message: "hello"}), config)
    wsdl = request(:get, "/soap?wsdl&enhanced=true", "", config)

    assert response.status == 405
    assert response.resp_body =~ "Method not allowed"
    assert wsdl.status == 200
    refute wsdl.resp_body =~ ~s(name="ExampleServiceHTTPBinding")
    refute wsdl.resp_body =~ ~s(name="ExampleServiceHTTPPort")
  end

  test "malformed SOAP 1.2 requests receive a SOAP 1.2 client fault" do
    response =
      conn(:post, "/soap/v1.2", "<not-xml")
      |> put_req_header("content-type", "application/soap+xml")
      |> EnhancedPlug.call(@config)

    assert response.status == 400
    assert get_resp_header(response, "content-type") == ["application/soap+xml; charset=utf-8"]
    assert response.resp_body =~ "http://www.w3.org/2003/05/soap-envelope"
    assert response.resp_body =~ "Invalid SOAP request"
  end

  test "the lowercase HTTP endpoint advertised by WSDL dispatches its operation" do
    wsdl = request(:get, "/soap?wsdl&enhanced=true")
    assert wsdl.resp_body =~ ~s(location="http://www.example.com/soap/api/exampleservice")
    assert wsdl.resp_body =~ ~s(location="/echo")

    response =
      conn(:post, "/soap/api/exampleservice/echo", Jason.encode!(%{message: "hello"}))
      |> put_req_header("content-type", "application/json")
      |> EnhancedPlug.call(@config)

    assert response.status == 200

    assert Jason.decode!(response.resp_body) ==
             %{"success" => true, "data" => %{"echo" => "hello"}}
  end

  test "unknown JSON operations return a JSON client error" do
    response =
      conn(:post, "/soap/api/Missing", Jason.encode!(%{message: "hello"}))
      |> put_req_header("content-type", "application/json")
      |> EnhancedPlug.call(@config)

    assert response.status == 400
    assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]
    assert get_in(Jason.decode!(response.resp_body), ["error", "code"]) == "Client"

    assert get_in(Jason.decode!(response.resp_body), ["error", "message"]) =~
             "Operation 'Missing' not found"
  end

  defp request(method, path, body \\ "", config \\ @config) do
    method
    |> conn(path, body)
    |> EnhancedPlug.call(config)
  end
end
