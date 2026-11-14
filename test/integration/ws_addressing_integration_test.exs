defmodule Lather.WSAddressingIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule AddressedService do
    @moduledoc false
    use Lather.Server

    @service_name "AddressedService"
    @namespace "urn:addressed:service"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  setup do
    plug = {
      Lather.Server.EnhancedPlug,
      [service: AddressedService, require_addressing: true]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client, port: port}
  end

  test "addressing option adds wsa headers and request succeeds", %{client: client} do
    {:ok, response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"}, addressing: true)

    assert response["echo"] == "hi"
  end

  test "requests without addressing are rejected", %{client: client} do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    text = fault[:fault_string]

    text =
      case text do
        %{"#text" => t} -> t
        other -> to_string(other)
      end

    assert text =~ "WS-Addressing"
  end

  test "custom addressing values are honored", %{client: client, port: port} do
    {:ok, response} =
      Lather.DynamicClient.call(
        client,
        "Echo",
        %{"message" => "hi"},
        addressing: %{
          to: "http://127.0.0.1:#{port}/soap",
          from: "http://test.client",
          action: "Echo",
          message_id: "test-123"
        }
      )

    assert response["echo"] == "hi"
  end
end
