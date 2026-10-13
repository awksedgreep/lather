defmodule Lather.ClientTest do
  use ExUnit.Case
  doctest Lather.Client

  alias Lather.Client
  alias Lather.Soap.Envelope

  describe "client creation" do
    test "creates a new client with endpoint" do
      client = Client.new("https://example.com/soap")

      assert client.endpoint == "https://example.com/soap"
      assert client.options == []
    end

    test "creates a new client with options" do
      options = [timeout: 60_000, headers: [{"custom", "header"}]]
      client = Client.new("https://example.com/soap", options)

      assert client.endpoint == "https://example.com/soap"
      assert client.options == options
    end
  end

  describe "envelope building" do
    test "builds a basic SOAP envelope" do
      {:ok, envelope} = Envelope.build(:get_user, %{id: 123})

      assert String.contains?(envelope, "soap:Envelope")
      assert String.contains?(envelope, "soap:Body")
      assert String.contains?(envelope, "get_user")
      assert String.contains?(envelope, "123")
    end

    test "builds envelope with namespace" do
      {:ok, envelope} = Envelope.build(:get_user, %{id: 123}, namespace: "http://example.com")

      assert String.contains?(envelope, "xmlns=\"http://example.com\"")
    end

    test "builds envelope with headers" do
      headers = [{"custom_header", "value"}]
      {:ok, envelope} = Envelope.build(:get_user, %{id: 123}, headers: headers)

      assert String.contains?(envelope, "soap:Header")
      assert String.contains?(envelope, "custom_header")
    end
  end

  defmodule CapturePlug do
    @behaviour Plug
    import Plug.Conn

    def init(capture), do: capture

    def call(conn, capture) do
      {:ok, body, conn} = read_body(conn)
      Agent.update(capture, fn _ -> %{headers: conn.req_headers, body: body} end)

      send_resp(conn, 200, """
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body><EchoResponse><value>ok</value></EchoResponse></soap:Body>
      </soap:Envelope>
      """)
    end
  end

  describe "call/4 request options" do
    setup do
      {:ok, capture} = Agent.start_link(fn -> nil end)

      {:ok, server, port} =
        Lather.TestUtils.start_server({CapturePlug, capture}, 50_000 + :rand.uniform(5_000))

      on_exit(fn ->
        try do
          GenServer.stop(server, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end)

      Process.sleep(50)

      %{capture: capture, endpoint: "http://127.0.0.1:#{port}/soap"}
    end

    test "defaults to a SOAP 1.1 envelope and HTTP content type", context do
      client = Client.new(context.endpoint)
      assert {:ok, _} = Client.call(client, "Echo", %{"value" => "hello"})

      %{body: body, headers: headers} = Agent.get(context.capture, & &1)
      assert {"content-type", "text/xml; charset=utf-8"} in headers
      assert body =~ "http://schemas.xmlsoap.org/soap/envelope/"
    end

    test "call options override defaults for the envelope and transport", context do
      client =
        Client.new(context.endpoint,
          soap_version: :v1_1,
          namespace: "urn:default",
          headers: [{"x-token", "default"}]
        )

      assert {:ok, _} =
               Client.call(client, "Echo", %{"value" => "hello"},
                 soap_version: :v1_2,
                 namespace: "urn:fixture",
                 namespace_prefix: "fx",
                 headers: [{"x-token", "call"}],
                 soap_headers: [%{"Auth" => "secret"}]
               )

      %{body: body, headers: headers} = Agent.get(context.capture, & &1)
      assert {"content-type", "application/soap+xml; charset=utf-8"} in headers
      assert {"x-token", "call"} in headers
      refute {"x-token", "default"} in headers
      refute Enum.any?(headers, fn {name, _} -> name == "auth" end)

      assert {:ok, parsed} = Lather.Xml.Parser.parse(body)
      envelope = parsed["soap:Envelope"]
      assert envelope["@xmlns:soap"] == "http://www.w3.org/2003/05/soap-envelope"
      assert envelope["soap:Header"]["Auth"] == "secret"
      operation = envelope["soap:Body"]["fx:Echo"]
      assert operation["@xmlns:fx"] == "urn:fixture"
      assert operation["value"] == "hello"
    end

    test "client defaults apply and a call can override SOAP 1.2 back to 1.1", context do
      client = Client.new(context.endpoint, soap_version: :v1_2, namespace: "urn:default")

      assert {:ok, _} = Client.call(client, "Echo", %{"value" => "one"})
      %{body: body, headers: headers} = Agent.get(context.capture, & &1)
      assert {"content-type", "application/soap+xml; charset=utf-8"} in headers
      assert body =~ "http://www.w3.org/2003/05/soap-envelope"
      assert body =~ "urn:default"

      assert {:ok, _} = Client.call(client, "Echo", %{"value" => "two"}, soap_version: :v1_1)
      %{body: body, headers: headers} = Agent.get(context.capture, & &1)
      assert {"content-type", "text/xml; charset=utf-8"} in headers
      assert body =~ "http://schemas.xmlsoap.org/soap/envelope/"
      assert body =~ "urn:default"
    end
  end
end
