defmodule Lather.WSTrustIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule TrustService do
    @moduledoc false
    use Lather.Server

    @service_name "TrustService"
    @namespace "urn:trust:service"

    soap_operation "Ping" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("pong", :string)
      end
    end

    def ping(%{"message" => message}), do: {:ok, %{"pong" => message}}
  end

  defmodule MockIssuer do
    @moduledoc false
    use Plug.Router

    def secret, do: "issuer-secret"

    plug(:match)
    plug(:dispatch)

    post "/issue" do
      {:ok, raw, _} = Plug.Conn.read_body(conn)
      {:ok, body} = Jason.decode(raw)

      if body["username"] == "client" and body["password"] == "password" do
        token = Lather.Auth.WSTrust.issue_token(secret(), body["username"])

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> send_resp(200, Jason.encode!(%{"token" => token}))
      else
        conn |> send_resp(401, Jason.encode!(%{"error" => "unauthorized"}))
      end
    end
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: TrustService, wstrust_secret: "issuer-secret"]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  test "client with {:wstrust, secret} authenticates", %{client: client} do
    {:ok, response} =
      Lather.DynamicClient.call(client, "Ping", %{"message" => "hi"},
        authentication: {:wstrust, "issuer-secret"}
      )

    assert response["pong"] == "hi"
  end

  test "client with {:wstrust, secret, subject} authenticates", %{client: client} do
    {:ok, response} =
      Lather.DynamicClient.call(
        client,
        "Ping",
        %{"message" => "hi"},
        authentication: {:wstrust, "issuer-secret", "alice"}
      )

    assert response["pong"] == "hi"
  end

  test "requests without a token are rejected", %{client: client} do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Ping", %{"message" => "hi"})

    assert fault[:fault_string]["#text"] =~ "WS-Trust"
  end

  test "tampered tokens are rejected", %{client: client} do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(
        client,
        "Ping",
        %{"message" => "hi"},
        authentication: {:wstrust_token, "junk.signature"}
      )

    assert fault[:fault_string]["#text"] =~ "WS-Trust"
  end

  test "request_token obtains a usable token from an issuer" do
    {:ok, _issuer_pid, issuer_port} = TestUtils.start_server({MockIssuer, []}, 0)

    {:ok, token} =
      Lather.Auth.WSTrust.request_token(
        "http://127.0.0.1:#{issuer_port}/issue",
        "client",
        "password"
      )

    {:ok, claims} = Lather.Auth.WSTrust.validate_token(token, MockIssuer.secret())
    assert claims["sub"] == "client"
  end
end
