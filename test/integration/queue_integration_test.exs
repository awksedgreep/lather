defmodule Lather.QueueIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule QueueService do
    @moduledoc false
    use Lather.Server

    @service_name "QueueService"
    @namespace "urn:queue:service"

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
    plug = {Lather.Server.EnhancedPlug, [service: QueueService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  test "queued invocations are drained in order", %{client: client} do
    name = :"QueueDrainTest-#{inspect(self())}"
    {:ok, pid} = Lather.Queue.start_link(name: name)

    Lather.Queue.enqueue(name, {"Echo", %{"message" => "one"}})
    Lather.Queue.enqueue(name, {"Echo", %{"message" => "two"}})

    results = Lather.Queue.drain(name, client)

    assert length(results) == 2
    assert {:ok, %{"echo" => "one"}} in results
    assert {:ok, %{"echo" => "two"}} in results
    assert Lather.Queue.size(name) == 0

    Process.unlink(pid)
    Process.exit(pid, :kill)
  end
end
