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

  test "faulty WSDL returns a structured error" do
    {:error, reason} = Analyzer.analyze("<not-a-wSDL>")
    assert reason
  end
end
