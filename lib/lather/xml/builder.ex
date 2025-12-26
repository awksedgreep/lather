defmodule Lather.Xml.Builder do
  @moduledoc """
  XML builder for creating SOAP envelopes.

  Provides functionality to build XML documents from Elixir data structures,
  specifically optimized for SOAP envelope construction.
  """

  @doc """
  Builds XML from the given data structure.

  ## Parameters

  * `data` - Elixir data structure (map) to convert to XML

  ## Examples

      iex> {:ok, xml} = Lather.Xml.Builder.build(%{"soap:Envelope" => %{"soap:Body" => %{"operation" => %{}}}})
      iex> String.contains?(xml, "<soap:Envelope>")
      true
      iex> String.contains?(xml, "<operation/>")
      true

  """
  @spec build(map()) :: {:ok, String.t()} | {:error, any()}
  def build(data) when is_map(data) do
    try do
      xml_content = build_xml_string(data)
      xml_with_declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <> xml_content
      {:ok, xml_with_declaration}
    rescue
      error ->
        {:error, error}
    end
  end

  def build(_data) do
    {:error, :invalid_data_structure}
  end

  @doc """
  Builds XML from a data structure without XML declaration.

  Useful for building fragments that will be embedded in larger documents.
  """
  @spec build_fragment(map()) :: {:ok, String.t()} | {:error, any()}
  def build_fragment(data) when is_map(data) do
    try do
      xml_content = build_xml_string(data)
      {:ok, xml_content}
    rescue
      error ->
        {:error, error}
    end
  end

  def build_fragment(_data) do
    {:error, :invalid_data_structure}
  end

  @doc """
  Builds XML string from a map structure.
  """
  @spec build_xml_string(map()) :: String.t()
  def build_xml_string(data) when is_map(data) do
    data
    |> Enum.map(fn {key, value} ->
      build_element(to_string(key), value)
    end)
    |> Enum.join("\n")
  end

  @spec build_element(String.t(), any()) :: String.t()
  defp build_element(tag, value) when is_map(value) do
    {attributes, content} = extract_attributes_and_content(value)
    attr_string = build_attributes(attributes)

    case content do
      nil ->
        "<#{tag}#{attr_string}/>"

      "" ->
        "<#{tag}#{attr_string}></#{tag}>"

      content when is_binary(content) ->
        escaped_content = escape_text(content)
        "<#{tag}#{attr_string}>#{escaped_content}</#{tag}>"

      content when is_map(content) ->
        inner_xml = build_xml_string(content)
        "<#{tag}#{attr_string}>\n#{indent(inner_xml)}\n</#{tag}>"

      content when is_list(content) ->
        inner_xml =
          Enum.map(content, fn item ->
            case item do
              {child_tag, child_value} ->
                build_element(to_string(child_tag), child_value)

              item when is_map(item) ->
                # Handle maps in lists by building them as nested elements
                Enum.map(item, fn {k, v} ->
                  build_element(to_string(k), v)
                end)
                |> Enum.join("\n")

              _ ->
                escape_text(to_string(item))
            end
          end)
          |> Enum.join("\n")

        "<#{tag}#{attr_string}>\n#{indent(inner_xml)}\n</#{tag}>"
    end
  end

  defp build_element(tag, value) when is_list(value) do
    inner_content =
      Enum.map(value, fn item ->
        case item do
          {child_tag, child_value} ->
            build_element(to_string(child_tag), child_value)

          item when is_map(item) ->
            # Handle maps in lists by building them as nested elements
            Enum.map(item, fn {k, v} ->
              build_element(to_string(k), v)
            end)
            |> Enum.join("\n")

          _ ->
            escape_text(to_string(item))
        end
      end)
      |> Enum.join("\n")

    "<#{tag}>\n#{indent(inner_content)}\n</#{tag}>"
  end

  defp build_element(tag, value) do
    escaped_value = escape_text(to_string(value))
    "<#{tag}>#{escaped_value}</#{tag}>"
  end

  @spec extract_attributes_and_content(map()) :: {map(), any()}
  defp extract_attributes_and_content(value) when is_map(value) do
    {attributes, content} =
      Enum.split_with(value, fn {key, _} ->
        String.starts_with?(to_string(key), "@")
      end)

    attr_map =
      Enum.into(attributes, %{}, fn {key, val} ->
        clean_key = key |> to_string() |> String.trim_leading("@")
        {clean_key, val}
      end)

    content_map = Enum.into(content, %{})

    # Handle special #text and #content keys
    final_content =
      cond do
        # Handle #content - list of child elements to include directly
        Map.has_key?(content_map, "#content") ->
          Map.get(content_map, "#content")

        # Handle #text - text content
        Map.has_key?(content_map, "#text") ->
          text_content = Map.get(content_map, "#text")
          if map_size(content_map) == 1 do
            # Only #text, no other children
            text_content
          else
            # Has both #text and other children, keep the map
            content_map
          end

        map_size(content_map) == 0 ->
          nil

        true ->
          content_map
      end

    {attr_map, final_content}
  end

  @spec build_attributes(map()) :: String.t()
  defp build_attributes(attributes) when map_size(attributes) == 0, do: ""

  defp build_attributes(attributes) do
    attrs =
      Enum.map(attributes, fn {key, value} ->
        escaped_value = escape_attribute(to_string(value))
        "#{key}=\"#{escaped_value}\""
      end)
      |> Enum.join(" ")

    " " <> attrs
  end

  @spec indent(String.t()) :: String.t()
  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map(&("  " <> &1))
    |> Enum.join("\n")
  end

  @doc """
  Escapes XML special characters in text content.
  """
  @spec escape_text(String.t()) :: String.t()
  def escape_text(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  def escape_text(value), do: escape_text(to_string(value))

  @spec escape_attribute(String.t()) :: String.t()
  defp escape_attribute(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
