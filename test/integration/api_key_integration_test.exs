defmodule Lather.APIKeyIntegrationTest do
  use ExUnit.Case, async: true

  alias Lather.TestUtils

  defmodule KeyService do
    @moduledoc false
    use Lather.Server

    @service_name "KeyService"
    @namespace "urn:key:service"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(%{}), do: {:ok, %{"pong" => "pong"}}
  end

  setup do
    plug =
      {Lather.Server.EnhancedPlug, [service: KeyService, api_keys: ["valid-key"]]}

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  test "a request with a valid API key succeeds", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:api_key, "valid-key"})

    {:ok, response} = Lather.DynamicClient.call(client, "Ping", %{})
    assert response["pong"] == "pong"
  end

  test "a request without an API key is rejected", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl")

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Ping", %{})
    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "Invalid API key"
  end

  test "a request with the wrong API key is rejected", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:api_key, "wrong-key"})

    {:error, _} = Lather.DynamicClient.call(client, "Ping", %{})
  end
end
