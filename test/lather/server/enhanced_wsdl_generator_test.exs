defmodule Lather.Server.EnhancedWSDLGeneratorTest do
  @moduledoc """
  Endpoint URLs advertised by the enhanced WSDL generator keep exactly one
  separator between the base URL and the service path (issue #39).
  """
  use ExUnit.Case, async: true

  alias Lather.Server.EnhancedWSDLGenerator

  defmodule UrlService do
    @moduledoc false
    use Lather.Server

    @service_name "UrlService"
    @namespace "urn:urls"

    soap_operation "Ping" do
      input do
        parameter("seq", :int, required: true)
      end

      output do
        parameter("pong", :string)
      end
    end

    def ping(%{"seq" => seq}), do: {:ok, %{"pong" => "pong #{seq}"}}
  end

  defp locations(wsdl) do
    Regex.scan(~r'location="([^"]+)"', wsdl)
    |> Enum.map(fn [_whole, url] ->
      url
    end)
  end

  test "endpoint URLs are well formed with or without a trailing slash" do
    for base_url <- ["http://localhost:4000/soap", "http://localhost:4000/soap/"] do
      urls = locations(EnhancedWSDLGenerator.generate(UrlService.__soap_service__(), base_url))

      assert "http://localhost:4000/soap/soap/v1.1/UrlService" in urls
      assert "http://localhost:4000/soap/soap/v1.2/UrlService" in urls
      assert "http://localhost:4000/soap/api/urlservice" in urls

      for url <- urls do
        refute String.contains?(url, "soapsoap"), "missing separator in #{url}"
        refute String.contains?(url, "soap//"), "duplicated separator in #{url}"
      end
    end
  end

  test "the HTTP port advertises the service name under the base path" do
    wsdl =
      EnhancedWSDLGenerator.generate(UrlService.__soap_service__(), "http://localhost:4000/soap")

    assert "http://localhost:4000/soap/api/urlservice" in locations(wsdl)
  end
end
