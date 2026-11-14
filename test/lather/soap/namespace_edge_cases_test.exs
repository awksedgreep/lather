defmodule Lather.Soap.NamespaceEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Lather.Soap.Elements

  defmodule Parsed do
    def parse(xml) do
      {:ok, parsed} = Lather.Xml.Parser.parse(xml)
      parsed
    end
  end

  test "legacy SOAP-ENV prefix is resolved by local name" do
    xml = ~s(<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <SOAP-ENV:Body><Echo><message>hi</message></Echo></SOAP-ENV:Body>
    </SOAP-ENV:Envelope>)

    parsed = Parsed.parse(xml)

    envelope = Elements.get(parsed, "Envelope")
    body = Elements.get(envelope, "Body")
    echo = Elements.get(body, "Echo")

    assert echo == %{"message" => "hi"}

    assert Elements.namespace_of("SOAP-ENV:Envelope", envelope) ==
             "http://schemas.xmlsoap.org/soap/envelope/"
  end

  test "custom namespace prefixes on body elements" do
    xml =
      ~s(<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:ns1="urn:custom">
      <soap:Body><ns1:Echo><ns1:message>hi</ns1:message></ns1:Echo></soap:Body>
    </soap:Envelope>)

    parsed = Parsed.parse(xml)
    body = Elements.get(parsed, "Envelope") |> Elements.get("Body")
    echo = Elements.get(body, "Echo")

    assert %{"ns1:message" => "hi"} = echo
    {key, _} = Elements.find(body, "Echo")
    assert key == "ns1:Echo"
    envelope = Elements.get(parsed, "Envelope")
    assert Elements.namespace_of("ns1:Echo", envelope) == "urn:custom"
  end

  test "elements without prefixes work" do
    xml = ~s(<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
      <Body><Echo><message>hi</message></Echo></Body>
    </Envelope>)

    parsed = Parsed.parse(xml)
    body = Elements.get(parsed, "Envelope") |> Elements.get("Body")

    assert Elements.get(body, "Echo") == %{"message" => "hi"}

    assert Elements.namespace_of("Envelope", parsed["Envelope"]) ==
             "http://www.w3.org/2003/05/soap-envelope"
  end

  test "mixed prefixes for envelope and body are tolerated" do
    xml = ~s(<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <Echo><message>hi</message></Echo>
      </soap:Body>
    </soapenv:Envelope>)

    parsed = Parsed.parse(xml)
    body = Elements.get(parsed, "Envelope") |> Elements.get("Body")

    assert Elements.get(body, "Echo") == %{"message" => "hi"}
  end

  test "fast parser handles namespace prefixes" do
    xml = ~s(<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Body><ns:Echo xmlns:ns="urn:ns"><ns:message>hi</ns:message></ns:Echo></soap:Body>
    </soap:Envelope>)

    {:ok, parsed} = Lather.Xml.FastParser.parse(xml)
    body = Elements.get(parsed, "Envelope") |> Elements.get("Body")

    assert Elements.get(body, "Echo")
  end
end
