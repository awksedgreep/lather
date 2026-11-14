defmodule Lather.ObservabilityIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule ObservabilityService do
    @moduledoc false
    use Lather.Server

    @service_name "ObservabilityService"
    @namespace "urn:observability:service"

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

  setup do
    store = :"ObsStore-#{inspect(self())}"
    {:ok, store_pid} = Lather.Persistence.start_link(name: store)

    plug = {
      Lather.Server.EnhancedPlug,
      [service: ObservabilityService, enable_metrics: true, persistence_store: store]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client, port: port, store_pid: store_pid}
  end

  test "dashboard renders service stats", %{client: client, port: port} do
    {:ok, _response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    {:ok, response} = Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?dashboard")

    assert response.status == 200
    assert response.body =~ "Service Dashboard: ObservabilityService"
    assert response.body =~ "ObservabilityService"
  end

  test "docs browser renders operation docs", %{port: port} do
    {:ok, response} = Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?docs")

    assert response.status == 200
    assert response.body =~ "Echo"
    assert response.body =~ "message: string (required)"
  end

  test "history endpoint returns persisted requests", %{client: client, port: port} do
    {:ok, _} =
      Lather.DynamicClient.call(
        client,
        "Echo",
        %{"message" => "hi"},
        persist_store: :"ObsStore-#{inspect(self())}"
      )

    {:ok, response} = Lather.Http.Transport.get("http://127.0.0.1:#{port}/soap?history")

    assert response.status == 200
    assert response.body =~ "Echo"
  end
end
