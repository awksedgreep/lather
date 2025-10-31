defmodule Lather.Mtom.AttachmentTest do
  use ExUnit.Case, async: true

  alias Lather.Mtom.Attachment

  describe "new/3" do
    test "creates attachment with binary data and content type" do
      data = <<1, 2, 3, 4, 5>>
      content_type = "application/pdf"

      attachment = Attachment.new(data, content_type)

      assert attachment.data == data
      assert attachment.content_type == content_type
      assert attachment.content_transfer_encoding == "binary"
      assert attachment.size == 5
      assert is_binary(attachment.id)
      assert is_binary(attachment.content_id)
      assert String.ends_with?(attachment.content_id, "@lather.soap")
    end

    test "creates attachment with custom content ID" do
      data = "test data"
      content_type = "text/plain"
      custom_id = "custom123@example.com"

      attachment = Attachment.new(data, content_type, content_id: custom_id)

      assert attachment.content_id == custom_id
    end

    test "creates attachment with custom transfer encoding" do
      data = "test data"
      content_type = "text/plain"
      encoding = "base64"

      attachment = Attachment.new(data, content_type, content_transfer_encoding: encoding)

      assert attachment.content_transfer_encoding == encoding
    end

    test "validates attachment by default" do
      # 200MB - over default limit
      data = String.duplicate("x", 200 * 1024 * 1024)
      content_type = "application/pdf"

      assert_raise ArgumentError, ~r/Invalid attachment/, fn ->
        Attachment.new(data, content_type)
      end
    end

    test "skips validation when requested" do
      # 200MB
      data = String.duplicate("x", 200 * 1024 * 1024)
      content_type = "application/pdf"

      attachment = Attachment.new(data, content_type, validate: false)

      assert attachment.size == 200 * 1024 * 1024
    end

    test "raises on invalid content type" do
      data = "test data"
      invalid_content_type = "not-a-mime-type"

      assert_raise ArgumentError, ~r/Invalid attachment/, fn ->
        Attachment.new(data, invalid_content_type)
      end
    end
  end

  describe "from_file/2" do
    setup do
      # Create temporary test files
      test_pdf_content = "%PDF-1.4 test content"
      test_txt_content = "Hello, world!"

      pdf_path = System.tmp_dir!() |> Path.join("test.pdf")
      txt_path = System.tmp_dir!() |> Path.join("test.txt")

      File.write!(pdf_path, test_pdf_content)
      File.write!(txt_path, test_txt_content)

      on_exit(fn ->
        File.rm(pdf_path)
        File.rm(txt_path)
      end)

      %{
        pdf_path: pdf_path,
        txt_path: txt_path,
        pdf_content: test_pdf_content,
        txt_content: test_txt_content
      }
    end

    test "creates attachment from file path", %{pdf_path: pdf_path, pdf_content: content} do
      {:ok, attachment} = Attachment.from_file(pdf_path)

      assert attachment.data == content
      assert attachment.content_type == "application/pdf"
      assert attachment.size == byte_size(content)
    end

    test "detects content type from file extension", %{txt_path: txt_path} do
      {:ok, attachment} = Attachment.from_file(txt_path)

      assert attachment.content_type == "text/plain"
    end

    test "allows content type override", %{pdf_path: pdf_path} do
      {:ok, attachment} = Attachment.from_file(pdf_path, content_type: "custom/type")

      assert attachment.content_type == "custom/type"
    end

    test "returns error for non-existent file" do
      {:error, {:file_error, :enoent}} = Attachment.from_file("/non/existent/file.pdf")
    end

    test "handles unknown file extensions" do
      unknown_path = System.tmp_dir!() |> Path.join("test.unknown")
      File.write!(unknown_path, "test content")

      on_exit(fn -> File.rm(unknown_path) end)

      {:ok, attachment} = Attachment.from_file(unknown_path)

      assert attachment.content_type == "application/octet-stream"
    end
  end

  describe "validate/1" do
    test "validates correct attachment" do
      attachment = Attachment.new("test data", "text/plain", validate: false)

      assert Attachment.validate(attachment) == :ok
    end

    test "fails validation for empty content type" do
      attachment = %Attachment{
        id: "test",
        content_type: "",
        data: "test",
        content_id: "test@soap",
        size: 4,
        content_transfer_encoding: "binary"
      }

      assert {:error, :invalid_content_type} = Attachment.validate(attachment)
    end

    test "fails validation for invalid content type" do
      attachment = %Attachment{
        id: "test",
        content_type: "not-a-mime-type",
        data: "test",
        content_id: "test@soap",
        size: 4,
        content_transfer_encoding: "binary"
      }

      assert {:error, :invalid_content_type} = Attachment.validate(attachment)
    end

    test "fails validation for oversized attachment" do
      # 150MB
      large_data = String.duplicate("x", 150 * 1024 * 1024)

      attachment = %Attachment{
        id: "test",
        content_type: "application/pdf",
        data: large_data,
        content_id: "test@soap",
        size: byte_size(large_data),
        content_transfer_encoding: "binary"
      }

      assert {:error, :attachment_too_large} = Attachment.validate(attachment)
    end

    test "fails validation for invalid encoding" do
      attachment = %Attachment{
        id: "test",
        content_type: "text/plain",
        data: "test",
        content_id: "test@soap",
        size: 4,
        content_transfer_encoding: "unsupported"
      }

      assert {:error, :unsupported_encoding} = Attachment.validate(attachment)
    end

    test "fails validation for non-binary data" do
      attachment = %Attachment{
        id: "test",
        content_type: "text/plain",
        # Not binary
        data: 123,
        content_id: "test@soap",
        size: 4,
        content_transfer_encoding: "binary"
      }

      assert {:error, :invalid_data} = Attachment.validate(attachment)
    end
  end

  describe "content_id_header/1" do
    test "generates proper Content-ID header format" do
      attachment = Attachment.new("test", "text/plain")

      header = Attachment.content_id_header(attachment)

      assert String.starts_with?(header, "<")
      assert String.ends_with?(header, ">")
      assert String.contains?(header, attachment.content_id)
    end
  end

  describe "cid_reference/1" do
    test "generates CID reference for XOP includes" do
      attachment = Attachment.new("test", "text/plain")

      cid_ref = Attachment.cid_reference(attachment)

      assert String.starts_with?(cid_ref, "cid:")
      assert String.contains?(cid_ref, attachment.content_id)
    end
  end

  describe "xop_include/1" do
    test "generates XOP Include element structure" do
      attachment = Attachment.new("test", "text/plain")

      xop_include = Attachment.xop_include(attachment)

      assert %{"xop:Include" => include_element} = xop_include
      assert include_element["@href"] == Attachment.cid_reference(attachment)
      assert include_element["@xmlns:xop"] == "http://www.w3.org/2004/08/xop/include"
    end
  end

  describe "is_attachment?/1" do
    test "identifies attachment tuples correctly" do
      assert Attachment.is_attachment?({:attachment, "data", "text/plain"}) == true
      assert Attachment.is_attachment?({:attachment, "data", "text/plain", []}) == true

      attachment_struct = Attachment.new("data", "text/plain")
      assert Attachment.is_attachment?(attachment_struct) == true
    end

    test "rejects non-attachment values" do
      assert Attachment.is_attachment?("regular string") == false
      assert Attachment.is_attachment?({:not_attachment, "data"}) == false
      assert Attachment.is_attachment?(%{data: "test"}) == false
      assert Attachment.is_attachment?(123) == false
      assert Attachment.is_attachment?(nil) == false
    end

    test "validates attachment tuple format" do
      # Invalid data type
      assert Attachment.is_attachment?({:attachment, 123, "text/plain"}) == false
      # Invalid content type
      assert Attachment.is_attachment?({:attachment, "data", 123}) == false
      # Wrong tuple size
      assert Attachment.is_attachment?({:attachment, "data"}) == false
    end
  end

  describe "from_tuple/1" do
    test "converts simple attachment tuple" do
      tuple = {:attachment, "test data", "text/plain"}

      {:ok, attachment} = Attachment.from_tuple(tuple)

      assert attachment.data == "test data"
      assert attachment.content_type == "text/plain"
      assert attachment.content_transfer_encoding == "binary"
    end

    test "converts attachment tuple with options" do
      tuple = {:attachment, "test data", "text/plain", [content_id: "custom123"]}

      {:ok, attachment} = Attachment.from_tuple(tuple)

      assert attachment.data == "test data"
      assert attachment.content_type == "text/plain"
      assert attachment.content_id == "custom123"
    end

    test "handles invalid attachment data in tuple" do
      # This will fail validation internally
      large_data = String.duplicate("x", 200 * 1024 * 1024)
      tuple = {:attachment, large_data, "text/plain"}

      assert {:error, :invalid_attachment_data} = Attachment.from_tuple(tuple)
    end

    test "rejects invalid tuple formats" do
      assert {:error, :invalid_attachment_tuple} = Attachment.from_tuple({:wrong, "data"})
      assert {:error, :invalid_attachment_tuple} = Attachment.from_tuple("not a tuple")
      assert {:error, :invalid_attachment_tuple} = Attachment.from_tuple({:attachment})
    end
  end

  describe "content type detection" do
    test "detects common file types correctly" do
      test_cases = [
        {"document.pdf", "application/pdf"},
        {"spreadsheet.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"},
        {"image.jpg", "image/jpeg"},
        {"image.png", "image/png"},
        {"archive.zip", "application/zip"},
        {"data.json", "application/json"},
        {"video.mp4", "video/mp4"},
        {"unknown.xyz", "application/octet-stream"}
      ]

      Enum.each(test_cases, fn {filename, expected_type} ->
        path = System.tmp_dir!() |> Path.join(filename)
        File.write!(path, "test content")

        on_exit(fn -> File.rm(path) end)

        {:ok, attachment} = Attachment.from_file(path)

        assert attachment.content_type == expected_type,
               "Expected #{expected_type} for #{filename}, got #{attachment.content_type}"
      end)
    end
  end

  describe "edge cases and error handling" do
    test "handles empty binary data" do
      attachment = Attachment.new("", "text/plain")

      assert attachment.data == ""
      assert attachment.size == 0
    end

    test "handles very large content type strings" do
      large_content_type = "application/" <> String.duplicate("x", 1000)
      attachment = Attachment.new("test", large_content_type)

      assert attachment.content_type == large_content_type
    end

    test "generates unique IDs and Content-IDs" do
      attachment1 = Attachment.new("test1", "text/plain")
      attachment2 = Attachment.new("test2", "text/plain")

      assert attachment1.id != attachment2.id
      assert attachment1.content_id != attachment2.content_id
    end

    test "handles Unicode data in attachments" do
      unicode_data = "Hello 世界 🌍 testing Unicode"
      attachment = Attachment.new(unicode_data, "text/plain")

      assert attachment.data == unicode_data
      assert attachment.size == byte_size(unicode_data)
    end

    test "preserves binary data integrity" do
      # Test with various binary patterns
      binary_patterns = [
        # Mixed bytes
        <<0, 1, 2, 3, 255, 254, 253>>,
        # Random binary
        :crypto.strong_rand_bytes(1000),
        # Null bytes
        String.duplicate(<<0>>, 100),
        # Max bytes
        String.duplicate(<<255>>, 100)
      ]

      Enum.each(binary_patterns, fn binary_data ->
        attachment = Attachment.new(binary_data, "application/octet-stream")
        assert attachment.data == binary_data
        assert attachment.size == byte_size(binary_data)
      end)
    end
  end

  describe "performance considerations" do
    test "handles reasonably large attachments efficiently" do
      # Test with 10MB file - should be fast
      large_data = :crypto.strong_rand_bytes(10 * 1024 * 1024)

      {time_microseconds, attachment} =
        :timer.tc(fn ->
          Attachment.new(large_data, "application/octet-stream", validate: false)
        end)

      # Should complete in under 100ms (100,000 microseconds)
      assert time_microseconds < 100_000
      assert attachment.size == 10 * 1024 * 1024
    end

    test "content ID generation is reasonably fast" do
      # Generate 1000 unique content IDs
      {time_microseconds, _content_ids} =
        :timer.tc(fn ->
          for _ <- 1..1000 do
            attachment = Attachment.new("test", "text/plain", validate: false)
            attachment.content_id
          end
        end)

      # Should complete in under 100ms
      assert time_microseconds < 100_000
    end
  end
end
