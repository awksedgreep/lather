defmodule Lather.Mtom.MimeTest do
  use ExUnit.Case, async: true

  alias Lather.Mtom.{Mime, Attachment}

  describe "generate_boundary/0" do
    test "generates valid UUID-based boundary" do
      boundary = Mime.generate_boundary()

      assert is_binary(boundary)
      assert String.starts_with?(boundary, "uuid:")
      assert String.length(boundary) > 10
    end

    test "generates unique boundaries" do
      boundary1 = Mime.generate_boundary()
      boundary2 = Mime.generate_boundary()

      assert boundary1 != boundary2
    end

    test "generates boundaries that match UUID format" do
      boundary = Mime.generate_boundary()

      # Remove "uuid:" prefix and check UUID format
      uuid_part = String.replace_prefix(boundary, "uuid:", "")

      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
               uuid_part
             )
    end

    test "generates boundaries suitable for MIME" do
      boundary = Mime.generate_boundary()

      # Should not contain problematic characters
      refute String.contains?(boundary, " ")
      refute String.contains?(boundary, "\r")
      refute String.contains?(boundary, "\n")
      refute String.contains?(boundary, "\"")
    end
  end

  describe "build_multipart_message/3" do
    setup do
      soap_envelope = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <TestOperation>
            <param>value</param>
          </TestOperation>
        </soap:Body>
      </soap:Envelope>
      """

      attachment1 = Attachment.new("PDF content here", "application/pdf")
      attachment2 = Attachment.new("Image data", "image/jpeg")

      %{
        soap_envelope: soap_envelope,
        attachment1: attachment1,
        attachment2: attachment2
      }
    end

    test "builds multipart message with single attachment", %{
      soap_envelope: soap,
      attachment1: att
    } do
      {content_type, body} = Mime.build_multipart_message(soap, [att])

      assert is_binary(content_type)
      assert is_binary(body)
      assert String.starts_with?(content_type, "multipart/related")
      assert String.contains?(content_type, "boundary=")
      assert String.contains?(content_type, "application/xop+xml")
    end

    test "builds multipart message with multiple attachments", %{
      soap_envelope: soap,
      attachment1: att1,
      attachment2: att2
    } do
      {_content_type, body} = Mime.build_multipart_message(soap, [att1, att2])

      assert String.contains?(body, "--uuid:")
      assert String.contains?(body, "application/pdf")
      assert String.contains?(body, "image/jpeg")
      assert String.contains?(body, "PDF content here")
      assert String.contains?(body, "Image data")
    end

    test "includes SOAP envelope in multipart body", %{soap_envelope: soap, attachment1: att} do
      {_content_type, body} = Mime.build_multipart_message(soap, [att])

      assert String.contains?(body, "TestOperation")
      assert String.contains?(body, "<param>value</param>")
      assert String.contains?(body, "application/xop+xml")
    end

    test "includes proper Content-ID headers", %{soap_envelope: soap, attachment1: att} do
      {_content_type, body} = Mime.build_multipart_message(soap, [att])

      assert String.contains?(body, "Content-ID: <rootpart@lather.soap>")
      assert String.contains?(body, "Content-ID: <#{att.content_id}>")
    end

    test "uses custom boundary when provided", %{soap_envelope: soap, attachment1: att} do
      custom_boundary = "custom-test-boundary-123"

      {content_type, body} = Mime.build_multipart_message(soap, [att], boundary: custom_boundary)

      assert String.contains?(content_type, custom_boundary)
      assert String.contains?(body, "--#{custom_boundary}")
      assert String.contains?(body, "--#{custom_boundary}--")
    end

    test "handles empty attachments list", %{soap_envelope: soap} do
      {content_type, body} = Mime.build_multipart_message(soap, [])

      assert String.starts_with?(content_type, "multipart/related")
      assert String.contains?(body, "TestOperation")
      # Should still have boundary markers
      assert String.contains?(body, "--uuid:")
    end

    test "uses custom SOAP content type when provided", %{soap_envelope: soap, attachment1: att} do
      custom_type = "application/soap+xml"

      {content_type, body} =
        Mime.build_multipart_message(soap, [att], soap_content_type: custom_type)

      assert String.contains?(content_type, custom_type)
      assert String.contains?(body, custom_type)
    end

    test "builds valid MIME structure", %{soap_envelope: soap, attachment1: att} do
      {_content_type, body} = Mime.build_multipart_message(soap, [att])

      # Should have proper CRLF line endings
      assert String.contains?(body, "\r\n")
      # Should have proper boundary termination
      assert String.ends_with?(String.trim(body), "--")
      # Should separate headers from content with double CRLF
      assert String.contains?(body, "\r\n\r\n")
    end
  end

  describe "parse_multipart_message/3" do
    setup do
      soap_envelope = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body><TestResponse><result>success</result></TestResponse></soap:Body>
      </soap:Envelope>
      """

      attachment = Attachment.new("Test file content", "text/plain")
      {content_type, body} = Mime.build_multipart_message(soap_envelope, [attachment])

      %{
        content_type: content_type,
        body: body,
        soap_envelope: soap_envelope,
        attachment: attachment
      }
    end

    test "parses multipart message successfully", %{content_type: ct, body: body} do
      {:ok, {soap_part, attachment_parts}} = Mime.parse_multipart_message(ct, body)

      assert is_binary(soap_part)
      assert is_list(attachment_parts)
      assert length(attachment_parts) == 1
    end

    test "extracts SOAP envelope correctly", %{content_type: ct, body: body} do
      {:ok, {soap_part, _attachments}} = Mime.parse_multipart_message(ct, body)

      assert String.contains?(soap_part, "TestResponse")
      assert String.contains?(soap_part, "<result>success</result>")
    end

    test "extracts attachment data correctly", %{content_type: ct, body: body} do
      {:ok, {_soap_part, attachment_parts}} = Mime.parse_multipart_message(ct, body)

      [attachment_part] = attachment_parts
      assert String.contains?(attachment_part.content, "Test file content")
      assert attachment_part.headers["content-type"] == "text/plain"
    end

    test "handles malformed content type" do
      malformed_ct = "not-multipart/invalid"
      body = "some body content"

      result = Mime.parse_multipart_message(malformed_ct, body)
      assert {:error, :boundary_not_found} = result
    end

    test "handles missing boundary in content type" do
      no_boundary_ct = "multipart/related; type=\"application/xop+xml\""
      body = "some body content"

      result = Mime.parse_multipart_message(no_boundary_ct, body)
      assert {:error, :boundary_not_found} = result
    end

    test "handles malformed multipart body" do
      valid_ct = "multipart/related; boundary=\"test-boundary\""
      malformed_body = "not a valid multipart body"

      result = Mime.parse_multipart_message(valid_ct, malformed_body)
      assert match?({:error, _}, result)
    end
  end

  describe "extract_boundary/1" do
    test "extracts quoted boundary" do
      content_type =
        "multipart/related; boundary=\"uuid:12345-abcde\"; type=\"application/xop+xml\""

      {:ok, boundary} = Mime.extract_boundary(content_type)

      assert boundary == "uuid:12345-abcde"
    end

    test "extracts unquoted boundary" do
      content_type = "multipart/related; boundary=uuid:12345-abcde; type=application/xop+xml"

      {:ok, boundary} = Mime.extract_boundary(content_type)

      assert boundary == "uuid:12345-abcde"
    end

    test "handles boundary with special characters" do
      content_type = "multipart/related; boundary=\"boundary-with_special.chars123\""

      {:ok, boundary} = Mime.extract_boundary(content_type)

      assert boundary == "boundary-with_special.chars123"
    end

    test "returns error when boundary not found" do
      content_type = "multipart/related; type=\"application/xop+xml\""

      result = Mime.extract_boundary(content_type)

      assert {:error, :boundary_not_found} = result
    end

    test "handles case insensitive boundary parameter" do
      content_type = "multipart/related; BOUNDARY=\"test-boundary\""

      {:ok, boundary} = Mime.extract_boundary(content_type)

      assert boundary == "test-boundary"
    end

    test "handles empty content type" do
      result = Mime.extract_boundary("")
      assert {:error, :boundary_not_found} = result
    end
  end

  describe "parse_headers/1" do
    test "parses standard MIME headers" do
      header_section =
        "Content-Type: application/pdf\r\nContent-ID: <attachment1>\r\nContent-Transfer-Encoding: binary"

      headers = Mime.parse_headers(header_section)

      assert headers["content-type"] == "application/pdf"
      assert headers["content-id"] == "<attachment1>"
      assert headers["content-transfer-encoding"] == "binary"
    end

    test "handles headers with extra whitespace" do
      header_section = "  Content-Type  :   application/pdf   \r\n  Content-ID  :  <test>  "

      headers = Mime.parse_headers(header_section)

      assert headers["content-type"] == "application/pdf"
      assert headers["content-id"] == "<test>"
    end

    test "handles mixed line endings" do
      header_section = "Content-Type: text/plain\nContent-ID: <test>\r\nContent-Length: 123"

      headers = Mime.parse_headers(header_section)

      assert headers["content-type"] == "text/plain"
      assert headers["content-id"] == "<test>"
      assert headers["content-length"] == "123"
    end

    test "ignores malformed header lines" do
      header_section = "Content-Type: text/plain\r\nMalformed header line\r\nContent-ID: <test>"

      headers = Mime.parse_headers(header_section)

      assert headers["content-type"] == "text/plain"
      assert headers["content-id"] == "<test>"
      refute Map.has_key?(headers, "malformed header line")
    end

    test "handles empty header section" do
      headers = Mime.parse_headers("")
      assert headers == %{}
    end

    test "converts header names to lowercase" do
      header_section = "CONTENT-TYPE: text/plain\r\nContent-ID: <test>\r\ncontent-length: 456"

      headers = Mime.parse_headers(header_section)

      assert headers["content-type"] == "text/plain"
      assert headers["content-id"] == "<test>"
      assert headers["content-length"] == "456"
    end
  end

  describe "build_content_type_header/3" do
    test "builds proper Content-Type header" do
      boundary = "uuid:test-boundary"
      type = "application/xop+xml"
      start = "rootpart@soap"

      header = Mime.build_content_type_header(boundary, type, start)

      assert String.starts_with?(header, "multipart/related")
      assert String.contains?(header, "boundary=\"#{boundary}\"")
      assert String.contains?(header, "type=\"#{type}\"")
      assert String.contains?(header, "start=\"<#{start}>\"")
    end

    test "handles special characters in parameters" do
      boundary = "uuid:boundary-with_special.chars"
      type = "application/soap+xml"
      start = "root@example.com"

      header = Mime.build_content_type_header(boundary, type, start)

      assert String.contains?(header, boundary)
      assert String.contains?(header, type)
      assert String.contains?(header, start)
    end
  end

  describe "validate_content_type/1" do
    test "validates proper multipart/related content type" do
      valid_ct = "multipart/related; boundary=\"test\"; type=\"application/xop+xml\""

      assert :ok = Mime.validate_content_type(valid_ct)
    end

    test "rejects non-multipart content types" do
      invalid_ct = "text/xml; charset=UTF-8"

      assert {:error, :not_multipart_related} = Mime.validate_content_type(invalid_ct)
    end

    test "rejects multipart/related without boundary" do
      no_boundary_ct = "multipart/related; type=\"application/xop+xml\""

      assert {:error, :missing_boundary} = Mime.validate_content_type(no_boundary_ct)
    end

    test "handles case insensitive validation" do
      mixed_case_ct = "MULTIPART/RELATED; boundary=\"test\""

      assert :ok = Mime.validate_content_type(mixed_case_ct)
    end
  end

  describe "integration scenarios" do
    test "round-trip: build and parse multipart message" do
      # Original data
      soap_envelope = """
      <?xml version="1.0" encoding="UTF-8"?>
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <TestOperation>
            <param1>value1</param1>
            <param2>value2</param2>
          </TestOperation>
        </soap:Body>
      </soap:Envelope>
      """

      original_attachments = [
        Attachment.new("First attachment data", "text/plain"),
        Attachment.new("Second attachment data", "application/octet-stream")
      ]

      # Build multipart message
      {content_type, body} = Mime.build_multipart_message(soap_envelope, original_attachments)

      # Parse it back
      {:ok, {parsed_soap, parsed_attachment_parts}} =
        Mime.parse_multipart_message(content_type, body)

      # Verify SOAP envelope
      assert String.contains?(parsed_soap, "TestOperation")
      assert String.contains?(parsed_soap, "value1")
      assert String.contains?(parsed_soap, "value2")

      # Verify attachments
      assert length(parsed_attachment_parts) == 2

      attachment_contents = Enum.map(parsed_attachment_parts, & &1.content)
      assert "First attachment data" in attachment_contents
      assert "Second attachment data" in attachment_contents
    end

    test "handles binary attachment data in round-trip" do
      soap_envelope = "<soap:Envelope><soap:Body><Test/></soap:Body></soap:Envelope>"

      # Create binary attachment
      binary_data = :crypto.strong_rand_bytes(1000)
      attachment = Attachment.new(binary_data, "application/octet-stream")

      # Round trip
      {content_type, body} = Mime.build_multipart_message(soap_envelope, [attachment])

      {:ok, {_parsed_soap, [parsed_attachment]}} =
        Mime.parse_multipart_message(content_type, body)

      # Binary data should be preserved exactly
      assert parsed_attachment.content == binary_data
    end

    test "preserves Unicode content in attachments" do
      soap_envelope = "<soap:Envelope><soap:Body><Test/></soap:Body></soap:Envelope>"

      unicode_content = "Hello 世界 🌍 Ελληνικά محتوى عربي"
      attachment = Attachment.new(unicode_content, "text/plain")

      # Round trip
      {content_type, body} = Mime.build_multipart_message(soap_envelope, [attachment])

      {:ok, {_parsed_soap, [parsed_attachment]}} =
        Mime.parse_multipart_message(content_type, body)

      # Unicode should be preserved
      assert parsed_attachment.content == unicode_content
    end
  end

  describe "performance and edge cases" do
    test "handles large number of attachments efficiently" do
      soap_envelope = "<soap:Envelope><soap:Body><Test/></soap:Body></soap:Envelope>"

      # Create 50 small attachments
      attachments =
        for i <- 1..50 do
          Attachment.new("Attachment #{i} content", "text/plain")
        end

      {time_microseconds, {content_type, body}} =
        :timer.tc(fn ->
          Mime.build_multipart_message(soap_envelope, attachments)
        end)

      # Should complete reasonably quickly (under 100ms)
      assert time_microseconds < 100_000

      # Verify all attachments are included
      assert length(attachments) == 50
      assert is_binary(content_type)
      assert byte_size(body) > 1000
    end

    test "handles empty SOAP envelope" do
      attachments = [Attachment.new("test", "text/plain")]

      {content_type, body} = Mime.build_multipart_message("", attachments)

      assert is_binary(content_type)
      assert is_binary(body)
      assert String.contains?(body, "test")
    end

    test "handles very long content type parameters" do
      long_boundary = "uuid:" <> String.duplicate("a", 100)
      long_type = "application/" <> String.duplicate("x", 100)
      long_start = "start" <> String.duplicate("y", 100) <> "@test.com"

      header = Mime.build_content_type_header(long_boundary, long_type, long_start)

      assert String.contains?(header, long_boundary)
      assert String.contains?(header, long_type)
      assert String.contains?(header, long_start)
    end

    test "handles malformed multipart boundaries gracefully" do
      content_type = "multipart/related; boundary=\"test-boundary\""
      malformed_body = "--wrong-boundary\r\nContent: test\r\n--wrong-boundary--"

      result = Mime.parse_multipart_message(content_type, malformed_body)

      # Should handle gracefully without crashing
      assert match?({:ok, {_, _}}, result) or match?({:error, _}, result)
    end
  end
end
