defmodule Lather.Xml.Builder do
  @moduledoc """
  XML builder for creating SOAP envelopes.

  Data structures (maps / keyword-style tuples with `@attr`, `#text`,
  and `#content` conventions) are converted to `XmlBuilder` AST tuples
  and rendered with `XmlBuilder.generate/1`. No manual string
  concatenation is used for element construction, and text / attribute
  escaping is handled by `XmlBuilder` at render time.

  ## Data shapes

    * `%{"tag" => "text"}` – element with text content
    * `%{"tag" => %{"@attr" => "v", "child" => "x"}}` – attributes are
      `@`-prefixed keys; every other key is a child element
    * `%{"tag" => %{"@attr" => "v", "#text" => "text"}}` – attributes plus
      text content
    * `%{"tag" => ["a", "b"]}` – a bare list is **repeated sibling
      elements**: `<tag>a</tag><tag>b</tag>`. Each item may itself be a
      map (with attributes / children). This mirrors `Lather.Xml.Parser`,
      which collects repeated elements into a list under one key, so a
      parsed document rebuilds losslessly.
    * `%{"tag" => %{"@attr" => "v", "item" => ["a", "b"]}}` – attributes
      together with repeated children:
      `<tag attr="v"><item>a</item><item>b</item></tag>`
    * `%{"tag" => %{"@attr" => "v", "#content" => [{"a", "1"}, {"b", "2"}]}}` –
      `#content` renders an **ordered** list of `{tag, value}` pairs (or
      single-key maps) as children, for when child order matters
    * `[{"tag", [{"@attr", "v"}, {"child", "x"}]}]` – a list of
      `{key, value}` pairs is the ordered (keyword-style) form of a map
      and is accepted anywhere a map is; an empty list renders an empty
      element

  ## Escaping contract

  `XmlBuilder`'s renderer is entity-aware: well-formed entities
  (`&amp;`, `&lt;`, …) in input pass through and resolve on parse,
  while bare `&`, `<`, `>`, quotes are escaped. Callers that must
  preserve literal entity-looking text (e.g. a value containing the
  characters `&amp;`) should pre-escape with `escape_text/1` — this is
  what `Lather.Soap.Body.serialize_params/1` does, keeping the
  historical raw-text-in / escaped-XML-out contract exact.
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
  @spec build(map() | [{String.t() | atom(), any()}]) :: {:ok, String.t()} | {:error, any()}
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

  def build(data) when is_list(data) do
    if Enum.all?(data, &match?({_, _}, &1)) do
      try do
        xml_content = build_xml_string(data)
        xml_with_declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <> xml_content
        {:ok, xml_with_declaration}
      rescue
        error ->
          {:error, error}
      end
    else
      {:error, :invalid_data_structure}
    end
  end

  def build(_data) do
    {:error, :invalid_data_structure}
  end

  @doc """
  Builds XML from a data structure without XML declaration.

  Useful for building fragments that will be embedded in larger documents.
  """
  @spec build_fragment(map() | [{String.t() | atom(), any()}]) ::
          {:ok, String.t()} | {:error, any()}
  def build_fragment(data) when is_map(data) do
    try do
      xml_content = build_xml_string(data)
      {:ok, xml_content}
    rescue
      error ->
        {:error, error}
    end
  end

  def build_fragment(data) when is_list(data) do
    if Enum.all?(data, &match?({_, _}, &1)) do
      try do
        xml_content = build_xml_string(data)
        {:ok, xml_content}
      rescue
        error ->
          {:error, error}
      end
    else
      {:error, :invalid_data_structure}
    end
  end

  def build_fragment(_data) do
    {:error, :invalid_data_structure}
  end

  @doc """
  Builds XML string from a map structure.
  """
  @spec build_xml_string(map() | [{String.t() | atom(), any()}]) :: String.t()
  def build_xml_string(data) do
    content = convert_to_xml_builder(data)
    XmlBuilder.generate(content)
  end

  # Converts a map / ordered pair list into a (flat) list of XmlBuilder
  # AST nodes.
  defp convert_to_xml_builder(data) when is_map(data) do
    data
    |> Enum.map(fn {key, value} -> convert_element(to_string(key), value) end)
    |> List.flatten()
  end

  defp convert_to_xml_builder(data) when is_list(data) do
    data
    |> Enum.map(&convert_to_xml_builder/1)
    |> List.flatten()
  end

  # A `{tag, value}` pair (ordered-list / `#content` item)
  defp convert_to_xml_builder({key, value}), do: convert_element(to_string(key), value)

  # Anything else (text, pre-built XmlBuilder AST tuples) passes through
  defp convert_to_xml_builder(data), do: data

  # `#text` inside a map that also has child elements is mixed content:
  # emit a text node, not a `<#text>` element.
  defp convert_element("#text", value), do: to_string(value)

  defp convert_element(tag, value) when is_map(value) do
    {attrs, content} = extract_attributes_and_content(value)

    final_content =
      cond do
        is_binary(content) -> content
        is_list(content) -> convert_to_xml_builder(content)
        is_map(content) -> convert_to_xml_builder(content)
        true -> nil
      end

    XmlBuilder.element(tag, attrs, final_content)
  end

  defp convert_element(tag, value) when is_list(value) do
    if ordered_pairs?(value) do
      build_ordered_element(tag, value)
    else
      # A bare list of values under a key means repeated sibling elements,
      # mirroring `Lather.Xml.Parser`, which collects repeated elements
      # into a list under a single key.
      Enum.map(value, &convert_element(tag, &1))
    end
  end

  defp convert_element(tag, value) do
    XmlBuilder.element(tag, to_string(value))
  end

  # Keyword-style ordered form: `[{"@attr", v}, {"child", v}, ...]`.
  # The empty list is treated as an empty element.
  defp ordered_pairs?(list), do: Enum.all?(list, &match?({_, _}, &1))

  defp build_ordered_element(tag, pairs) do
    {attr_pairs, child_pairs} =
      Enum.split_with(pairs, fn {k, _} -> String.starts_with?(to_string(k), "@") end)

    attr_map =
      Map.new(attr_pairs, fn {k, v} ->
        {String.trim_leading(to_string(k), "@"), v}
      end)

    XmlBuilder.element(tag, attr_map, convert_to_xml_builder(child_pairs))
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
            to_string(text_content)
          else
            # Mixed content: text plus child elements. Keep the map; the
            # `#text` entry is rendered as a text node by convert_element/2.
            content_map
          end

        map_size(content_map) == 0 ->
          nil

        true ->
          content_map
      end

    {attr_map, final_content}
  end

  @doc """
  Escapes XML special characters in text content.

  Note: `build/1` and `build_fragment/1` escape automatically via
  `XmlBuilder`, so this helper is only needed when embedding text into
  XML through other (manual) means.
  """
  @spec escape_text(String.t()) :: String.t()
  def escape_text(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  def escape_text(value), do: escape_text(to_string(value))
end
