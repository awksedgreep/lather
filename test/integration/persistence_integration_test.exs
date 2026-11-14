defmodule Lather.PersistenceIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule PersistService do
    @moduledoc false
    use Lather.Server

    @service_name "PersistService"
    @namespace "urn:persist:service"

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

  test "config_file options are merged into the plug" do
    config_path = "/tmp/lather_config_#{inspect(self())}.json"
    File.write(config_path, Jason.encode!(%{"enable_swagger" => true}))

    plug = {
      Lather.Server.EnhancedPlug,
      [service: PersistService, config_file: config_path]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, response} = Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?swagger")
    assert response.status == 200
  end

  test "persist_store records call history" do
    plug = {Lather.Server.EnhancedPlug, [service: PersistService]}
    {:ok, _plug_pid, port} = TestUtils.start_server(plug, 0)

    store_name = :"PersistStore-#{inspect(self())}"
    {:ok, store_pid} = Lather.Persistence.start_link(name: store_name)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, _response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"}, persist_store: store_name)

    history = Lather.Persistence.history(store_name)
    assert length(history) == 1
    record = hd(history)
    assert record[:operation] == "Echo"

    Process.unlink(store_pid)
    Process.exit(store_pid, :kill)
  end
end
