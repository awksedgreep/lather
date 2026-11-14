defmodule Lather.Auth.OAuthTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.OAuth
  alias Lather.TestUtils

  defmodule TokenEndpoint do
    @moduledoc false
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    post "/token" do
      {:ok, body, _} = Plug.Conn.read_body(conn)
      params = URI.decode_query(body)

      cond do
        params["grant_type"] == "client_credentials" and params["client_id"] == "cid" and
            params["client_secret"] == "csecret" ->
          respond_json(conn, 200, %{"access_token" => "token-123", "token_type" => "Bearer"})

        params["grant_type"] == "refresh_token" and params["refresh_token"] == "r-1" ->
          respond_json(
            conn,
            200,
            %{"access_token" => "token-456", "refresh_token" => "r-2"}
          )

        true ->
          respond_json(conn, 401, %{"error" => "invalid_client"})
      end
    end

    defp respond_json(conn, status, payload) do
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(payload))
    end
  end

  defmodule TokenService do
    @moduledoc false
    use Lather.Server

    @service_name "TokenService"
    @namespace "urn:token:service"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(%{}), do: {:ok, %{"pong" => "ping"}}
  end

  setup do
    plug = {TokenEndpoint, []}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, _pid2, port2} =
      TestUtils.start_server({Lather.Server.EnhancedPlug, [service: TokenService]}, 0)

    {:ok,
     token_url: "http://127.0.0.1:#{port}/token", wsdl_url: "http://127.0.0.1:#{port2}/soap?wsdl"}
  end

  test "client credentials grant returns an access token", %{token_url: token_url} do
    assert {:ok, "token-123"} = OAuth.client_credentials_token("cid", "csecret", token_url)
  end

  test "bad credentials return an endpoint error", %{token_url: token_url} do
    assert {:error, {:token_endpoint_error, 401, _}} =
             OAuth.client_credentials_token("wrong", "nope", token_url)
  end

  test "bearer_headers formats the authorization header" do
    assert OAuth.bearer_headers("abc") == [{"authorization", "Bearer abc"}]
  end

  test "refresh grant returns a new token", %{token_url: token_url} do
    assert {:ok, %{"access_token" => "token-456", "refresh_token" => "r-2"}} =
             OAuth.refresh_token("cid", "csecret", "r-1", token_url)
  end

  test "client_with_token attaches the bearer header", %{token_url: token_url, wsdl_url: wsdl_url} do
    {:ok, client} = OAuth.client_with_token(wsdl_url, "cid", "csecret", token_url)
    assert {"authorization", "Bearer token-123"} in client.default_options[:headers]

    {:ok, response} = Lather.DynamicClient.call(client, "Ping", %{})
    assert response["pong"] == "ping"
  end
end
