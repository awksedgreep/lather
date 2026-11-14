defmodule Lather.MultiFactorAuthTest do
  use ExUnit.Case, async: true

  alias Lather.TestUtils

  defmodule MFAService do
    @moduledoc false
    use Lather.Server

    @service_name "MFAService"
    @namespace "urn:mfa:service"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(%{}), do: {:ok, %{"pong" => "pong"}}
  end

  @plug_opts [
    service: MFAService,
    api_keys: ["mfa-key"],
    jwt_secret: "mfa-jwt",
    require_auth: [:api_key, :jwt]
  ]

  setup do
    {:ok, _pid, port} = TestUtils.start_server({Lather.Server.EnhancedPlug, @plug_opts}, 0)

    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  def soap_body(jwt) do
    """
    <?xml version="1.0"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/wsdl/">
      <soap:Header>
        <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
          <jwt:JWT xmlns:jwt="urn:ietf:params:oauth:jwt">#{jwt}</jwt:JWT>
        </wsse:Security>
      </soap:Header>
      <soap:Body><Ping xmlns="urn:mfa:service"/></soap:Body>
    </soap:Envelope>
    """
  end

  test "both factors present succeeds", %{base_url: base_url} do
    jwt = Lather.Auth.JWT.token(%{"sub" => "mfa-user"}, "mfa-jwt")

    conn =
      Plug.Test.conn(:post, "#{base_url}/soap", soap_body(jwt))
      |> Plug.Conn.put_req_header("content-type", "text/xml")
      |> Plug.Conn.put_req_header("x-api-key", "mfa-key")

    response = Lather.Server.EnhancedPlug.call(conn, Lather.Server.EnhancedPlug.init(@plug_opts))
    assert response.status == 200
  end

  test "missing the API key is rejected", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:jwt, "mfa-jwt"})

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Ping", %{})
    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "API key"
  end

  test "missing the JWT is rejected", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:api_key, "mfa-key"})

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Ping", %{})
    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "JWT"
  end
end
