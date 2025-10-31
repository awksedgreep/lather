defmodule Lather.Xml.Parser do
  @moduledoc """
  XML parser for processing SOAP responses.

  Provides functionality to parse XML documents into Elixir data structures,
  specifically optimized for SOAP response parsing.
  """

  import SweetXml

  @doc """
  Parses XML string into an Elixir data structure.

  ## Parameters

  * `xml_string` - XML content as a string

  ## Returns

  * `{:ok, parsed_data}` - Successfully parsed XML as a map
  * `{:error, reason}` - Parsing error

  ## Examples

      iex> xml = "<?xml version=\\"1.0\\"?><root><item>value</item></root>"
      iex> Parser.parse(xml)
      {:ok, %{"root" => %{"item" => "value"}}}

  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, any()}
  def parse(xml_string) when is_binary(xml_string) do
    try do
      # Clean the XML string to handle common issues
      cleaned_xml =
        xml_string
        |> String.trim()
        |> remove_bom()

      # Parse with SweetXml and build the structure
      doc = SweetXml.parse(cleaned_xml, namespace_conformant: true)

      parsed = parse_node(doc)

      {:ok, parsed}
    rescue
      error ->
        {:error, {:parse_error, error}}
    catch
      :exit, reason ->
        {:error, {:parse_error, reason}}
    end
  end

  def parse(_), do: {:error, :invalid_input}

  # Remove Byte Order Mark (BOM) if present
  defp remove_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp remove_bom(xml_string), do: xml_string

  @doc """
  Extracts text content from an XML element.
  """
  @spec extract_text(any()) :: String.t() | nil
  def extract_text(element) when is_binary(element) do
    # If it's already a string, just return it
    element
  end

  def extract_text(element) do
    case xpath(element, ~x"./text()"s) do
      "" -> nil
      text -> text
    end
  end

  @doc """
  Extracts all attributes from an XML element.
  """
  @spec extract_attributes(any()) :: map()
  def extract_attributes(element) do
    xpath(element, ~x"./@*"l)
    |> Enum.reduce(%{}, fn attr, acc ->
      name = xpath(attr, ~x"name(.)"s)
      value = xpath(attr, ~x"."s)
      Map.put(acc, "@#{name}", value)
    end)
  end

  # Private functions

  defp parse_node(node) do
    case elem(node, 0) do
      :xmlElement ->
        parse_xml_element(node)

      :xmlText ->
        parse_xml_text(node)

      _ ->
        %{}
    end
  end

  defp parse_xml_element(
         {:xmlElement, name, _expanded, _namespace, _nsinfo, _parents, _pos, attributes, content,
          _language, _xmlbase, _elementdef}
       ) do
    # Get the element name (preserving namespace prefix if present)
    element_name = to_string(name)

    # Parse attributes
    attrs = parse_attributes(attributes)

    # Parse content (children and text)
    {children_map, text_content} = parse_content(content)

    # Build the element value
    element_value = build_element_value(attrs, children_map, text_content)

    %{element_name => element_value}
  end

  defp parse_xml_text({:xmlText, _parents, _pos, _language, value, _type}) do
    text = to_string(value) |> String.trim()
    if text == "", do: nil, else: text
  end

  defp parse_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn attr, acc ->
      case attr do
        {:xmlAttribute, name, _expanded, _nsinfo, _namespace, _parents, _pos, _language, value,
         _normalized} ->
          Map.put(acc, "@#{name}", to_string(value))

        _ ->
          acc
      end
    end)
  end

  defp parse_content(content) do
    {children, texts} =
      Enum.reduce(content, {%{}, []}, fn node, {child_acc, text_acc} ->
        case elem(node, 0) do
          :xmlElement ->
            child_map = parse_xml_element(node)
            {merge_children(child_acc, child_map), text_acc}

          :xmlText ->
            text = parse_xml_text(node)
            if text, do: {child_acc, [text | text_acc]}, else: {child_acc, text_acc}

          _ ->
            {child_acc, text_acc}
        end
      end)

    text_content =
      case Enum.reverse(texts) do
        [] -> nil
        [single] -> single
        multiple -> Enum.join(multiple, " ")
      end

    {children, text_content}
  end

  defp merge_children(acc, new_child) do
    Enum.reduce(new_child, acc, fn {key, value}, acc ->
      case Map.get(acc, key) do
        nil ->
          Map.put(acc, key, value)

        existing when is_list(existing) ->
          Map.put(acc, key, existing ++ [value])

        existing ->
          Map.put(acc, key, [existing, value])
      end
    end)
  end

  defp build_element_value(attrs, children, text) do
    cond do
      map_size(attrs) == 0 and map_size(children) == 0 and is_nil(text) ->
        ""

      map_size(attrs) == 0 and map_size(children) == 0 ->
        text

      map_size(children) == 0 and is_nil(text) ->
        attrs

      map_size(children) == 0 ->
        Map.put(attrs, "#text", text)

      is_nil(text) ->
        Map.merge(attrs, children)

      true ->
        attrs
        |> Map.merge(children)
        |> Map.put("#text", text)
    end
  end
end
