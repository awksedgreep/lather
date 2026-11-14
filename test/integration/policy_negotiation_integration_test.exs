defmodule Lather.PolicyNegotiationIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule PolicyService do
    @moduledoc false
    use Lather.Server

    @service_name "PolicyService"
    @namespace "urn:policy:service"

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
      [
        service: PolicyService,
        api_keys: ["secret-key"],
        policy: %{
          "require_auth" => ["api_key"],
          "operations" => ["Echo"]
        }
      ]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client, port: port}
  end

  test "negotiate fetches the published policy", %{client: client, port: port} do
    {:ok, policy} = Lather.Policy.negotiate("http://127.0.0.1:#{port}/soap")

    assert policy["require_auth"] == "api_key"
    assert policy["operations"] == "Echo"
    assert client != nil
  end

  test "negotiate rejects calls violating the policy", %{client: client} do
    {:error, violations} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"}, negotiate: true)

    assert violations == ["policy requires api_key authentication"]
  end

  test "negotiate allows compliant calls", %{client: client} do
    {:ok, response} =
      Lather.DynamicClient.call(
        client,
        "Echo",
        %{"message" => "hi"},
        negotiate: true,
        authentication: {:api_key, "secret-key"}
      )

    assert response["echo"] == "hi"
  end
end
