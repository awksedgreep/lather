defmodule Lather.DiscoveryIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule DiscoverableService do
    @moduledoc false
    use Lather.Server

    @service_name "DiscoverableService"
    @namespace "urn:discoverable:service"

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
      [service: DiscoverableService, enable_discovery: true]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, port: port}
  end

  test "probe discovers the service", %{port: port} do
    {:ok, matches} = Lather.Discovery.probe("http://127.0.0.1:#{port}/soap")

    assert length(matches) == 1
    match = List.first(matches)
    assert match[:types] == "DiscoverableService"
    assert match[:endpoint] =~ "/soap"
  end

  test "services without discovery enabled return 404" do
    plug = {Lather.Server.EnhancedPlug, [service: DiscoverableService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, response} =
      Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?discovery")

    assert response.status == 404
  end
end
