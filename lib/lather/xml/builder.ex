defmodule Lather.Xml.Builder do
  @moduledoc """
  XML builder for creating SOAP envelopes.

  Data structures (maps / keyword-style tuples with `@attr`, `#text`,
  and `#content` conventions) are converted to `XmlBuilder` AST tuples
  and rendered with `XmlBuilder.generate/1`. No manual string
  concatenation is used for element construction, and text / attribute
  escaping is handled by `XmlBuilder` at render time.

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

  defp convert_to_xml_builder(data) when is_map(data) do
    # Lather allows maps as root, but XmlBuilder.generate expects a single element or list
    # We'll convert the map to a list of elements
    Enum.map(data, fn {key, value} ->
      convert_element(to_string(key), value)
    end)
  end

  defp convert_to_xml_builder(data) when is_list(data) do
    Enum.map(data, fn
      {key, value} -> convert_element(to_string(key), value)
      item -> convert_to_xml_builder(item)
    end)
    |> List.flatten()
  end

  defp convert_to_xml_builder(data), do: data

  defp convert_element(tag, value) when is_map(value) do
    {attrs, content} = extract_attributes_and_content(value)
    
    final_content = 
      cond do
        is_binary(content) -> content
        is_list(content) -> Enum.map(content, &convert_to_xml_builder/1) |> List.flatten()
        is_map(content) -> convert_to_xml_builder(content)
        true -> nil
      end

    XmlBuilder.element(tag, attrs, final_content)
  end

  defp convert_element(tag, value) when is_list(value) do
    # Separate attributes from children
    {attr_pairs, child_pairs} =
      Enum.split_with(value, fn 
        {k, _} -> String.starts_with?(to_string(k), "@")
        _ -> false
      end)
 
    attr_map =
      Map.new(attr_pairs, fn {k, v} ->
        {String.trim_leading(to_string(k), "@"), v}
      end)
 
    children =
      Enum.map(child_pairs, fn
        {child_tag, child_val} -> convert_element(to_string(child_tag), child_val)
        item -> convert_to_xml_builder(item)
      end)
      |> List.flatten()
 
    XmlBuilder.element(tag, attr_map, children)
  end

  defp convert_element(tag, value) do
    XmlBuilder.element(tag, to_string(value))
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
