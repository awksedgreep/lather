defmodule Lather.EventingIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule EventService do
    @moduledoc false
    use Lather.Server

    @service_name "EventService"
    @namespace "urn:eventing:service"

    soap_operation "Ping" do
      output do
        parameter("pong", :string)
      end
    end

    def ping(_params), do: {:ok, %{"pong" => "pong"}}
  end

  setup do
    plug = {
      Lather.Server.EnhancedPlug,
      [service: EventService, enable_eventing: true]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, port: port}
  end

  test "subscribe, publish and poll events over HTTP", %{port: port} do
    {:ok, response} =
      Lather.Http.Transport.post("http://127.0.0.1:#{port}/soap?subscribe=orders", "")

    assert response.status == 200

    {:ok, parsed} = Lather.Xml.Parser.parse(response.body)

    sub =
      get_in(parsed, ["soap:Envelope", "soap:Body", "wse:SubscribeResponse", "wse:SubscriptionId"])

    assert is_binary(sub)

    {:ok, pub} =
      Lather.Http.Transport.post("http://127.0.0.1:#{port}/soap?publish=orders", "event-payload")

    assert pub.status == 200

    {:ok, events} = Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?events&sub=#{sub}")
    assert events.status == 200
    assert events.body =~ "event-payload"
  end

  test "eventing disabled returns 404" do
    plug = {Lather.Server.EnhancedPlug, [service: EventService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, response} = Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?events")
    assert response.status == 404
  end
end
