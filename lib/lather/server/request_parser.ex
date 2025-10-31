defmodule Lather.Server.RequestParser do
  @moduledoc """
  Parses incoming SOAP requests and extracts operation details and parameters.
  """

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

  # Extract SOAP envelope from parsed XML
  defp extract_envelope(parsed) when is_map(parsed) do
    cond do
      Map.has_key?(parsed, "soap:Envelope") -> {:ok, parsed["soap:Envelope"]}
      Map.has_key?(parsed, "Envelope") -> {:ok, parsed["Envelope"]}
      true -> {:error, "No SOAP envelope found"}
    end
  end

  defp extract_envelope(_), do: {:error, "No SOAP envelope found"}

  # Extract SOAP body from envelope
  defp extract_body(envelope) when is_map(envelope) do
    cond do
      Map.has_key?(envelope, "soap:Body") -> {:ok, envelope["soap:Body"]}
      Map.has_key?(envelope, "Body") -> {:ok, envelope["Body"]}
      true -> {:error, "No SOAP body found"}
    end
  end

  defp extract_body(_), do: {:error, "No SOAP body found"}

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
          key in ["soap:Header", "Header", "soap:Fault", "Fault"]
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

  defp extract_operation(nil), do: {:error, "No operation found in SOAP body"}

  defp extract_operation(_), do: {:error, "Invalid SOAP body structure"}

  # Extract parameters from a map structure (operation content)
  defp extract_parameters_from_map(nil), do: %{}
  defp extract_parameters_from_map(""), do: %{}
  defp extract_parameters_from_map(content) when is_binary(content), do: %{}

  defp extract_parameters_from_map(content) when is_map(content) do
    content
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      # Remove namespace prefix from parameter names
      clean_key = key |> String.split(":") |> List.last()

      cond do
        # Skip attributes (keys starting with @)
        String.starts_with?(key, "@") ->
          acc

        # Skip #text if it's the only content
        key == "#text" and map_size(content) == 1 ->
          acc

        # Handle nested maps (complex parameters)
        is_map(value) and key != "#text" ->
          Map.put(acc, clean_key, extract_parameters_from_map(value))

        # Handle #text content with attributes
        key == "#text" ->
          Map.put(acc, clean_key, value)

        # Handle simple string values
        is_binary(value) ->
          if value == "" do
            Map.put(acc, clean_key, %{})
          else
            Map.put(acc, clean_key, value)
          end

        # Handle lists (array-like structures)
        is_list(value) ->
          Map.put(acc, clean_key, value)

        # Handle other types by converting to string (but not lists)
        true ->
          Map.put(acc, clean_key, to_string(value))
      end
    end)
  end

  defp extract_parameters_from_map(_), do: %{}
end
