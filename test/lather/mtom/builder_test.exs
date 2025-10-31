defmodule Lather.Mtom.BuilderTest do
  use ExUnit.Case, async: true

  alias Lather.Mtom.Builder

  describe "build_mtom_message/3" do
    test "builds MTOM message with single attachment" do
      params = %{
        "document" => {:attachment, "PDF content here", "application/pdf"},
        "filename" => "test.pdf"
      }

      {:ok, {content_type, body}} = Builder.build_mtom_message(:UploadDocument, params)

      assert is_binary(content_type)
      assert is_binary(body)
      assert String.starts_with?(content_type, "multipart/related")
      assert String.contains?(content_type, "boundary=")
      assert String.contains?(body, "UploadDocument")
      assert String.contains?(body, "test.pdf")
      assert String.contains?(body, "PDF content here")
      assert String.contains?(body, "application/pdf")
      assert String.contains?(body, "xop:Include")
    end

    test "builds MTOM message with multiple attachments" do
      params = %{
        "documents" => [
          {:attachment, "First document", "application/pdf"},
          {:attachment, "Second document", "text/plain"}
        ],
        "metadata" => %{"count" => "2"}
      }

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:UploadMultiple, params)

      assert String.contains?(body, "UploadMultiple")
      assert String.contains?(body, "First document")
      assert String.contains?(body, "Second document")
      assert String.contains?(body, "application/pdf")
      assert String.contains?(body, "text/plain")
      # Should have multiple XOP includes
      xop_count = body |> String.split("xop:Include") |> length() |> Kernel.-(1)
      assert xop_count == 2
    end

    test "builds MTOM message with nested attachments" do
      params = %{
        "report" => %{
          "summary" => {:attachment, "Summary content", "text/plain"},
          "details" => %{
            "chart" => {:attachment, "Chart data", "image/png"},
            "data" => {:attachment, "Raw data", "text/csv"}
          }
        }
      }

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:ProcessReport, params)

      assert String.contains?(body, "ProcessReport")
      assert String.contains?(body, "Summary content")
      assert String.contains?(body, "Chart data")
      assert String.contains?(body, "Raw data")
      assert String.contains?(body, "text/plain")
      assert String.contains?(body, "image/png")
      assert String.contains?(body, "text/csv")
    end

    test "builds MTOM message with attachment options" do
      params = %{
        "file" => {:attachment, "Test content", "text/plain", [content_id: "custom123"]}
      }

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:Upload, params)

      assert String.contains?(body, "Test content")
      assert String.contains?(body, "custom123")
    end

    test "includes proper SOAP envelope structure" do
      params = %{
        "document" => {:attachment, "Test", "text/plain"},
        "title" => "Document Title"
      }

      options = [
        namespace: "http://example.com/upload",
        version: :v1_2
      ]

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:Upload, params, options)

      # Should contain SOAP 1.2 namespace
      assert String.contains?(body, "http://www.w3.org/2003/05/soap-envelope")
      assert String.contains?(body, "Upload")
      assert String.contains?(body, "Document Title")
      assert String.contains?(body, "xop:Include")
    end

    test "handles custom boundary option" do
      params = %{"file" => {:attachment, "Test", "text/plain"}}
      custom_boundary = "custom-test-boundary"

      {:ok, {content_type, body}} =
        Builder.build_mtom_message(:Upload, params, boundary: custom_boundary)

      assert String.contains?(content_type, custom_boundary)
      assert String.contains?(body, custom_boundary)
    end

    test "returns error for invalid attachment data" do
      # Invalid attachment tuple
      params = %{"file" => {:attachment, 123, "text/plain"}}

      {:error, {:parameter_processing_error, _}} =
        Builder.build_mtom_message(:Upload, params)
    end

    test "handles empty parameters" do
      {:ok, {content_type, body}} = Builder.build_mtom_message(:EmptyOp, %{})

      assert String.starts_with?(content_type, "multipart/related")
      assert String.contains?(body, "EmptyOp")
    end

    test "handles parameters without attachments" do
      params = %{"name" => "John", "age" => "30"}

      {:ok, {_content_type, body}} = Builder.build_mtom_message(:CreateUser, params)

      assert String.contains?(body, "CreateUser")
      assert String.contains?(body, "John")
      assert String.contains?(body, "30")
      # Should still be multipart but without binary attachments
      refute String.contains?(body, "xop:Include")
    end
  end

  describe "process_parameters/1" do
    test "extracts single attachment and creates XOP include" do
      params = %{
        "document" => {:attachment, "PDF content", "application/pdf"},
        "title" => "Test Document"
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 1
      [attachment] = attachments
      assert attachment.data == "PDF content"
      assert attachment.content_type == "application/pdf"

      # Original attachment should be replaced with XOP include
      assert processed_params["title"] == "Test Document"
      xop_include = processed_params["document"]
      assert %{"xop:Include" => include_data} = xop_include
      assert String.starts_with?(include_data["@href"], "cid:")
    end

    test "extracts multiple attachments from list" do
      params = %{
        "files" => [
          {:attachment, "File 1", "text/plain"},
          "regular string",
          {:attachment, "File 2", "application/pdf"}
        ]
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 2

      # Check processed list
      processed_files = processed_params["files"]
      assert length(processed_files) == 3
      assert Enum.at(processed_files, 1) == "regular string"
      # First and third should be XOP includes
      assert %{"xop:Include" => _} = Enum.at(processed_files, 0)
      assert %{"xop:Include" => _} = Enum.at(processed_files, 2)
    end

    test "extracts nested attachments from maps" do
      params = %{
        "report" => %{
          "summary" => {:attachment, "Summary", "text/plain"},
          "metadata" => %{"title" => "Report"},
          "appendix" => {:attachment, "Appendix", "application/pdf"}
        }
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 2

      # Check nested structure
      report = processed_params["report"]
      assert report["metadata"]["title"] == "Report"
      assert %{"xop:Include" => _} = report["summary"]
      assert %{"xop:Include" => _} = report["appendix"]
    end

    test "handles deeply nested structures" do
      params = %{
        "level1" => %{
          "level2" => %{
            "level3" => [
              %{"file" => {:attachment, "Deep file", "text/plain"}},
              %{"info" => "regular data"}
            ]
          }
        }
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 1

      deep_file = get_in(processed_params, ["level1", "level2", "level3"])
      [file_item, info_item] = deep_file
      assert %{"xop:Include" => _} = file_item["file"]
      assert info_item["info"] == "regular data"
    end

    test "preserves non-attachment data unchanged" do
      params = %{
        "string" => "test",
        "number" => 42,
        "boolean" => true,
        "list" => [1, 2, 3],
        "map" => %{"key" => "value"}
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 0
      assert processed_params == params
    end

    test "handles attachment with custom options" do
      params = %{
        "file" => {:attachment, "Content", "text/plain", [content_id: "custom-id"]}
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 1
      [attachment] = attachments
      assert attachment.content_id == "custom-id"

      xop_include = processed_params["file"]
      assert String.contains?(xop_include["xop:Include"]["@href"], "custom-id")
    end

    test "handles empty parameters" do
      {:ok, {processed_params, attachments}} = Builder.process_parameters(%{})

      assert processed_params == %{}
      assert attachments == []
    end

    test "returns error for invalid attachment processing" do
      # This should trigger an error during attachment creation
      params = %{
        "file" => {:attachment, "x" |> String.duplicate(200 * 1024 * 1024), "text/plain"}
      }

      {:error, {:parameter_processing_error, _}} = Builder.process_parameters(params)
    end
  end

  describe "has_attachments?/1" do
    test "detects single attachment" do
      params = %{"file" => {:attachment, "data", "text/plain"}}
      assert Builder.has_attachments?(params) == true
    end

    test "detects attachments in lists" do
      params = %{
        "files" => [
          "regular string",
          {:attachment, "data", "text/plain"}
        ]
      }

      assert Builder.has_attachments?(params) == true
    end

    test "detects nested attachments" do
      params = %{
        "report" => %{
          "appendix" => {:attachment, "data", "application/pdf"}
        }
      }

      assert Builder.has_attachments?(params) == true
    end

    test "detects attachments with options" do
      params = %{
        "file" => {:attachment, "data", "text/plain", [content_id: "test"]}
      }

      assert Builder.has_attachments?(params) == true
    end

    test "returns false for parameters without attachments" do
      params = %{
        "name" => "John",
        "data" => [1, 2, 3],
        "info" => %{"key" => "value"}
      }

      assert Builder.has_attachments?(params) == false
    end

    test "returns false for empty parameters" do
      assert Builder.has_attachments?(%{}) == false
    end

    test "handles complex nested structures without attachments" do
      params = %{
        "level1" => %{
          "level2" => [
            %{"data" => "value1"},
            %{"data" => "value2"}
          ]
        }
      }

      assert Builder.has_attachments?(params) == false
    end

    test "detects attachments in deeply nested structures" do
      params = %{
        "level1" => %{
          "level2" => [
            %{"data" => "value1"},
            %{"file" => {:attachment, "data", "text/plain"}}
          ]
        }
      }

      assert Builder.has_attachments?(params) == true
    end
  end

  describe "validate_attachments/1" do
    test "validates correct attachments" do
      params = %{
        "file1" => {:attachment, "content1", "text/plain"},
        "file2" => {:attachment, "content2", "application/pdf"}
      }

      assert :ok = Builder.validate_attachments(params)
    end

    test "validates nested attachments" do
      params = %{
        "report" => %{
          "summary" => {:attachment, "summary", "text/plain"},
          "data" => [
            {:attachment, "data1", "text/csv"},
            {:attachment, "data2", "application/json"}
          ]
        }
      }

      assert :ok = Builder.validate_attachments(params)
    end

    test "validates attachments with options" do
      params = %{
        "file" => {:attachment, "content", "text/plain", [content_id: "test123"]}
      }

      assert :ok = Builder.validate_attachments(params)
    end

    test "passes validation for parameters without attachments" do
      params = %{"name" => "John", "age" => 30}

      assert :ok = Builder.validate_attachments(params)
    end

    test "returns error for invalid attachment data" do
      # Oversized attachment
      large_data = String.duplicate("x", 200 * 1024 * 1024)
      params = %{"file" => {:attachment, large_data, "text/plain"}}

      {:error, {:attachment_validation_error, _}} = Builder.validate_attachments(params)
    end

    test "returns error for invalid content type" do
      params = %{"file" => {:attachment, "data", "invalid-content-type"}}

      {:error, {:attachment_validation_error, _}} = Builder.validate_attachments(params)
    end

    test "returns error for invalid attachment tuple" do
      params = %{"file" => {:attachment, 123, "text/plain"}}

      {:error, {:attachment_validation_error, _}} = Builder.validate_attachments(params)
    end
  end

  describe "estimate_message_size/2" do
    test "estimates size for single attachment" do
      params = %{
        "file" => {:attachment, String.duplicate("x", 1000), "text/plain"},
        "name" => "test"
      }

      size = Builder.estimate_message_size(params)

      # Should be close to 1000 bytes + overhead
      assert size > 1000
      assert size < 2000
    end

    test "estimates size for multiple attachments" do
      params = %{
        "files" => [
          {:attachment, String.duplicate("a", 500), "text/plain"},
          {:attachment, String.duplicate("b", 800), "application/pdf"}
        ]
      }

      size = Builder.estimate_message_size(params)

      # Should account for both attachments + overhead
      # 500 + 800
      assert size > 1300
      # with reasonable overhead
      assert size < 3000
    end

    test "includes custom base SOAP size" do
      params = %{"file" => {:attachment, String.duplicate("x", 1000), "text/plain"}}

      size_default = Builder.estimate_message_size(params)
      size_custom = Builder.estimate_message_size(params, 5000)

      # Custom base should result in larger estimate
      assert size_custom > size_default
      # 5000 - 1024 (default)
      assert size_custom - size_default >= 4000
    end

    test "handles nested attachments in size calculation" do
      params = %{
        "report" => %{
          "summary" => {:attachment, String.duplicate("s", 300), "text/plain"},
          "details" => {:attachment, String.duplicate("d", 700), "application/pdf"}
        }
      }

      size = Builder.estimate_message_size(params)

      # Should find both nested attachments
      # 300 + 700
      assert size > 1000
      # with overhead
      assert size < 2500
    end

    test "returns reasonable size for parameters without attachments" do
      params = %{"name" => "John", "age" => "30"}

      size = Builder.estimate_message_size(params)

      # Should return base SOAP size since no attachments
      # default base size
      assert size >= 1024
      # with minimal overhead
      assert size < 1600
    end

    test "handles empty parameters" do
      size = Builder.estimate_message_size(%{})

      assert size >= 1024
      assert size < 1200
    end

    test "handles very large attachment estimates" do
      # 50MB attachment
      large_size = 50 * 1024 * 1024
      params = %{"file" => {:attachment, String.duplicate("x", large_size), "application/zip"}}

      size = Builder.estimate_message_size(params)

      # Should be close to the large size + overhead
      assert size > large_size
      # reasonable overhead
      assert size < large_size + 10000
    end
  end

  describe "error handling and edge cases" do
    test "handles malformed attachment tuples gracefully" do
      params = %{
        "good" => {:attachment, "data", "text/plain"},
        "bad1" => {:attachment, "missing_content_type"},
        "bad2" => {:not_attachment, "data", "text/plain"},
        "regular" => "normal data"
      }

      # Should fail during processing due to malformed attachment
      {:error, {:parameter_processing_error, _}} = Builder.process_parameters(params)
    end

    test "handles nil and unusual values in parameters" do
      params = %{
        "nil_value" => nil,
        "atom" => :test_atom,
        "function" => &String.length/1,
        "file" => {:attachment, "data", "text/plain"}
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 1
      assert processed_params["nil_value"] == nil
      assert processed_params["atom"] == :test_atom
      assert is_function(processed_params["function"])
    end

    test "preserves binary data integrity in attachments" do
      binary_data = :crypto.strong_rand_bytes(1000)
      params = %{"binary" => {:attachment, binary_data, "application/octet-stream"}}

      {:ok, {_processed_params, attachments}} = Builder.process_parameters(params)

      [attachment] = attachments
      assert attachment.data == binary_data
    end

    test "handles Unicode content in attachments" do
      unicode_content = "Hello 世界 🌍 Ελληνικά"
      params = %{"unicode" => {:attachment, unicode_content, "text/plain"}}

      {:ok, {_processed_params, attachments}} = Builder.process_parameters(params)

      [attachment] = attachments
      assert attachment.data == unicode_content
    end

    test "handles very deep nesting without stack overflow" do
      # Create deeply nested structure
      deep_params =
        Enum.reduce(1..50, %{"file" => {:attachment, "data", "text/plain"}}, fn i, acc ->
          %{"level#{i}" => acc}
        end)

      {:ok, {_processed_params, attachments}} = Builder.process_parameters(deep_params)

      assert length(attachments) == 1
    end

    test "handles circular references gracefully" do
      # Elixir maps can't have true circular references, but we can test
      # with repeated references to the same structure
      shared_data = %{"shared" => "value"}

      params = %{
        "ref1" => shared_data,
        "ref2" => shared_data,
        "attachment" => {:attachment, "data", "text/plain"}
      }

      {:ok, {processed_params, attachments}} = Builder.process_parameters(params)

      assert length(attachments) == 1
      assert processed_params["ref1"] == shared_data
      assert processed_params["ref2"] == shared_data
    end

    test "handles attachment processing with invalid SOAP envelope options" do
      params = %{"file" => {:attachment, "data", "text/plain"}}

      # Invalid namespace should still work
      {:ok, {_content_type, body}} =
        Builder.build_mtom_message(:Test, params, namespace: :invalid_namespace)

      assert String.contains?(body, "Test")
      assert String.contains?(body, "data")
    end
  end

  describe "performance considerations" do
    test "processes large number of attachments efficiently" do
      # Create 20 small attachments
      attachments_map =
        for i <- 1..20, into: %{} do
          {"file#{i}", {:attachment, "Content #{i}", "text/plain"}}
        end

      {time_microseconds, {:ok, {_processed, attachments}}} =
        :timer.tc(fn -> Builder.process_parameters(attachments_map) end)

      assert length(attachments) == 20
      # Should complete in reasonable time (under 50ms)
      assert time_microseconds < 50_000
    end

    test "handles large attachment data efficiently" do
      # 5MB attachment
      large_data = String.duplicate("x", 5 * 1024 * 1024)
      params = %{"large" => {:attachment, large_data, "application/zip"}}

      {time_microseconds, {:ok, {_processed, attachments}}} =
        :timer.tc(fn -> Builder.process_parameters(params) end)

      [attachment] = attachments
      assert byte_size(attachment.data) == 5 * 1024 * 1024
      # Should complete in reasonable time (under 100ms)
      assert time_microseconds < 100_000
    end

    test "size estimation is fast for complex structures" do
      # Create complex nested structure with many attachments
      complex_params = %{
        "reports" =>
          Enum.map(1..10, fn i ->
            %{
              "summary" => {:attachment, "Summary #{i}", "text/plain"},
              "data" => {:attachment, String.duplicate("d", 1000), "text/csv"}
            }
          end)
      }

      {time_microseconds, size} =
        :timer.tc(fn -> Builder.estimate_message_size(complex_params) end)

      # Should account for all attachments
      assert size > 10_000
      # Should be very fast (under 10ms)
      assert time_microseconds < 10_000
    end
  end
end
