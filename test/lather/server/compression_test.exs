defmodule Lather.Server.CompressionTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn, only: [get_resp_header: 2]

  alias Lather.Server.EnhancedPlug

  defmodule CompressService do
    use Lather.Server

    @service_name "CompressService"

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

  @config EnhancedPlug.init(service: CompressService)

  defp request(method, path, body, headers) do
    conn(method, path, body)
    |> apply_headers(headers)
    |> EnhancedPlug.call(@config)
  end

  defp apply_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {name, value}, acc ->
      Plug.Conn.put_req_header(acc, name, value)
    end)
  end

  test "large responses are gzipped when the client accepts gzip" do
    response = request(:get, "/soap", "", [{"accept-encoding", "gzip, deflate"}])

    assert response.status == 200
    assert get_resp_header(response, "content-encoding") == ["gzip"]

    decompressed = :zlib.gunzip(response.resp_body)
    assert decompressed =~ "CompressService - Service Overview"
  end

  test "small responses are not compressed" do
    response = request(:get, "/soap?health", "", [{"accept-encoding", "gzip"}])

    assert response.status == 200
    assert get_resp_header(response, "content-encoding") == []
    assert response.resp_body =~ "\"status\":\"ok\""
  end

  test "responses stay uncompressed when gzip is not accepted" do
    response = request(:get, "/soap", "", [{"accept-encoding", "br, deflate"}])

    assert response.status == 200
    assert get_resp_header(response, "content-encoding") == []
    assert response.resp_body =~ "Service Overview"
  end

  test "gzipped SOAP request bodies are decompressed" do
    soap = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <Echo xmlns="urn:example"><message>compressed hello</message></Echo>
      </soap:Body>
    </soap:Envelope>
    """

    response =
      request(:post, "/soap", :zlib.gzip(soap), [
        {"content-encoding", "gzip"},
        {"content-type", "text/xml"}
      ])

    assert response.status == 200
    assert response.resp_body =~ "compressed hello"
  end

  test "gzipped JSON request bodies are decompressed" do
    json = Jason.encode!(%{"message" => "json via gzip"})

    response =
      request(:post, "/soap/api/Echo", :zlib.gzip(json), [
        {"content-encoding", "gzip"},
        {"content-type", "application/json"}
      ])

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["data"]["echo"] == "json via gzip"
  end

  test "malformed gzip bodies produce a client error" do
    response = request(:post, "/soap", "not gzip data", [{"content-encoding", "gzip"}])
    assert response.status == 400
  end
end
