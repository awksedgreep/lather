defmodule Lather.Integration.MtomRoundTripTest do
  @moduledoc """
  Integration tests for MTOM (Message Transmission Optimization Mechanism).

  Tests the complete MTOM workflow:
  - Building MTOM messages with attachments
  - Parsing MTOM multipart messages back
  - Binary data integrity through the cycle
  - Various attachment types and sizes
  - XOP Include reference resolution
  """
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Lather.Mtom.{Attachment, Builder, Mime}

  describe "MTOM message build and parse cycle" do
    test "single PDF attachment round-trips correctly" do
      # Create binary data that looks like a PDF
      pdf_data = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34>> <> :crypto.strong_rand_bytes(1000)

      params = %{
        "fileName" => "report.pdf",
        "document" => {:attachment, pdf_data, "application/pdf"}
      }

      # Build MTOM message
      {:ok, {content_type, body}} = Builder.build_mtom_message(:UploadDocument, params)

      # Verify content type structure
      assert String.starts_with?(content_type, "multipart/related")
      assert String.contains?(content_type, "boundary=")
      assert String.contains?(content_type, "type=\"application/xop+xml\"")

      # Parse the message back
      {:ok, {soap_part, attachment_parts}} = Mime.parse_multipart_message(content_type, body)

      # Verify SOAP part contains XOP include
      assert String.contains?(soap_part, "xop:Include")
      assert String.contains?(soap_part, "UploadDocument")
      assert String.contains?(soap_part, "report.pdf")

      # Verify attachment was preserved
      assert length(attachment_parts) == 1
      [attachment_part] = attachment_parts

      assert attachment_part.headers["content-type"] == "application/pdf"
      assert attachment_part.content == pdf_data
    end

    test "multiple attachments round-trip correctly" do
      pdf_data = :crypto.strong_rand_bytes(500)
      image_data = <<0x89, 0x50, 0x4E, 0x47>> <> :crypto.strong_rand_bytes(800)
      text_data = "This is plain text content for testing"

      params = %{
        "title" => "Multi-attachment Test",
        "pdfDoc" => {:attachment, pdf_data, "application/pdf"},
        "image" => {:attachment, image_data, "image/png"},
        "notes" => {:attachment, text_data, "text/plain"}
      }

      {:ok, {content_type, body}} = Builder.build_mtom_message(:UploadMultiple, params)
      {:ok, {soap_part, attachment_parts}} = Mime.parse_multipart_message(content_type, body)

      # Verify all attachments present
      assert length(attachment_parts) == 3

      # Collect attachment data by content type for comparison
      attachments_by_type = Enum.into(attachment_parts, %{}, fn part ->
        {part.headers["content-type"], part.content}
      end)

      assert attachments_by_type["application/pdf"] == pdf_data
      assert attachments_by_type["image/png"] == image_data
      assert attachments_by_type["text/plain"] == text_data

      # Verify SOAP part has correct structure
      assert String.contains?(soap_part, "Multi-attachment Test")

      # Should have 3 XOP includes
      xop_count = soap_part |> String.split("xop:Include") |> length() |> Kernel.-(1)
      assert xop_count == 3
    end

    test "nested attachments in complex structure round-trip correctly" do
      report_data = :crypto.strong_rand_bytes(300)
      chart_data = :crypto.strong_rand_bytes(400)
      summary_data = "Executive summary text"

      params = %{
        "report" => %{
          "metadata" => %{"title" => "Quarterly Report", "author" => "John Doe"},
          "content" => {:attachment, report_data, "application/pdf"},
          "appendix" => %{
            "chart" => {:attachment, chart_data, "image/png"},
            "summary" => {:attachment, summary_data, "text/plain"}
          }
        }
      }

      {:ok, {content_type, body}} = Builder.build_mtom_message(:ProcessReport, params)
      {:ok, {_soap_part, attachment_parts}} = Mime.parse_multipart_message(content_type, body)

      # All 3 nested attachments should be extracted
      assert length(attachment_parts) == 3

      # Verify each attachment's data integrity
      attachment_data = Enum.map(attachment_parts, & &1.content)
      assert report_data in attachment_data
      assert chart_data in attachment_data
      assert summary_data in attachment_data
    end

    test "attachments in array round-trip correctly" do
      files = [
        {:attachment, :crypto.strong_rand_bytes(100), "text/plain"},
        {:attachment, :crypto.strong_rand_bytes(200), "text/csv"},
        {:attachment, :crypto.strong_rand_bytes(150), "application/json"}
      ]

      params = %{
        "batchName" => "Batch Upload",
        "files" => files
      }

      {:ok, {content_type, body}} = Builder.build_mtom_message(:BatchUpload, params)
      {:ok, {_soap_part, attachment_parts}} = Mime.parse_multipart_message(content_type, body)

      assert length(attachment_parts) == 3

      content_types = Enum.map(attachment_parts, & &1.headers["content-type"])
      assert "text/plain" in content_types
      assert "text/csv" in content_types
      assert "application/json" in content_types
    end
  end

  describe "binary data integrity" do
    test "preserves exact binary content for random data" do
      # Test with various sizes of random binary data
      sizes = [0, 1, 10, 100, 1000, 10000, 100_000]

      for size <- sizes do
        original_data = if size == 0, do: <<>>, else: :crypto.strong_rand_bytes(size)

        params = %{"file" => {:attachment, original_data, "application/octet-stream"}}

        {:ok, {content_type, body}} = Builder.build_mtom_message(:Upload, params)
        {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(content_type, body)

        assert attachment_part.content == original_data,
               "Binary data mismatch for size #{size}"
      end
    end

    test "preserves binary data with all byte values" do
      # Create data with every possible byte value (0-255)
      all_bytes = for i <- 0..255, do: <<i>>, into: <<>>

      params = %{"file" => {:attachment, all_bytes, "application/octet-stream"}}

      {:ok, {content_type, body}} = Builder.build_mtom_message(:Upload, params)
      {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(content_type, body)

      assert attachment_part.content == all_bytes
      assert byte_size(attachment_part.content) == 256
    end

    test "preserves binary data with null bytes" do
      # Binary with embedded null bytes
      data_with_nulls = <<0, 1, 2, 0, 0, 0, 3, 4, 0, 5>>

      params = %{"file" => {:attachment, data_with_nulls, "application/octet-stream"}}

      {:ok, {content_type, body}} = Builder.build_mtom_message(:Upload, params)
      {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(content_type, body)

      assert attachment_part.content == data_with_nulls
    end

    test "preserves MIME boundary-like sequences in binary data" do
      # Binary that contains sequences similar to MIME boundaries
      tricky_data = "data--boundary\r\n--more-data\r\n\r\n--end--"

      params = %{"file" => {:attachment, tricky_data, "text/plain"}}

      {:ok, {content_type, body}} = Builder.build_mtom_message(:Upload, params)
      {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(content_type, body)

      assert attachment_part.content == tricky_data
    end

    test "preserves UTF-8 binary content" do
      utf8_content = "Hello 世界 🌍 Привет мир العربية"

      params = %{"file" => {:attachment, utf8_content, "text/plain; charset=utf-8"}}

      {:ok, {content_type, body}} = Builder.build_mtom_message(:Upload, params)
      {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(content_type, body)

      assert attachment_part.content == utf8_content
    end
  end

  describe "content type handling" do
    test "handles various document types" do
      document_types = [
        {"application/pdf", <<0x25, 0x50, 0x44, 0x46>>},
        {"application/msword", <<0xD0, 0xCF, 0x11, 0xE0>>},
        {"application/vnd.openxmlformats-officedocument.wordprocessingml.document", "PK" <> :crypto.strong_rand_bytes(10)},
        {"application/vnd.ms-excel", <<0xD0, 0xCF, 0x11, 0xE0>>},
        {"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "PK" <> :crypto.strong_rand_bytes(10)}
      ]

      for {content_type, data} <- document_types do
        params = %{"file" => {:attachment, data, content_type}}

        {:ok, {ct_header, body}} = Builder.build_mtom_message(:Upload, params)
        {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(ct_header, body)

        assert attachment_part.headers["content-type"] == content_type,
               "Content type mismatch for #{content_type}"
        assert attachment_part.content == data
      end
    end

    test "handles various image types" do
      image_types = [
        {"image/jpeg", <<0xFF, 0xD8, 0xFF, 0xE0>>},
        {"image/png", <<0x89, 0x50, 0x4E, 0x47>>},
        {"image/gif", <<0x47, 0x49, 0x46, 0x38>>},
        {"image/webp", "RIFF" <> <<0, 0, 0, 0>> <> "WEBP"},
        {"image/svg+xml", "<svg></svg>"}
      ]

      for {content_type, data} <- image_types do
        params = %{"image" => {:attachment, data, content_type}}

        {:ok, {ct_header, body}} = Builder.build_mtom_message(:UploadImage, params)
        {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(ct_header, body)

        assert attachment_part.headers["content-type"] == content_type
        assert attachment_part.content == data
      end
    end

    test "handles archive types" do
      archive_types = [
        {"application/zip", "PK" <> <<3, 4>> <> :crypto.strong_rand_bytes(20)},
        {"application/gzip", <<0x1F, 0x8B, 0x08>>},
        {"application/x-tar", :crypto.strong_rand_bytes(512)}
      ]

      for {content_type, data} <- archive_types do
        params = %{"archive" => {:attachment, data, content_type}}

        {:ok, {ct_header, body}} = Builder.build_mtom_message(:UploadArchive, params)
        {:ok, {_soap_part, [attachment_part]}} = Mime.parse_multipart_message(ct_header, body)

        assert attachment_part.headers["content-type"] == content_type
      end
    end
  end

  describe "custom content IDs" do
    test "preserves custom content ID in attachment" do
      custom_id = "my-custom-attachment-id@example.com"
      data = :crypto.strong_rand_bytes(100)

      params = %{
        "file" => {:attachment, data, "application/pdf", [content_id: custom_id]}
      }

      {:ok, {content_type, body}} = Builder.build_mtom_message(:Upload, params)
      {:ok, {soap_part, [attachment_part]}} = Mime.parse_multipart_message(content_type, body)

      # XOP include should reference the custom ID
      assert String.contains?(soap_part, custom_id)

      # Attachment should have the custom content ID in headers
      assert String.contains?(attachment_part.headers["content-id"], custom_id)
    end

    test "handles multiple attachments with custom IDs" do
      params = %{
        "mainDoc" => {:attachment, "main content", "application/pdf", [content_id: "main-doc@upload"]},
        "attachment1" => {:attachment, "attach 1", "text/plain", [content_id: "attach-1@upload"]},
        "attachment2" => {:attachment, "attach 2", "text/plain", [content_id: "attach-2@upload"]}
      }

      {:ok, {content_type, body}} = Builder.build_mtom_message(:UploadWithAttachments, params)
      {:ok, {soap_part, attachment_parts}} = Mime.parse_multipart_message(content_type, body)

      # All custom IDs should be in the SOAP part as XOP references
      assert String.contains?(soap_part, "main-doc@upload")
      assert String.contains?(soap_part, "attach-1@upload")
      assert String.contains?(soap_part, "attach-2@upload")

      # All attachments should be present
      assert length(attachment_parts) == 3
    end
  end

  describe "SOAP envelope integration" do
    test "SOAP 1.1 envelope with MTOM" do
      params = %{
        "data" => {:attachment, "test data", "text/plain"}
      }

      options = [
        namespace: "http://example.com/upload",
        version: :v1_1
      ]

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:Upload, params, options)

      # Should contain SOAP 1.1 namespace
      assert String.contains?(body, "http://schemas.xmlsoap.org/soap/envelope/")
      assert String.contains?(body, "Upload")
      assert String.contains?(body, "xop:Include")
    end

    test "SOAP 1.2 envelope with MTOM" do
      params = %{
        "data" => {:attachment, "test data", "text/plain"}
      }

      options = [
        namespace: "http://example.com/upload",
        version: :v1_2
      ]

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:Upload, params, options)

      # Should contain SOAP 1.2 namespace
      assert String.contains?(body, "http://www.w3.org/2003/05/soap-envelope")
    end

    test "MTOM message preserves non-attachment parameters" do
      params = %{
        "title" => "Test Document",
        "author" => "John Doe",
        "pages" => "100",
        "content" => {:attachment, "document content", "application/pdf"},
        "metadata" => %{
          "created" => "2024-03-15",
          "version" => "1.0"
        }
      }

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:CreateDocument, params)

      # All string parameters should be in the SOAP body
      assert String.contains?(body, "Test Document")
      assert String.contains?(body, "John Doe")
      assert String.contains?(body, "100")
      assert String.contains?(body, "2024-03-15")
      assert String.contains?(body, "1.0")
    end
  end

  describe "attachment struct creation and validation" do
    test "creates valid attachment from tuple" do
      data = :crypto.strong_rand_bytes(100)

      {:ok, attachment} = Attachment.from_tuple({:attachment, data, "application/pdf"})

      assert attachment.data == data
      assert attachment.content_type == "application/pdf"
      assert attachment.size == 100
      assert is_binary(attachment.content_id)
      assert :ok = Attachment.validate(attachment)
    end

    test "creates attachment with custom options" do
      data = "test content"

      {:ok, attachment} = Attachment.from_tuple(
        {:attachment, data, "text/plain", [content_id: "custom-id", content_transfer_encoding: "binary"]}
      )

      assert attachment.content_id == "custom-id"
      assert attachment.content_transfer_encoding == "binary"
    end

    test "generates XOP include reference" do
      attachment = Attachment.new("data", "text/plain")
      xop_include = Attachment.xop_include(attachment)

      assert %{"xop:Include" => include_data} = xop_include
      assert String.starts_with?(include_data["@href"], "cid:")
      assert include_data["@xmlns:xop"] == "http://www.w3.org/2004/08/xop/include"
    end

    test "content ID header format is correct" do
      attachment = Attachment.new("data", "text/plain", content_id: "test-id@example.com")

      header = Attachment.content_id_header(attachment)
      assert header == "<test-id@example.com>"
    end

    test "CID reference format is correct" do
      attachment = Attachment.new("data", "text/plain", content_id: "test-id@example.com")

      cid_ref = Attachment.cid_reference(attachment)
      assert cid_ref == "cid:test-id@example.com"
    end
  end

  describe "MIME utilities" do
    test "generates unique boundaries" do
      boundaries = for _ <- 1..100, do: Mime.generate_boundary()

      # All boundaries should be unique
      assert length(Enum.uniq(boundaries)) == 100

      # All should start with uuid:
      assert Enum.all?(boundaries, &String.starts_with?(&1, "uuid:"))
    end

    test "extracts boundary from content type header" do
      {:ok, boundary} = Mime.extract_boundary(
        "multipart/related; boundary=\"uuid:12345-abcde\"; type=\"application/xop+xml\""
      )
      assert boundary == "uuid:12345-abcde"
    end

    test "extracts boundary without quotes" do
      {:ok, boundary} = Mime.extract_boundary(
        "multipart/related; boundary=uuid:12345-abcde; type=\"application/xop+xml\""
      )
      assert boundary == "uuid:12345-abcde"
    end

    test "validates multipart/related content type" do
      assert :ok = Mime.validate_content_type(
        "multipart/related; boundary=\"test\"; type=\"application/xop+xml\""
      )

      assert {:error, :not_multipart_related} = Mime.validate_content_type("text/xml")
      assert {:error, :missing_boundary} = Mime.validate_content_type("multipart/related")
    end

    test "parses MIME headers correctly" do
      headers = Mime.parse_headers("""
      Content-Type: application/pdf
      Content-Transfer-Encoding: binary
      Content-ID: <attachment123@lather.soap>
      """)

      assert headers["content-type"] == "application/pdf"
      assert headers["content-transfer-encoding"] == "binary"
      assert headers["content-id"] == "<attachment123@lather.soap>"
    end
  end

  describe "builder utilities" do
    test "has_attachments? detects attachments correctly" do
      assert Builder.has_attachments?(%{"file" => {:attachment, "data", "text/plain"}})
      assert Builder.has_attachments?(%{"nested" => %{"file" => {:attachment, "data", "text/plain"}}})
      assert Builder.has_attachments?(%{"list" => [{:attachment, "data", "text/plain"}]})

      refute Builder.has_attachments?(%{"name" => "value"})
      refute Builder.has_attachments?(%{})
    end

    test "estimates message size reasonably" do
      small_data = :crypto.strong_rand_bytes(1000)
      large_data = :crypto.strong_rand_bytes(100_000)

      small_params = %{"file" => {:attachment, small_data, "application/octet-stream"}}
      large_params = %{"file" => {:attachment, large_data, "application/octet-stream"}}

      small_size = Builder.estimate_message_size(small_params)
      large_size = Builder.estimate_message_size(large_params)

      # Large should be much bigger than small
      assert large_size > small_size * 50

      # Sizes should be reasonable (not way off)
      assert small_size > 1000
      assert large_size > 100_000
    end

    test "validates attachments correctly" do
      valid_params = %{
        "file1" => {:attachment, "content", "text/plain"},
        "file2" => {:attachment, "content", "application/pdf"}
      }

      assert :ok = Builder.validate_attachments(valid_params)

      # Invalid content type
      invalid_params = %{"file" => {:attachment, "content", "invalid"}}
      assert {:error, _} = Builder.validate_attachments(invalid_params)
    end
  end
end
