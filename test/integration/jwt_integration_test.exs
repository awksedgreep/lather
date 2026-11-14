defmodule Lather.JWTIntegrationTest do
  use ExUnit.Case, async: true

  alias Lather.TestUtils

  defmodule JWTService do
    @moduledoc false
    use Lather.Server

    @service_name "JWTService"
    @namespace "urn:jwt:service"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(%{}), do: {:ok, %{"pong" => "authenticated"}}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: JWTService, jwt_secret: "jwt-secret"]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  test "a request with a valid JWT succeeds", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl",
        authentication: {:jwt, "jwt-secret", %{"sub" => "tester"}}
      )

    {:ok, response} = Lather.DynamicClient.call(client, "Ping", %{})
    assert response["pong"] == "authenticated"
  end

  test "a request with the wrong secret is rejected", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:jwt, "wrong-secret"})

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Ping", %{})
    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "JWT verification failed"
  end

  test "a request without a JWT is rejected", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl")

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Ping", %{})
    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "Missing JWT"
  end
end
