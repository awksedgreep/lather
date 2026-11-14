defmodule Lather.SAMLIntegrationTest do
  use ExUnit.Case, async: true

  alias Lather.TestUtils

  defmodule SAMLService do
    @moduledoc false
    use Lather.Server

    @service_name "SAMLService"
    @namespace "urn:saml:service"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(%{}), do: {:ok, %{"pong" => "pong"}}
  end

  setup do
    plug =
      {Lather.Server.EnhancedPlug, [service: SAMLService, saml_secret: "saml-secret"]}

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  test "a request with a valid SAML assertion succeeds", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl",
        authentication: {:saml, "saml-secret", "alice", [attributes: %{"role" => "admin"}]}
      )

    {:ok, response} = Lather.DynamicClient.call(client, "Ping", %{})
    assert response["pong"] == "pong"
  end

  test "a request with the wrong SAML secret is rejected", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:saml, "wrong-secret"})

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Ping", %{})
    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "SAML verification failed"
  end

  test "a request without a SAML assertion is rejected", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl")

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Ping", %{})
    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "Missing SAML assertion"
  end
end
