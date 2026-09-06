defmodule Lather.Server.RequestParser do
  @moduledoc """
  Parses incoming SOAP requests and extracts operation details and parameters.
  """

  alias Lather.Soap.Elements
  alias Lather.Xml.Parser

  @doc """
  Parses a SOAP request XML and extracts the operation name and parameters.

  Returns:
  - `{:ok, %{operation: operation_name, params: params_map}}`
  - `{:error, {:parse_error, reason}}`
  """
  def parse(soap_xml) do
    with {:ok, parsed} <- Parser.parse(soap_xml),
         {:ok, envelope} <- extract_envelope(parsed),
         {:ok, body} <- extract_body(envelope),
         {:ok, operation_data} <- extract_operation(body) do
      {:ok, operation_data}
    else
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  # Extract SOAP envelope from parsed XML. Element names are matched by
  # local name so any prefix (soap:, soapenv:, SOAP-ENV:, s:, none) works.
  defp extract_envelope(parsed) do
    case Elements.get(parsed, "Envelope") do
      nil -> {:error, "No SOAP envelope found"}
      envelope -> {:ok, envelope}
    end
  end

  # Extract SOAP body from envelope
  defp extract_body(envelope) do
    case Elements.get(envelope, "Body") do
      nil -> {:error, "No SOAP body found"}
      body -> {:ok, body}
    end
  end

  # Extract operation name and parameters from body
  defp extract_operation(body) when is_map(body) do
    # Handle case where body might be empty or just contain whitespace/empty values
    if map_size(body) == 0 do
      {:error, "No operation found in SOAP body"}
    else
      # Filter out SOAP-specific keys to find the operation
      operation_keys =
        Map.keys(body)
        |> Enum.reject(fn key ->
          String.starts_with?(key, "@") or Elements.local_name(key) in ["Header", "Fault"]
        end)

      # Keep all operation keys - empty operations are valid

      case operation_keys do
        [] ->
          {:error, "No operation found in SOAP body"}

        [operation_name | _] ->
          # Remove namespace prefix if present
          clean_name = operation_name |> String.split(":") |> List.last()
          params = extract_parameters_from_map(body[operation_name])
          {:ok, %{operation: clean_name, params: params}}
      end
    end
  end

  # Handle empty or non-map body structures
  defp extract_operation(body) when is_binary(body) and body == "" do
    {:error, "No operation found in SOAP body"}
  end

  defp extract_operation(_), do: {:error, "Invalid SOAP body structure"}

  # Extract parameters from a map structure (operation content).
  #
  # Namespace prefixes are stripped from keys, attributes are dropped, and
  # the same cleaning is applied to nested maps and to every item of a
  # list, so a parameter has the same shape whether an element occurred
  # once or many times. An empty element is an empty string.
  defp extract_parameters_from_map(nil), do: %{}
  defp extract_parameters_from_map(content) when is_binary(content), do: %{}

  defp extract_parameters_from_map(content) when is_map(content) do
    content
    |> Enum.reject(fn {key, _} -> String.starts_with?(key, "@") end)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      cond do
        # `#text` next to child elements (mixed content) is kept as-is;
        # a lone `#text` (element with attributes only) becomes the value.
        key == "#text" and map_size(content) == 1 -> acc
        key == "#text" -> Map.put(acc, key, value)
        true -> Map.put(acc, Elements.local_name(key), clean_value(value))
      end
    end)
  end

  defp extract_parameters_from_map(_), do: %{}

  # An element carrying only attributes and text (`<a xsi:type="x">1</a>`)
  # collapses to its text; other maps are cleaned recursively.
  defp clean_value(%{"#text" => text} = map) when is_binary(text) do
    if Enum.all?(map, fn {k, _} -> k == "#text" or String.starts_with?(k, "@") end) do
      text
    else
      extract_parameters_from_map(map)
    end
  end

  defp clean_value(value) when is_map(value), do: extract_parameters_from_map(value)
  defp clean_value(value) when is_list(value), do: Enum.map(value, &clean_value/1)
  defp clean_value(value) when is_binary(value), do: value
  defp clean_value(value), do: to_string(value)
end
