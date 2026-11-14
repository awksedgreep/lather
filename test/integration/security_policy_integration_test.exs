defmodule Lather.SecurityPolicyIntegrationTest do
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

  test "security policy at init raises when config violates it" do
    assert_raise ArgumentError, fn ->
      Lather.Server.EnhancedPlug.init(
        service: PolicyService,
        security_policy: %{require_auth: [:api_key], min_factors: 2}
      )
    end
  end

  test "security policy at init passes when config satisfies it" do
    plug = {
      Lather.Server.EnhancedPlug,
      [
        service: PolicyService,
        api_keys: ["policy-key"],
        security_policy: %{require_auth: [:api_key], min_factors: 1}
      ]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"},
        authentication: {:api_key, "policy-key"}
      )

    assert response["echo"] == "hi"

    {:error, _} = Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})
  end
end
