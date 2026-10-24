defmodule Lather.Integration.SoapFaultStatusTest do
  @moduledoc """
  Regression tests for issue #37: SOAP faults are surfaced regardless of HTTP
  status, including SOAP 1.2 faults delivered with an HTTP 200 status.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Lather.DynamicClient
  alias Lather.TestUtils

  defmodule FaultRouter do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    # WSDL served for the client bootstrap (query ?wsdl).
    get "/soap" do
      if conn.query_params["wsdl"] do
        send_resp(conn, 200, wsdl())
      else
        send_resp(conn, 400, "bad request")
      end
    end

    # SOAP 1.1 fault with HTTP 400.
    post "/soap" do
      fault = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>Client</faultcode>
            <faultstring>Bad document in 400</faultstring>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      conn |> put_resp_content_type("text/xml") |> send_resp(400, fault)
    end

    # SOAP 1.2 fault delivered with HTTP 200.
    post "/soap200" do
      fault = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
        <soap:Body>
          <soap:Fault>
            <soap:Code><soap:Value>soap:Sender</soap:Value></soap:Code>
            <soap:Reason><soap:Text>Bad request in a 200</soap:Text></soap:Reason>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      conn |> put_resp_content_type("application/soap+xml") |> send_resp(200, fault)
    end

    defp wsdl do
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <wsdl:definitions xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
                        xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                        xmlns:tns="http://example.com/fault"
                        targetNamespace="http://example.com/fault">
        <wsdl:types>
          <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="http://example.com/fault">
            <xsd:element name="PingRequest"><xsd:complexType><xsd:sequence/></xsd:complexType></xsd:element>
            <xsd:element name="PingResponse"><xsd:complexType><xsd:sequence/></xsd:complexType></xsd:element>
          </xsd:schema>
        </wsdl:types>
        <wsdl:message name="PingRequest"><wsdl:part name="body" type="xsd:string"/></wsdl:message>
        <wsdl:message name="PingResponse"><wsdl:part name="result" type="xsd:string"/></wsdl:message>
        <wsdl:portType name="FaultPort">
          <wsdl:operation name="Ping">
            <wsdl:input message="tns:PingRequest"/><wsdl:output message="tns:PingResponse"/>
          </wsdl:operation>
        </wsdl:portType>
        <wsdl:binding name="FaultBinding" type="tns:FaultPort">
          <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document"/>
          <wsdl:operation name="Ping">
            <soap:operation soapAction="http://example.com/fault/Ping"/>
            <wsdl:input><soap:body use="literal"/></wsdl:input>
            <wsdl:output><soap:body use="literal"/></wsdl:output>
          </wsdl:operation>
        </wsdl:binding>
        <wsdl:service name="FaultService">
          <wsdl:port name="FaultPort" binding="tns:FaultBinding">
            <soap:address location="http://localhost/soap"/>
          </wsdl:port>
        </wsdl:service>
      </wsdl:definitions>
      """
    end
  end

  setup do
    {:ok, _pid, port} = TestUtils.start_server(FaultRouter, 0)
    %{port: port}
  end

  test "a SOAP fault with HTTP 400 is surfaced as a fault, not a bare http_error", %{port: port} do
    result =
      Lather.Http.Transport.post(
        "http://localhost:#{port}/soap",
        "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"><soap:Body><Ping/></soap:Body></soap:Envelope>",
        timeout: 5000
      )

    assert {:error, {:soap_fault, fault}} = result
    assert fault.fault_code == "Client"
    assert fault.fault_string == "Bad document in 400"
  end

  test "a SOAP 1.2 fault delivered with HTTP 200 is surfaced as a fault", %{port: port} do
    result =
      Lather.Http.Transport.post(
        "http://localhost:#{port}/soap200",
        "<soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\"><soap:Body><Ping/></soap:Body></soap:Envelope>",
        soap_version: :v1_2
      )

    assert {:error, {:soap_fault, fault}} = result
    assert fault.fault_code =~ "Sender"
    assert fault.fault_string == "Bad request in a 200"
  end
end
