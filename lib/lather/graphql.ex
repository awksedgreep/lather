defmodule Lather.GraphQL do
  @moduledoc """
  A lightweight GraphQL-style bridge for Lather SOAP services.

  SOAP operations are exposed as GraphQL fields on a synthetic `Query`
  type. Queries of the form:

      Echo(message: "hello") { echo }

  are executed against a `Lather.DynamicClient` and the resulting SOAP
  body is projected onto the requested selection set.

  ## Examples

      iex> fields = Lather.GraphQL.parse_query("Echo(message: \"hi\") { echo }")
      iex> hd(fields)[:args]
      %{message: "hi"}

  """

  alias Lather.DynamicClient

  @doc """
  Parse a (subset of) GraphQL query text into field invocations.

  Supports top-level fields with optional parenthesised arguments and an
  optional single-level selection set.
  """
  @spec parse_query(String.t()) :: [map()]
  def parse_query(query) when is_binary(query) do
    query = String.trim(query)

    fields =
      query
      |> String.split(~r/\n(?=\w)/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Enum.map(fields, &parse_field/1)
  end

  @doc """
  Execute a GraphQL-style query against a DynamicClient.

  Each top-level field maps to a SOAP operation. Returns
  `{:ok, %{field_name => result}}` or `{:error, reason}`.
  """
  @spec execute(DynamicClient.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def execute(%DynamicClient{} = client, query) do
    fields = parse_query(query)

    results =
      Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, acc} ->
        case DynamicClient.call(client, field[:field], field[:args]) do
          {:ok, body} ->
            {:cont, {:ok, Map.put(acc, field[:field], project(body, field[:selection]))}}

          {:error, reason} ->
            {:halt, {:error, {field[:field], reason}}}
        end
      end)

    results
  end

  @doc """
  Generate a GraphQL SDL schema for a service module.
  """
  @spec schema(module()) :: String.t()
  def schema(service_module) do
    service_info = service_module.__soap_service__()

    query_fields =
      Enum.map(service_info.operations, fn op ->
        args =
          Enum.map(op.input, fn param ->
            "#{param.name}: #{graphql_type(param.type)}"
          end)
          |> Enum.join(", ")

        "  #{op.name}(#{args}): SOAPResponse"
      end)
      |> Enum.join("\n")

    """
    type Query {
    #{query_fields}
    }

    type SOAPResponse {
      body: String
    }
    """
  end

  defp parse_field(field) do
    [name, rest] =
      case Regex.run(~r/^(\w+)(.*)$/, field) do
        [_, name, rest] -> [name, rest]
        _ -> [field, ""]
      end

    {args, selection} = parse_args_and_selection(rest)

    %{field: name, args: args, selection: selection}
  end

  defp parse_args_and_selection(rest) do
    args =
      case Regex.run(~r/\((.*?)\)/, rest) do
        [_, raw] -> parse_args(raw)
        _ -> %{}
      end

    selection =
      case Regex.run(~r/\{([^}]*)\}/, rest) do
        [_, raw] ->
          raw
          |> String.split(~r/[,\n]+/)
          |> Enum.flat_map(&String.split(&1, " "))
          |> Enum.reject(&(&1 == ""))

        _ ->
          nil
      end

    {args, selection}
  end

  defp parse_args(""), do: %{}

  defp parse_args(raw) do
    raw
    |> String.split(",")
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), parse_value(String.trim(value)))
        _ -> acc
      end
    end)
  end

  defp parse_value(value) do
    cond do
      String.starts_with?(value, "\"") ->
        String.trim(value, "\"")

      value == "true" ->
        true

      value == "false" ->
        false

      match?({_, ""}, Integer.parse(value)) ->
        elem(Integer.parse(value), 0)

      match?({_, _}, Float.parse(value)) ->
        elem(Float.parse(value), 0)

      true ->
        value
    end
  end

  defp project(body, nil), do: body

  defp project(body, selection) do
    Map.take(body, selection)
  end

  defp graphql_type(type) do
    case type do
      t when t in [:string, :text] -> "String"
      t when t in [:integer, :int, :long] -> "Int"
      t when t in [:float, :double, :decimal] -> "Float"
      t when t in [:boolean, :bool] -> "Boolean"
      _ -> "String"
    end
  end
end
