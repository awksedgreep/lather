defmodule Lather.AsyncClientTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule AsyncService do
    @moduledoc false
    use Lather.Server

    @service_name "AsyncService"
    @namespace "urn:async:service"

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
    plug = {Lather.Server.EnhancedPlug, [service: AsyncService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  test "call_async returns an awaitable task", %{client: client} do
    task = Lather.DynamicClient.call_async(client, "Echo", %{"message" => "async"})
    {:ok, response} = Lather.DynamicClient.await(task)

    assert response["echo"] == "async"
  end

  test "call_many runs invocations concurrently and preserves order", %{client: client} do
    invocations = Enum.map(1..20, &{"Echo", %{"message" => "msg-#{&1}"}})

    results = Lather.DynamicClient.call_many(client, invocations, concurrency: 5)

    assert length(results) == 20

    Enum.with_index(results)
    |> Enum.each(fn {result, index} ->
      assert {:ok, %{"echo" => "msg-#{index + 1}"}} == result
    end)
  end

  test "call_many reports failures per invocation", %{client: client} do
    results =
      Lather.DynamicClient.call_many(client, [
        {"Echo", %{"message" => "ok"}},
        {"NoSuchOperation", %{}},
        {"Echo", %{"message" => "ok2"}}
      ])

    assert [
             {:ok, _},
             {:error, _},
             {:ok, _}
           ] = results
  end

  test "call_stream is lazy", %{client: client} do
    invocations = Stream.cycle([{"Echo", %{"message" => "lazy"}}])

    first_three =
      client
      |> Lather.DynamicClient.call_stream(invocations)
      |> Enum.take(3)

    assert length(first_three) == 3

    Enum.each(first_three, fn result ->
      assert {:ok, %{"echo" => "lazy"}} == result
    end)
  end
end
