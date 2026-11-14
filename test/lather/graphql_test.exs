defmodule Lather.GraphQLTest do
  use ExUnit.Case, async: true

  alias Lather.GraphQL

  test "parse_query extracts fields, args and selection" do
    fields = GraphQL.parse_query("Echo(message: \"hi\", count: 2) { echo count }")

    assert length(fields) == 1
    field = hd(fields)

    assert field[:field] == "Echo"
    assert field[:args] == %{"message" => "hi", "count" => 2}
    assert field[:selection] == ["echo", "count"]
  end

  test "parse_query handles fields without args" do
    [field] = GraphQL.parse_query("Ping")

    assert field[:field] == "Ping"
    assert field[:args] == %{}
    assert field[:selection] == nil
  end

  defmodule SchemaService do
    @moduledoc false
    use Lather.Server

    @service_name "SchemaService"
    @namespace "urn:graphql:schema"

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

  test "schema renders GraphQL SDL" do
    sdl = GraphQL.schema(SchemaService)

    assert sdl =~ "type Query"
    assert sdl =~ "Echo(message: String): SOAPResponse"
  end
end
