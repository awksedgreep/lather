defmodule Lather.Server.ServiceSupervisorTest do
  use ExUnit.Case, async: true

  alias Lather.Server.ServiceSupervisor

  defmodule SupervisedService do
    @moduledoc false
    use Lather.Server

    @service_name "SupervisedService"
    @namespace "urn:supervised:service"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}

    soap_operation "Boom" do
      output do
        parameter("error", :string)
      end
    end

    def boom(%{}), do: {:error, :boom}
  end

  test "in-process calls work", %{} do
    {:ok, pid} = ServiceSupervisor.start_link(SupervisedService)

    assert {:ok, response} = ServiceSupervisor.call(pid, "Echo", %{"message" => "hi"})
    assert response["echo"] == "hi"

    stats = ServiceSupervisor.stats(pid)
    assert stats.requests == 1
    assert stats.errors == 0
    assert stats.service == SupervisedService
    assert stats.http_running == false
  end

  test "errors are counted", %{} do
    {:ok, pid} = ServiceSupervisor.start_link(SupervisedService)

    {:ok, _} = ServiceSupervisor.call(pid, "Echo", %{"message" => "ok"})
    {:ok, _} = ServiceSupervisor.call(pid, "Boom", %{})

    stats = ServiceSupervisor.stats(pid)
    assert stats.requests == 2
    assert stats.errors == 1
  end

  test "http server lifecycle", %{} do
    {:ok, pid} = ServiceSupervisor.start_link(SupervisedService)

    {:ok, port} = ServiceSupervisor.start_http_server(pid, 0)
    assert is_integer(port) and port > 0

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")
    {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "live"})
    assert response["echo"] == "live"

    stats = ServiceSupervisor.stats(pid)
    assert stats.http_running == true
    assert stats.http_port == port

    :ok = ServiceSupervisor.stop_http_server(pid)
    stats = ServiceSupervisor.stats(pid)
    assert stats.http_running == false
  end

  test "starting twice returns the same port", %{} do
    {:ok, pid} = ServiceSupervisor.start_link(SupervisedService)
    {:ok, port1} = ServiceSupervisor.start_http_server(pid, 0)
    {:ok, port2} = ServiceSupervisor.start_http_server(pid, 0)

    assert port1 == port2
  end
end
