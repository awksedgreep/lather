defmodule Lather.ReliableMessagingIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule RmService do
    @moduledoc false
    use Lather.Server

    @service_name "RmService"
    @namespace "urn:rm:service"

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
    plug = {Lather.Server.EnhancedPlug, [service: RmService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  test "reliable option delivers with WS-RM headers", %{client: client} do
    {:ok, response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"}, reliable: true)

    assert response["echo"] == "hi"
  end
end
