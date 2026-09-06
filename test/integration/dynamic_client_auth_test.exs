defmodule Lather.Integration.DynamicClientAuthTest do
  @moduledoc """
  Verifies that DynamicClient's `:authentication` option actually reaches the
  wire (issue #19): Basic auth as an HTTP header, WS-Security as a SOAP header.
  """
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  @moduletag :integration

  defmodule EchoService do
    use Lather.Server

    @namespace "http://test.example.com/auth"
    @service_name "AuthEchoService"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end

      soap_action("Echo")
    end

    def echo(%{"message" => m}), do: {:ok, %{"echo" => m}}
  end

  # Serves the WSDL from EchoService; captures every POST and answers with
  # a canned response so the raw request can be inspected.
  defmodule CapturePlug do
    @behaviour Plug
    import Plug.Conn

    def init(opts), do: opts

    def call(%Plug.Conn{method: "POST"} = conn, capture) do
      {:ok, body, conn} = read_body(conn)
      Agent.update(capture, fn _ -> %{headers: conn.req_headers, body: body} end)

      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(200, """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body><EchoResponse><echo>ok</echo></EchoResponse></soap:Body>
      </soap:Envelope>
      """)
    end

    def call(conn, _capture) do
      Lather.Server.Plug.call(conn, Lather.Server.Plug.init(service: EchoService))
    end
  end

  setup do
    {:ok, capture} = Agent.start_link(fn -> nil end)

    {:ok, pid, port} =
      TestUtils.start_server({CapturePlug, capture}, 47_100 + :rand.uniform(1000))

    on_exit(fn ->
      try do
        GenServer.stop(pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    Process.sleep(50)
    {:ok, capture: capture, wsdl: "http://localhost:#{port}/soap?wsdl"}
  end

  test "{:basic, u, p} sends an Authorization header", %{capture: capture, wsdl: wsdl} do
    {:ok, client} = Lather.DynamicClient.new(wsdl, authentication: {:basic, "admin", "s3cret"})

    assert {:ok, %{"echo" => "ok"}} =
             Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    %{headers: headers} = Agent.get(capture, & &1)
    expected = "Basic " <> Base.encode64("admin:s3cret")
    assert {"authorization", expected} in headers
  end

  test "{:wssecurity, u, p} adds a UsernameToken SOAP header", %{capture: capture, wsdl: wsdl} do
    {:ok, client} =
      Lather.DynamicClient.new(wsdl, authentication: {:wssecurity, "admin", "s3cret"})

    assert {:ok, _} = Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    %{body: body} = Agent.get(capture, & &1)
    {:ok, parsed} = Lather.Xml.Parser.parse(body)

    token =
      get_in(parsed, ["soap:Envelope", "soap:Header", "wsse:Security", "wsse:UsernameToken"])

    assert token["wsse:Username"] == "admin"
    assert token["wsse:Password"]["#text"] == "s3cret"
    assert token["wsse:Password"]["@Type"] =~ "PasswordText"
  end

  test "{:wssecurity, u, p, password_type: :digest} sends a digest", %{
    capture: capture,
    wsdl: wsdl
  } do
    {:ok, client} =
      Lather.DynamicClient.new(wsdl,
        authentication: {:wssecurity, "admin", "s3cret", password_type: :digest}
      )

    assert {:ok, _} = Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    %{body: body} = Agent.get(capture, & &1)
    {:ok, parsed} = Lather.Xml.Parser.parse(body)

    token =
      get_in(parsed, ["soap:Envelope", "soap:Header", "wsse:Security", "wsse:UsernameToken"])

    assert token["wsse:Password"]["@Type"] =~ "PasswordDigest"
    assert is_binary(token["wsse:Nonce"]["#text"])
    refute token["wsse:Password"]["#text"] == "s3cret"
  end

  test "WS-Security header is merged with caller-supplied SOAP headers", %{
    capture: capture,
    wsdl: wsdl
  } do
    {:ok, client} =
      Lather.DynamicClient.new(wsdl, authentication: {:wssecurity, "admin", "s3cret"})

    assert {:ok, _} =
             Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"},
               headers: [%{"SessionId" => "abc"}]
             )

    %{body: body} = Agent.get(capture, & &1)
    {:ok, parsed} = Lather.Xml.Parser.parse(body)
    header = get_in(parsed, ["soap:Envelope", "soap:Header"])
    assert header["SessionId"] == "abc"
    assert is_map(header["wsse:Security"])
  end
end
