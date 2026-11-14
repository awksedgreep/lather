defmodule Lather.StreamOperationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule StreamService do
    @moduledoc false
    use Lather.Server

    @service_name "StreamService"
    @namespace "urn:stream:service"

    soap_operation "StreamItems" do
      input do
        parameter("count", :integer, required: true)
      end

      output do
        parameter("item", :string)
      end
    end

    def stream_items(%{"count" => count}) do
      n =
        case count do
          value when is_integer(value) -> value
          value -> String.to_integer(to_string(value))
        end

      items =
        Enum.map(1..n, fn i ->
          %{"item" => "item-#{i}"}
        end)

      {:stream, items}
    end
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: StreamService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  test "stream_operation yields each chunk as it arrives", %{client: client} do
    stream = Lather.DynamicClient.stream_operation(client, "StreamItems", %{"count" => 5})

    results = Enum.take(stream, 5)

    assert length(results) == 5

    Enum.with_index(results)
    |> Enum.each(fn {result, index} ->
      case result do
        {:ok, body} ->
          assert body["StreamItemsResponse"]["item"] == "item-#{index + 1}"

        other ->
          flunk("unexpected stream result: #{inspect(other)}")
      end
    end)
  end

  test "stream is lazy: only requested chunks are consumed", %{client: client} do
    stream = Lather.DynamicClient.stream_operation(client, "StreamItems", %{"count" => 1000})

    [first] = Enum.take(stream, 1)
    {:ok, body} = first
    assert body["StreamItemsResponse"]["item"] == "item-1"
  end
end
