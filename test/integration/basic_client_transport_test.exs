defmodule Lather.BasicClientTransportTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule BasicService do
    @moduledoc false
    use Lather.Server

    @service_name "BasicService"
    @namespace "urn:httpc"

    soap_operation "Ping" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def ping(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  test "basic client fetches WSDL" do
    plug = {Lather.Server.EnhancedPlug, [service: BasicService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, response} =
      Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?wsdl", client: :basic)

    assert response.status == 200
    assert response.body =~ "definitions"
  end

  test "basic client posts a SOAP envelope" do
    plug = {Lather.Server.EnhancedPlug, [service: BasicService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    envelope = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Body><Ping><message>basic</message></Ping></soap:Body>
    </soap:Envelope>
    """

    {:ok, response} =
      Lather.Http.Transport.post(
        "http://127.0.0.1:#{port}/soap",
        envelope,
        soap_version: :v1_2,
        client: :basic
      )

    assert response.status == 200
    assert response.body =~ "basic"
  end

  test "basic client is used when set globally" do
    plug = {Lather.Server.EnhancedPlug, [service: BasicService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    Application.put_env(:lather, :http_client, :basic)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")
    {:ok, result} = Lather.DynamicClient.call(client, "Ping", %{"message" => "global"})

    assert result["echo"] == "global"

    Application.put_env(:lather, :http_client, :finch)
  end
end
