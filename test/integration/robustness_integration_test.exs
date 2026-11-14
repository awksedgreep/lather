defmodule Lather.RobustnessIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule TenantServiceA do
    @moduledoc false
    use Lather.Server

    @service_name "TenantServiceA"
    @namespace "urn:tenant:a"

    soap_operation "EchoA" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo_a(%{"message" => message}), do: {:ok, %{"echo" => "A: #{message}"}}
  end

  defmodule TenantServiceB do
    @moduledoc false
    use Lather.Server

    @service_name "TenantServiceB"
    @namespace "urn:tenant:b"

    soap_operation "EchoB" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo_b(%{"message" => message}), do: {:ok, %{"echo" => "B: #{message}"}}
  end

  defp fault_text(fault) do
    text = fault[:fault_string]

    case text do
      %{"#text" => t} -> t
      other -> to_string(other)
    end
  end

  test "tenants route to different services" do
    plug = {
      Lather.Server.EnhancedPlug,
      [
        service: TenantServiceA,
        tenants: %{
          "beta" => TenantServiceB,
          "default" => TenantServiceA
        }
      ]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client_b} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl&tenant=beta")
    {:ok, response_b} = Lather.DynamicClient.call(client_b, "EchoB", %{"message" => "hi"})
    assert response_b["echo"] == "B: hi"

    {:ok, client_a} =
      Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl&tenant=default")

    {:ok, response_a} = Lather.DynamicClient.call(client_a, "EchoA", %{"message" => "hi"})
    assert response_a["echo"] == "A: hi"
  end

  test "unknown operation errors suggest a close match" do
    plug = {Lather.Server.EnhancedPlug, [service: TenantServiceA]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/ws/2003/05/soap-envelope">
      <soap:Body><EchoAa><message>x</message></EchoAa></soap:Body>
    </soap:Envelope>
    """

    {:error, {:soap_fault, fault}} =
      Lather.Http.Transport.post(
        "http://127.0.0.1:#{port}/soap",
        body,
        soap_version: :v1_2
      )

    assert fault_text(fault) =~ "Did you mean 'EchoA'"
  end

  test "fault injection is survivable with reliable messaging" do
    plug = {
      Lather.Server.EnhancedPlug,
      [service: TenantServiceA, fault_injection_rate: 0.4]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, response} =
      Lather.DynamicClient.call(
        client,
        "EchoA",
        %{"message" => "hi"},
        reliable: true,
        retries: 8
      )

    assert response["echo"] == "A: hi"
  end

  test "debug mode logs requests without breaking them" do
    plug = {Lather.Server.EnhancedPlug, [service: TenantServiceA, debug: true]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, response} = Lather.DynamicClient.call(client, "EchoA", %{"message" => "hi"})
    assert response["echo"] == "A: hi"
  end

  test "unicode survives the round trip" do
    plug = {Lather.Server.EnhancedPlug, [service: TenantServiceA]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, response} = Lather.DynamicClient.call(client, "EchoA", %{"message" => "café 😀"})

    assert response["echo"] == "A: café 😀"
  end
end
