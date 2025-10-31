defmodule Lather.Mtom.Mime do
  @moduledoc """
  MIME utilities for MTOM multipart/related message handling.

  This module provides functions for building and parsing multipart/related
  MIME messages used in MTOM (Message Transmission Optimization Mechanism).

  MTOM messages use the multipart/related content type with the following structure:

      Content-Type: multipart/related;
                    boundary="uuid:12345-abcde";
                    type="application/xop+xml";
                    start="<rootpart@lather.soap>"

      --uuid:12345-abcde
      Content-Type: application/xop+xml; charset=UTF-8; type="text/xml"
      Content-Transfer-Encoding: 8bit
      Content-ID: <rootpart@lather.soap>

      <?xml version="1.0"?>
      <soap:Envelope>
        <!-- SOAP envelope with XOP includes -->
      </soap:Envelope>

      --uuid:12345-abcde
      Content-Type: application/pdf
      Content-Transfer-Encoding: binary
      Content-ID: <attachment123@lather.soap>

      %PDF-1.4 [binary data]...
      --uuid:12345-abcde--

  """

  alias Lather.Mtom.Attachment

  @doc """
  Generates a unique boundary string for multipart messages.

  ## Returns

    * Boundary string suitable for multipart MIME messages

  ## Examples

      boundary = Mime.generate_boundary()
      # "uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890"

  """
  @spec generate_boundary() :: String.t()
  def generate_boundary do
    "uuid:" <> generate_uuid()
  end

  @doc """
  Builds a complete multipart/related MIME message with SOAP envelope and attachments.

  ## Parameters

    * `soap_envelope` - The SOAP envelope XML as binary
    * `attachments` - List of Attachment structs
    * `options` - Additional options

  ## Options

    * `:boundary` - Custom boundary (auto-generated if not provided)
    * `:soap_content_type` - SOAP part content type (default: "application/xop+xml")
    * `:soap_charset` - SOAP part charset (default: "UTF-8")

  ## Returns

    * `{content_type_header, multipart_body}` - Complete MIME message

  ## Examples

      {content_type, body} = Mime.build_multipart_message(soap_xml, attachments)

  """
  @spec build_multipart_message(binary(), [Attachment.t()], keyword()) ::
          {String.t(), binary()}
  def build_multipart_message(soap_envelope, attachments, options \\ [])
      when is_binary(soap_envelope) and is_list(attachments) do
    boundary = Keyword.get(options, :boundary, generate_boundary())
    soap_content_type = Keyword.get(options, :soap_content_type, "application/xop+xml")
    soap_charset = Keyword.get(options, :soap_charset, "UTF-8")

    # Generate Content-ID for root SOAP part
    root_content_id = "rootpart@lather.soap"

    # Build Content-Type header
    content_type_header = build_content_type_header(boundary, soap_content_type, root_content_id)

    # Build multipart body
    multipart_body =
      build_multipart_body(
        boundary,
        soap_envelope,
        attachments,
        root_content_id,
        soap_content_type,
        soap_charset
      )

    {content_type_header, multipart_body}
  end

  @doc """
  Parses a multipart/related MIME message.

  ## Parameters

    * `content_type` - The Content-Type header value
    * `body` - The multipart message body
    * `options` - Parsing options

  ## Returns

    * `{:ok, {soap_part, attachments}}` - Successfully parsed message
    * `{:error, reason}` - Parsing error

  ## Examples

      {:ok, {soap_xml, attachments}} = Mime.parse_multipart_message(content_type, body)

  """
  @spec parse_multipart_message(String.t(), binary(), keyword()) ::
          {:ok, {binary(), [map()]}} | {:error, term()}
  def parse_multipart_message(content_type, body, _options \\ [])
      when is_binary(content_type) and is_binary(body) do
    with {:ok, boundary} <- extract_boundary(content_type),
         {:ok, parts} <- parse_multipart_body(body, boundary),
         {:ok, {soap_part, attachment_parts}} <- separate_parts(parts) do
      {:ok, {soap_part, attachment_parts}}
    end
  end

  @doc """
  Extracts the boundary parameter from a Content-Type header.

  ## Parameters

    * `content_type` - Content-Type header value

  ## Returns

    * `{:ok, boundary}` - Successfully extracted boundary
    * `{:error, reason}` - Extraction failed

  ## Examples

      {:ok, boundary} = Mime.extract_boundary("multipart/related; boundary=\"uuid:123\"")

  """
  @spec extract_boundary(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def extract_boundary(content_type) when is_binary(content_type) do
    case Regex.run(~r/boundary=(?:"([^"]+)"|([^;\s]+))/i, content_type) do
      [_, quoted_boundary] when quoted_boundary != "" ->
        {:ok, quoted_boundary}

      [_, "", unquoted_boundary] when unquoted_boundary != "" ->
        {:ok, unquoted_boundary}

      _ ->
        {:error, :boundary_not_found}
    end
  end

  @doc """
  Parses MIME headers from a header section.

  ## Parameters

    * `header_section` - Raw header text

  ## Returns

    * Map of parsed headers with lowercase keys

  ## Examples

      headers = Mime.parse_headers("Content-Type: application/pdf\\r\\nContent-ID: <att1>")
      # %{"content-type" => "application/pdf", "content-id" => "<att1>"}

  """
  @spec parse_headers(binary()) :: map()
  def parse_headers(header_section) when is_binary(header_section) do
    header_section
    |> String.split(["\r\n", "\n"])
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          clean_name = name |> String.trim() |> String.downcase()
          clean_value = String.trim(value)
          Map.put(acc, clean_name, clean_value)

        _ ->
          acc
      end
    end)
  end

  @doc """
  Builds a Content-Type header for multipart/related messages.

  ## Parameters

    * `boundary` - Multipart boundary
    * `type` - Root part type
    * `start` - Root part Content-ID

  ## Returns

    * Complete Content-Type header value

  ## Examples

      header = Mime.build_content_type_header("uuid:123", "application/xop+xml", "root@soap")

  """
  @spec build_content_type_header(String.t(), String.t(), String.t()) :: String.t()
  def build_content_type_header(boundary, type, start) do
    "multipart/related; " <>
      "boundary=\"#{boundary}\"; " <>
      "type=\"#{type}\"; " <>
      "start=\"<#{start}>\""
  end

  @doc """
  Validates a multipart/related Content-Type header.

  ## Parameters

    * `content_type` - Content-Type header to validate

  ## Returns

    * `:ok` if valid, `{:error, reason}` if invalid

  """
  @spec validate_content_type(String.t()) :: :ok | {:error, atom()}
  def validate_content_type(content_type) when is_binary(content_type) do
    cond do
      not String.starts_with?(String.downcase(content_type), "multipart/related") ->
        {:error, :not_multipart_related}

      not String.contains?(content_type, "boundary=") ->
        {:error, :missing_boundary}

      true ->
        :ok
    end
  end

  # Private functions

  defp build_multipart_body(
         boundary,
         soap_envelope,
         attachments,
         root_content_id,
         soap_content_type,
         soap_charset
       ) do
    # Start with root SOAP part
    soap_part = build_soap_part(soap_envelope, root_content_id, soap_content_type, soap_charset)

    # Build attachment parts
    attachment_parts = Enum.map(attachments, &build_attachment_part/1)

    # Combine all parts with boundary
    parts = [soap_part | attachment_parts]

    parts_content =
      parts
      |> Enum.map(&("--#{boundary}\r\n" <> &1))
      |> Enum.join("\r\n")

    parts_content <> "\r\n--#{boundary}--\r\n"
  end

  defp build_soap_part(soap_envelope, content_id, content_type, charset) do
    headers = [
      "Content-Type: #{content_type}; charset=#{charset}; type=\"text/xml\"",
      "Content-Transfer-Encoding: 8bit",
      "Content-ID: <#{content_id}>"
    ]

    headers_section = Enum.join(headers, "\r\n")
    headers_section <> "\r\n\r\n" <> soap_envelope <> "\r\n"
  end

  defp build_attachment_part(%Attachment{} = attachment) do
    headers = [
      "Content-Type: #{attachment.content_type}",
      "Content-Transfer-Encoding: #{attachment.content_transfer_encoding}",
      "Content-ID: #{Attachment.content_id_header(attachment)}"
    ]

    headers_section = Enum.join(headers, "\r\n")
    headers_section <> "\r\n\r\n" <> attachment.data <> "\r\n"
  end

  defp parse_multipart_body(body, boundary) when is_binary(body) and is_binary(boundary) do
    # Split body by boundary
    boundary_pattern = "--" <> boundary

    parts =
      body
      |> String.split(boundary_pattern)
      # Remove content before first boundary
      |> Enum.drop(1)
      # Remove closing boundary
      |> Enum.reject(&String.starts_with?(&1, "--"))
      |> Enum.map(&String.trim(&1, "\r\n"))
      |> Enum.reject(&(&1 == ""))

    parsed_parts =
      Enum.map(parts, fn part ->
        case String.split(part, "\r\n\r\n", parts: 2) do
          [headers_section, content] ->
            headers = parse_headers(headers_section)
            %{headers: headers, content: content}

          [content] ->
            # No headers, just content
            %{headers: %{}, content: content}
        end
      end)

    {:ok, parsed_parts}
  rescue
    _ -> {:error, :invalid_multipart_body}
  end

  defp separate_parts(parts) when is_list(parts) do
    # Find the root SOAP part (should have XOP content type or be the first part)
    soap_part_index =
      Enum.find_index(parts, fn part ->
        content_type = Map.get(part.headers, "content-type", "")
        String.contains?(content_type, "xop+xml") or String.contains?(content_type, "text/xml")
      end) || 0

    case List.pop_at(parts, soap_part_index) do
      {nil, _} ->
        {:error, :soap_part_not_found}

      {soap_part, attachment_parts} ->
        {:ok, {soap_part.content, attachment_parts}}
    end
  end

  defp generate_uuid do
    <<u0::32, u1::16, u2::16, u3::16, u4::48>> = :crypto.strong_rand_bytes(16)

    # Format as UUID v4
    u2_v4 = Bitwise.bor(Bitwise.band(u2, 0x0FFF), 0x4000)
    u3_variant = Bitwise.bor(Bitwise.band(u3, 0x3FFF), 0x8000)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [
      u0,
      u1,
      u2_v4,
      u3_variant,
      u4
    ])
    |> List.to_string()
  end
end
