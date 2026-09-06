defmodule Lather.Soap.ElementsTest do
  use ExUnit.Case, async: true
  doctest Lather.Soap.Elements

  alias Lather.Soap.Elements

  test "local_name/1 and prefix/1" do
    assert Elements.local_name("SOAP-ENV:Envelope") == "Envelope"
    assert Elements.local_name("Envelope") == "Envelope"
    assert Elements.prefix("SOAP-ENV:Envelope") == "SOAP-ENV"
    assert Elements.prefix("Envelope") == nil
  end

  test "find/2 matches by local name and prefers an exact key" do
    assert Elements.find(%{"s:Body" => 1}, "Body") == {"s:Body", 1}
    assert Elements.find(%{"s:Body" => 1, "Body" => 2}, "Body") == {"Body", 2}
    assert Elements.find(%{"@Body" => 1}, "Body") == nil
    assert Elements.find("not a map", "Body") == nil
  end

  test "get_in/2 walks prefixed paths and tolerates non-map values" do
    doc = %{
      "soapenv:Envelope" => %{"soapenv:Body" => %{"soapenv:Fault" => %{"faultcode" => "x"}}}
    }

    assert Elements.get_in(doc, ["Envelope", "Body", "Fault", "faultcode"]) == "x"
    assert Elements.get_in(%{"Envelope" => %{"Body" => ""}}, ["Envelope", "Body", "Fault"]) == nil
  end

  test "soap_version/1 reads the namespace bound to the Envelope prefix" do
    assert Elements.soap_version(%{
             "env:Envelope" => %{"@xmlns:env" => Elements.soap_1_2_namespace()}
           }) == :v1_2

    assert Elements.soap_version(%{"Envelope" => %{"@xmlns" => Elements.soap_1_2_namespace()}}) ==
             :v1_2

    assert Elements.soap_version(%{
             "soap:Envelope" => %{"@xmlns:soap" => Elements.soap_1_1_namespace()}
           }) == :v1_1

    assert Elements.soap_version(%{
             "Envelope" => %{"Body" => %{"Fault" => %{"Code" => %{"Value" => "x"}}}}
           }) == :v1_2

    assert Elements.soap_version(%{"Envelope" => %{}}) == :v1_1
  end
end
