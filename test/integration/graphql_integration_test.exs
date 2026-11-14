defmodule Lather.GraphQLIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule GraphService do
    @moduledoc false
    use Lather.Server

    @service_name "GraphService"
    @namespace "urn:graphql:service"

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
    plug = {Lather.Server.EnhancedPlug, [service: GraphService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  test "execute a GraphQL-style query", %{client: client} do
    {:ok, results} = Lather.GraphQL.execute(client, "Echo(message: \"hello\") { echo }")

    assert results["Echo"] == %{"echo" => "hello"}
  end

  test "unknown operation reports an error", %{client: client} do
    {:error, {"Nope", _reason}} = Lather.GraphQL.execute(client, "Nope()")
  end
end
