defmodule Lather.Server.WSDLGeneratorTest do
  use ExUnit.Case, async: true

  alias Lather.Server.WSDLGenerator

  defmodule VersionedService do
    use Lather.Server

    @service_name "VersionedService"
    @api_version "3.2.1"

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

  defmodule UnversionedService do
    use Lather.Server

    @service_name "UnversionedService"

    def ping(_params), do: {:ok, %{"pong" => "pong"}}
  end

  test "declares the service version in a documentation element" do
    wsdl =
      WSDLGenerator.generate(
        VersionedService.__soap_service__(),
        "http://localhost:4000/soap"
      )

    assert wsdl =~ ~s(<documentation>Version: 3.2.1</documentation>)
  end

  test "omits the documentation element when no version is declared" do
    wsdl =
      WSDLGenerator.generate(
        UnversionedService.__soap_service__(),
        "http://localhost:4000/soap"
      )

    refute wsdl =~ "documentation"
  end

  test "cached_generate returns the same WSDL as generate" do
    direct =
      WSDLGenerator.generate(VersionedService.__soap_service__(), "http://localhost:4000/soap")

    cached = WSDLGenerator.cached_generate(VersionedService, "http://localhost:4000/soap")
    assert cached == direct
    assert WSDLGenerator.cached_generate(VersionedService, "http://localhost:4000/soap") == cached
  end

  test "cached_generate regenerates when the ttl expires" do
    first = WSDLGenerator.cached_generate(UnversionedService, "http://localhost:4000/a", 0)
    second = WSDLGenerator.cached_generate(UnversionedService, "http://localhost:4000/a", 0)
    assert first == second
  end

  test "escapes special characters in the version" do
    service_info = %{
      name: "EscService",
      namespace: "urn:esc",
      target_namespace: "urn:esc",
      version: "1.0 <beta>",
      operations: [],
      types: []
    }

    wsdl = WSDLGenerator.generate(service_info, "http://localhost:4000/soap")
    assert wsdl =~ "Version: 1.0 &lt;beta&gt;"
  end
end
