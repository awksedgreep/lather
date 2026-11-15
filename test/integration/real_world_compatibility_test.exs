defmodule Lather.RealWorldCompatibilityTest do
  use ExUnit.Case, async: true

  alias Lather.Wsdl.Analyzer

  test "parses a realistic SOAP 1.1 weather WSDL" do
    wsdl = File.read!("test/fixtures/weather_wsdl.xml")
    {:ok, analysis} = Analyzer.analyze(wsdl)

    assert analysis.service_name == "WeatherService"

    operations = for op <- analysis.operations, do: op.name
    assert "GetWeather" in operations

    endpoint = for e <- analysis.endpoints, do: e.address.location

    assert endpoint == ["https://weather.example.com/soap"]
  end

  test "operation inputs reference typed elements" do
    wsdl = File.read!("test/fixtures/weather_wsdl.xml")
    {:ok, analysis} = Analyzer.analyze(wsdl)

    matching = for op <- analysis.operations, op.name == "GetWeather", do: op
    op = hd(matching)

    assert op.input

    parts = op.input[:parts] || op.input["parts"]
    typed = for p <- parts, p.type == "tns:GetWeatherRequest", do: p
    assert typed != []
  end

  test "RPC-style WSDL exposes primitive parts and per-operation style" do
    wsdl = File.read!("test/fixtures/stockquote_rpc_wsdl.xml")
    {:ok, analysis} = Analyzer.analyze(wsdl)

    assert analysis.service_name == "StockQuoteService"

    [op] = for op <- analysis.operations, op.name == "GetQuote", do: op

    assert op.style == "rpc"
    assert op.soap_action == "urn:GetQuote"
    assert op.documentation == "Returns the current quote for a ticker symbol."

    parts = op.input[:parts] || op.input["parts"]
    [part] = parts
    assert part.name == "symbol"
    assert part.type == "xsd:string"
  end

  test "nested-type WSDL with multiple ports and faults is parsed" do
    wsdl = File.read!("test/fixtures/orders_wsdl.xml")
    {:ok, analysis} = Analyzer.analyze(wsdl)

    names = for op <- analysis.operations, do: op.name
    assert Enum.sort(names) == ["CancelOrder", "PlaceOrder"]

    locations = for e <- analysis.endpoints, do: e.address.location

    assert "https://orders.example.com/soap" in locations
    assert "http://orders.internal.example.com/soap" in locations

    [place] = for op <- analysis.operations, op.name == "PlaceOrder", do: op
    faults = place.faults
    assert length(faults) == 1
    assert hd(faults).message == "tns:OrderFault"
  end

  test "SOAP 1.2 binding WSDL with arrays and attributes is parsed" do
    wsdl = File.read!("test/fixtures/inventory_wsdl.xml")
    {:ok, analysis} = Analyzer.analyze(wsdl)

    assert analysis.service_name == "InventoryService"

    [op] = for op <- analysis.operations, op.name == "CheckStock", do: op

    assert op.soap_action == "urn:CheckStock"
    assert op.style == "document"

    locations = for e <- analysis.endpoints, do: e.address.location
    assert locations == ["https://inventory.example.com/soap12"]
  end

  test "generate_report summarizes every fixture" do
    for path <- [
          "test/fixtures/weather_wsdl.xml",
          "test/fixtures/stockquote_rpc_wsdl.xml",
          "test/fixtures/orders_wsdl.xml",
          "test/fixtures/inventory_wsdl.xml"
        ] do
      {:ok, analysis} = Analyzer.analyze(File.read!(path))
      report = Analyzer.generate_report(analysis)

      assert report =~ "## Service: #{analysis.service_name}"
      assert report =~ "## Operations"
    end
  end

  test "faulty WSDL returns a structured error" do
    {:error, reason} = Analyzer.analyze("<not-a-wSDL>")
    assert reason
  end
end
