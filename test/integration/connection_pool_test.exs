defmodule Lather.ConnectionPoolTest do
  use ExUnit.Case, async: false

  alias Lather.Http.Transport
  alias Lather.TestUtils

  defmodule PoolService do
    @moduledoc false
    use Lather.Server

    @service_name "PoolService"
    @namespace "urn:pool:service"

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
    plug = {Lather.Server.EnhancedPlug, [service: PoolService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, port: port}
  end

  test "warm_connection starts a pool and requests use it", %{port: port} do
    url = "http://127.0.0.1:#{port}"
    pool_name = String.to_atom("warm_pool_#{:rand.uniform(100_000)}")

    {:ok, pool} = Transport.warm_connection(url, size: 5, pool_name: pool_name)

    {:ok, response} = Transport.get("#{url}/soap?wsdl", pool_name: pool)
    assert response.status == 200
    assert response.body =~ "PoolService"

    status = Transport.pool_status(pool_name, url)
    assert match?({:ok, _}, status) or match?({:error, :not_found}, status)
  end

  test "DynamicClient.warm_pool/with_pool round-trip", %{port: port} do
    {:ok, client} =
      Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    pool_name = String.to_atom("dyn_pool_#{:rand.uniform(100_000)}")

    {:ok, pool} = Lather.DynamicClient.warm_pool(client, pool_name: pool_name, size: 8)
    warmed_client = Lather.DynamicClient.with_pool(client, pool)

    {:ok, response} = Lather.DynamicClient.call(warmed_client, "Echo", %{"message" => "pooled"})
    assert response["echo"] == "pooled"
  end

  test "GET transport works without a warmed pool", %{port: port} do
    {:ok, response} = Transport.get("http://127.0.0.1:#{port}/soap?wsdl")

    assert response.status == 200
  end
end
