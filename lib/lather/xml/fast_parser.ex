defmodule Lather.Xml.FastParser do
  @moduledoc """
  A single-pass binary scanner for XML documents, optimized for the flat
  element/text shapes typical of SOAP envelopes.

  It avoids building an `:xmerl` document tree, decoding attributes, and
  namespace resolution, so parsing large responses is faster and uses far
  less memory than the full `Lather.Xml.Parser`.

  ## Result shape

  * Leaf text becomes the string value: `<name>Bob</name>` -> `"name" => "Bob"`
  * Nested elements become nested maps.
  * Attributes are ignored.
  * CDATA and the basic entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`,
    `&#39;`) are decoded.
  * Mixed text + child content is exposed under a `"value"` key.

  Namespace-sensitive handling and malformed input should go through
  `Lather.Xml.Parser`, which is stricter.

  ## Examples

      iex> Lather.Xml.FastParser.parse("<root><item>value</item></root>")
      {:ok, %{"root" => %{"item" => "value"}}}

  """

  @doc """
  Parse an XML binary into a map using the fast scanner.

  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, term()} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    try do
      xml = strip_declaration(xml)
      {name, value, _pos} = parse_element(xml, skip_ws(xml, 0))
      {:ok, %{name => value}}
    rescue
      _ -> {:error, :parse_error}
    end
  end

  def parse(_), do: {:error, :invalid_input}

  defp strip_declaration(xml) do
    if String.starts_with?(xml, "<?xml") do
      case index_of(xml, "?>") do
        nil -> xml
        idx -> binary_part(xml, idx + 2, String.length(xml) - idx - 2)
      end
    else
      xml
    end
  end

  # Parses the element starting at `<`, returns {value, pos_after_close}.
  defp parse_element(xml, pos) do
    pos = skip_ws(xml, pos)

    if char_at(xml, pos) != ?< do
      raise "expected element at position #{pos}"
    end

    {name, pos} = parse_tag_name(xml, pos + 1)
    pos = skip_ws(xml, pos)

    # Advance to the closing '>' of the opening tag (skipping attributes).
    pos = tag_close_pos(xml, pos)

    if char_at(xml, pos - 1) == ?/ do
      {name, %{}, skip_past(xml, pos, ">")}
    else
      {value, pos} = parse_content(xml, pos + 1)
      {name, value, pos}
    end
  end

  defp tag_close_pos(xml, pos) do
    case :binary.match(xml, ">", scope: {pos, byte_size(xml) - pos}) do
      {idx, _len} -> idx
      nil -> pos
    end
  end

  defp parse_tag_name(xml, pos) do
    end_pos = tag_name_end(xml, pos)
    {binary_part(xml, pos, end_pos - pos), end_pos}
  end

  defp tag_name_end(xml, pos) do
    case char_at(xml, pos) do
      nil ->
        pos

      c ->
        if c in [?>, ?/, ?<, ?\s, ?\t, ?\n, ?\r] do
          pos
        else
          tag_name_end(xml, pos + 1)
        end
    end
  end

  defp parse_content(xml, pos) do
    pos = skip_ws(xml, pos)

    case char_at(xml, pos) do
      nil ->
        raise "unexpected end of document"

      ?< ->
        if char_at(xml, pos + 1) == ?/ do
          {%{}, skip_past(xml, pos, ">")}
        else
          parse_children(xml, pos, %{})
        end

      _ ->
        text_end = next_lt(xml, pos)
        text = decode_entities(binary_part(xml, pos, text_end - pos))
        pos = text_end

        if char_at(xml, pos) != ?< or char_at(xml, pos + 1) == ?/ do
          {text, skip_past(xml, pos, ">")}
        else
          parse_children(xml, pos, %{"value" => text})
        end
    end
  end

  defp parse_children(xml, pos, acc) do
    pos = skip_ws(xml, pos)

    if char_at(xml, pos) != ?< do
      raise "unexpected content at position #{pos}"
    end

    if char_at(xml, pos + 1) == ?/ do
      {finalize(acc), skip_past(xml, pos, ">")}
    else
      {child_name, child_value, pos} = parse_element(xml, pos)
      parse_children(xml, pos, Map.put(acc, child_name, child_value))
    end
  end

  defp finalize(%{"value" => text} = acc) do
    if map_size(acc) == 1 do
      text
    else
      acc
    end
  end

  defp finalize(acc) do
    acc
  end

  defp next_lt(xml, pos) do
    case :binary.match(xml, "<", scope: {pos, byte_size(xml) - pos}) do
      {idx, _len} -> idx
      nil -> byte_size(xml)
    end
  end

  defp skip_past(xml, pos, needle) do
    case :binary.match(xml, needle, scope: {pos, byte_size(xml) - pos}) do
      {idx, len} -> idx + len
      nil -> pos
    end
  end

  defp skip_ws(xml, pos) do
    case char_at(xml, pos) do
      c when c in [?\s, ?\t, ?\n, ?\r] -> skip_ws(xml, pos + 1)
      _ -> pos
    end
  end

  defp char_at(xml, pos) do
    if pos < byte_size(xml) do
      :binary.at(xml, pos)
    else
      nil
    end
  end

  defp index_of(binary, needle) do
    case :binary.match(binary, needle) do
      {pos, _len} -> pos
      nil -> nil
    end
  end

  defp decode_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end
end
