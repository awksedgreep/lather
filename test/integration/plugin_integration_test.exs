defmodule Lather.PluginIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule PluginService do
    @moduledoc false
    use Lather.Server

    @service_name "PluginService"
    @namespace "urn:plugin:service"

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

  defmodule MarkerPlugin do
    @moduledoc false
    @impl Lather.Plugin
    def before_request(_operation, options), do: {:ok, options}

    @impl Lather.Plugin
    def after_response(_operation, {:ok, body}), do: {:ok, Map.put(body, "plugin", "marker")}

    def after_response(_operation, error), do: error

    @impl Lather.Plugin
    def on_error(_operation, _error), do: {:ok, :logged}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: PluginService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} =
      Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl", plugins: [MarkerPlugin])

    {:ok, client: client}
  end

  test "plugins run around dynamic client calls", %{client: client} do
    {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    assert response["echo"] == "hi"
    assert response["plugin"] == "marker"
  end

  test "failing before_request blocks the call" do
    plug = {Lather.Server.EnhancedPlug, [service: PluginService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} =
      Lather.DynamicClient.new(
        "http://127.0.0.1:#{port}/soap?wsdl",
        plugins: [Lather.PluginTest.FailingPlugin]
      )

    assert {:error, :plugin_failure} =
             Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})
  end
end
