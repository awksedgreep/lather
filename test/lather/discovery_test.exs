defmodule Lather.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Lather.Discovery

  test "probe envelope contains the Probe action" do
    xml = Discovery.probe_envelope("MyService")

    assert xml =~ "discovery/Probe"
    assert xml =~ "MyService"
  end

  test "matches document round-trips through the parser" do
    {:ok, xml} = Discovery.matches_document("MyService", "http://localhost:4000/soap")

    {:ok, parsed} = Lather.Xml.Parser.parse(xml)

    match = get_in(parsed, ["soap:Envelope", "soap:Body", "wsd:Matches", "wsd:Match"])
    assert match["@endpoint"] == "http://localhost:4000/soap"
  end
end
