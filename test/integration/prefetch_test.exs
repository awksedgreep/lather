defmodule Lather.PrefetchTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule PrefetchService do
    @moduledoc false
    use Lather.Server

    @service_name "PrefetchService"
    @namespace "urn:prefetch:service"

    soap_operation "GetUser" do
      input do
        parameter("id", :string, required: true)
      end

      output do
        parameter("name", :string)
      end
    end

    soap_operation "GetPermissions" do
      input do
        parameter("id", :string, required: true)
      end

      output do
        parameter("permissions", :string)
      end
    end

    def get_user(%{"id" => id}), do: {:ok, %{"name" => "user-#{id}"}}

    def get_permissions(%{"id" => id}), do: {:ok, %{"permissions" => "read write"}}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: PrefetchService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, pool} =
      Lather.Prefetch.start_link(name: String.to_atom("prefetch_#{:rand.uniform(100_000)}"))

    {:ok, client: client, pool: pool}
  end

  test "prefetches related operations and serves them from cache", %{client: client, pool: pool} do
    {:ok, response} =
      Lather.DynamicClient.call(client, "GetUser", %{"id" => "1"},
        prefetch: [{"GetPermissions", %{"id" => "1"}}],
        prefetch_pool: pool
      )

    assert response["name"] == "user-1"

    # Give the async prefetch task a moment to finish.
    Process.sleep(150)

    {:ok, cached} =
      Lather.DynamicClient.call(client, "GetPermissions", %{"id" => "1"}, prefetch_pool: pool)

    assert cached["permissions"] == "read write"
    assert cached["prefetched"] == true
  end

  test "prefetch pool records size", %{client: client, pool: pool} do
    Lather.Prefetch.put(pool, "Echo", %{"message" => "x"}, %{"echo" => "x"})

    assert Lather.Prefetch.size(pool) == 1
    assert Lather.Prefetch.fetch(pool, "Echo", %{"message" => "x"}) == {:ok, %{"echo" => "x"}}
    assert Lather.Prefetch.fetch(pool, "Echo", %{"message" => "y"}) == :miss

    Lather.Prefetch.clear(pool)
    assert Lather.Prefetch.size(pool) == 0
  end
end
