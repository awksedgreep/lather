defmodule MtomClientExample do
  @moduledoc """
  Example of using Lather's MTOM (Message Transmission Optimization Mechanism) support.

  This example demonstrates:
  - Creating attachments from binary data with `Attachment.new/3`
  - Creating attachments from files with `Attachment.from_file/2`
  - Building MTOM messages with `Builder.build_mtom_message/3`
  - Using attachments in DynamicClient calls with `{:attachment, data, content_type}` tuples
  - Handling multiple attachments in a single request
  - Size estimation and validation for attachments

  MTOM is used to efficiently transfer binary data (like files, images, PDFs) in SOAP
  messages by packaging them as MIME attachments rather than base64-encoding them
  inline in the XML.
  """

  alias Lather.Mtom.{Attachment, Builder}

  @document_service_wsdl "https://documents.example.com/DocumentService?wsdl"

  def run do
    IO.puts("MTOM Client Example")
    IO.puts("==================")
    IO.puts("")

    # Demonstrate the different MTOM features
    demo_attachment_creation()
    demo_file_attachments()
    demo_mtom_message_building()
    demo_dynamic_client_usage()
    demo_multiple_attachments()
    demo_size_estimation_and_validation()
  end

  # ===========================================================================
  # Section 1: Creating Attachments from Binary Data
  # ===========================================================================

  @doc """
  Demonstrates creating attachments from binary data using `Attachment.new/3`.

  The `Attachment.new/3` function creates an attachment struct from raw binary data.
  It automatically generates a unique content ID and validates the attachment.
  """
  def demo_attachment_creation do
    IO.puts("1. Creating Attachments from Binary Data")
    IO.puts("-----------------------------------------")

    # Simple PDF attachment from binary data
    # In a real application, this would be actual PDF content
    pdf_data = <<0x25, 0x50, 0x44, 0x46>> <> "...PDF content here..."

    # Create a basic attachment with auto-generated content ID
    pdf_attachment = Attachment.new(pdf_data, "application/pdf")

    IO.puts("Created PDF attachment:")
    IO.puts("  - Content-ID: #{pdf_attachment.content_id}")
    IO.puts("  - Content-Type: #{pdf_attachment.content_type}")
    IO.puts("  - Size: #{pdf_attachment.size} bytes")
    IO.puts("  - Transfer Encoding: #{pdf_attachment.content_transfer_encoding}")
    IO.puts("")

    # Create an image attachment with a custom content ID
    # Custom content IDs are useful when you need to reference attachments
    # in a specific way in your SOAP message
    image_data = <<0x89, 0x50, 0x4E, 0x47>> <> "...PNG image data..."

    image_attachment = Attachment.new(image_data, "image/png",
      content_id: "company-logo@example.com"
    )

    IO.puts("Created image attachment with custom content ID:")
    IO.puts("  - Content-ID: #{image_attachment.content_id}")
    IO.puts("  - Content-Type: #{image_attachment.content_type}")
    IO.puts("  - Size: #{image_attachment.size} bytes")
    IO.puts("")

    # Create an attachment with custom transfer encoding
    # Most binary data uses "binary" encoding, but base64 is also supported
    xml_data = "<?xml version=\"1.0\"?><data>Sample XML content</data>"

    xml_attachment = Attachment.new(xml_data, "application/xml",
      content_id: "metadata-xml@example.com",
      content_transfer_encoding: "binary"
    )

    IO.puts("Created XML attachment with custom encoding:")
    IO.puts("  - Content-ID: #{xml_attachment.content_id}")
    IO.puts("  - Content-Type: #{xml_attachment.content_type}")
    IO.puts("  - Size: #{xml_attachment.size} bytes")
    IO.puts("  - Transfer Encoding: #{xml_attachment.content_transfer_encoding}")
    IO.puts("")

    # Demonstrate helper functions for working with attachments
    IO.puts("Attachment helper functions:")
    IO.puts("  - Content-ID header: #{Attachment.content_id_header(pdf_attachment)}")
    IO.puts("  - CID reference: #{Attachment.cid_reference(pdf_attachment)}")
    IO.puts("  - XOP Include: #{inspect(Attachment.xop_include(pdf_attachment))}")
    IO.puts("")
  end

  # ===========================================================================
  # Section 2: Creating Attachments from Files
  # ===========================================================================

  @doc """
  Demonstrates creating attachments from files using `Attachment.from_file/2`.

  The `from_file/2` function reads a file from disk and automatically detects
  the content type based on the file extension. You can also override the
  content type manually if needed.
  """
  def demo_file_attachments do
    IO.puts("2. Creating Attachments from Files")
    IO.puts("-----------------------------------")

    # Example: Loading a PDF from file
    # The content type is automatically detected from the .pdf extension
    IO.puts("Loading attachment from file (auto-detect content type):")
    IO.puts("  {:ok, attachment} = Attachment.from_file(\"document.pdf\")")
    IO.puts("")

    # Example: Loading with explicit content type override
    IO.puts("Loading with explicit content type:")
    IO.puts("  {:ok, attachment} = Attachment.from_file(\"data.bin\",")
    IO.puts("    content_type: \"application/octet-stream\"")
    IO.puts("  )")
    IO.puts("")

    # Example: Loading with custom content ID
    IO.puts("Loading with custom content ID:")
    IO.puts("  {:ok, attachment} = Attachment.from_file(\"report.xlsx\",")
    IO.puts("    content_id: \"monthly-report@example.com\"")
    IO.puts("  )")
    IO.puts("")

    # Demonstrate error handling for file operations
    IO.puts("Error handling for file attachments:")

    case Attachment.from_file("/nonexistent/path/file.pdf") do
      {:ok, _attachment} ->
        IO.puts("  File loaded successfully")

      {:error, {:file_error, reason}} ->
        IO.puts("  Error loading file: #{inspect(reason)}")
        IO.puts("  (This is expected for the nonexistent file example)")
    end

    IO.puts("")

    # Show supported file extensions and their content types
    IO.puts("Supported file extensions (auto-detected content types):")
    IO.puts("  - Documents: .pdf, .doc, .docx, .xls, .xlsx, .ppt, .pptx")
    IO.puts("  - Images: .jpg, .jpeg, .png, .gif, .tiff, .bmp, .webp")
    IO.puts("  - Archives: .zip, .rar, .7z, .gz")
    IO.puts("  - Text: .txt, .csv, .json, .xml")
    IO.puts("  - Media: .mp4, .avi, .mp3, .wav")
    IO.puts("  - Unknown extensions default to: application/octet-stream")
    IO.puts("")
  end

  # ===========================================================================
  # Section 3: Building MTOM Messages
  # ===========================================================================

  @doc """
  Demonstrates building MTOM messages with `Builder.build_mtom_message/3`.

  The Builder module handles the complete process of:
  1. Detecting attachment tuples in parameters
  2. Converting them to Attachment structs
  3. Replacing attachment data with XOP Include references
  4. Building the SOAP envelope
  5. Packaging everything into a multipart/related MIME message
  """
  def demo_mtom_message_building do
    IO.puts("3. Building MTOM Messages with Builder")
    IO.puts("--------------------------------------")

    # Create sample binary data for demonstration
    pdf_data = "Sample PDF binary content for demonstration"
    image_data = "Sample image binary content"

    # Build an MTOM message with attachments
    # Attachments are specified using the {:attachment, data, content_type} tuple format
    params = %{
      "documentTitle" => "Monthly Report",
      "author" => "Jane Smith",
      "documentContent" => {:attachment, pdf_data, "application/pdf"},
      "thumbnail" => {:attachment, image_data, "image/jpeg"}
    }

    IO.puts("Building MTOM message with parameters:")
    IO.puts("  %{")
    IO.puts("    \"documentTitle\" => \"Monthly Report\",")
    IO.puts("    \"author\" => \"Jane Smith\",")
    IO.puts("    \"documentContent\" => {:attachment, pdf_data, \"application/pdf\"},")
    IO.puts("    \"thumbnail\" => {:attachment, image_data, \"image/jpeg\"}")
    IO.puts("  }")
    IO.puts("")

    # Check if parameters contain attachments
    has_attachments = Builder.has_attachments?(params)
    IO.puts("Has attachments: #{has_attachments}")
    IO.puts("")

    # Process parameters to see how attachments are extracted
    case Builder.process_parameters(params) do
      {:ok, {processed_params, attachments}} ->
        IO.puts("Processed parameters (attachments replaced with XOP includes):")
        IO.puts("  Number of attachments extracted: #{length(attachments)}")
        IO.puts("")

        IO.puts("Attachment details:")

        Enum.each(attachments, fn attachment ->
          IO.puts("  - Content-ID: #{attachment.content_id}")
          IO.puts("    Type: #{attachment.content_type}")
          IO.puts("    Size: #{attachment.size} bytes")
        end)

        IO.puts("")

        IO.puts("Processed parameter keys: #{inspect(Map.keys(processed_params))}")
        IO.puts("(Binary data has been replaced with XOP Include references)")
        IO.puts("")

      {:error, reason} ->
        IO.puts("Error processing parameters: #{inspect(reason)}")
    end

    # Build the complete MTOM message
    IO.puts("Building complete MTOM message:")

    options = [
      namespace: "http://documents.example.com/upload"
    ]

    case Builder.build_mtom_message(:UploadDocument, params, options) do
      {:ok, {content_type, _body}} ->
        IO.puts("  Content-Type: #{content_type}")
        IO.puts("  Message built successfully!")
        IO.puts("")
        IO.puts("The Content-Type header includes:")
        IO.puts("  - multipart/related media type")
        IO.puts("  - MIME boundary for separating parts")
        IO.puts("  - type=application/xop+xml for MTOM")
        IO.puts("  - start parameter pointing to SOAP envelope")

      {:error, reason} ->
        IO.puts("  Error building message: #{inspect(reason)}")
    end

    IO.puts("")
  end

  # ===========================================================================
  # Section 4: Using Attachments with DynamicClient
  # ===========================================================================

  @doc """
  Demonstrates using attachments in DynamicClient calls.

  When making SOAP calls with attachments, you simply include attachment tuples
  in your parameters. The DynamicClient automatically detects these and uses
  MTOM encoding for the request.

  Attachment tuple formats:
  - `{:attachment, binary_data, content_type}` - Basic attachment
  - `{:attachment, binary_data, content_type, options}` - With options
  """
  def demo_dynamic_client_usage do
    IO.puts("4. Using Attachments with DynamicClient")
    IO.puts("---------------------------------------")

    IO.puts("The {:attachment, data, content_type} tuple format:")
    IO.puts("")
    IO.puts("  # Basic attachment tuple")
    IO.puts("  {:attachment, pdf_binary, \"application/pdf\"}")
    IO.puts("")
    IO.puts("  # Attachment with options (custom content ID)")
    IO.puts("  {:attachment, image_binary, \"image/png\", [content_id: \"logo@example.com\"]}")
    IO.puts("")

    # Demonstrate checking if a value is an attachment
    pdf_data = "sample pdf data"
    test_values = [
      {:attachment, pdf_data, "application/pdf"},
      {:attachment, pdf_data, "image/jpeg", [content_id: "test"]},
      "regular string value",
      123,
      %{"nested" => "map"}
    ]

    IO.puts("Checking values with Attachment.is_attachment?/1:")

    Enum.each(test_values, fn value ->
      is_att = Attachment.is_attachment?(value)
      display = if is_tuple(value), do: inspect(value) |> String.slice(0, 50), else: inspect(value)
      IO.puts("  #{display}... => #{is_att}")
    end)

    IO.puts("")

    # Example of a complete upload workflow
    IO.puts("Example: Complete upload workflow with DynamicClient")
    IO.puts("")
    IO.puts("  # 1. Connect to the document service")
    IO.puts("  {:ok, client} = Lather.DynamicClient.new(wsdl_url)")
    IO.puts("")
    IO.puts("  # 2. Read file content")
    IO.puts("  {:ok, pdf_content} = File.read(\"report.pdf\")")
    IO.puts("")
    IO.puts("  # 3. Prepare parameters with attachment")
    IO.puts("  params = %{")
    IO.puts("    \"fileName\" => \"report.pdf\",")
    IO.puts("    \"fileContent\" => {:attachment, pdf_content, \"application/pdf\"},")
    IO.puts("    \"metadata\" => %{")
    IO.puts("      \"author\" => \"John Doe\",")
    IO.puts("      \"department\" => \"Engineering\"")
    IO.puts("    }")
    IO.puts("  }")
    IO.puts("")
    IO.puts("  # 4. Make the SOAP call - MTOM is used automatically")
    IO.puts("  {:ok, response} = Lather.DynamicClient.call(client, \"UploadDocument\", params)")
    IO.puts("")

    # Show conversion from tuple to struct
    IO.puts("Converting attachment tuples to structs:")

    case Attachment.from_tuple({:attachment, pdf_data, "application/pdf"}) do
      {:ok, attachment} ->
        IO.puts("  Tuple converted successfully!")
        IO.puts("  - Content-ID: #{attachment.content_id}")
        IO.puts("  - Size: #{attachment.size} bytes")

      {:error, reason} ->
        IO.puts("  Conversion error: #{inspect(reason)}")
    end

    IO.puts("")
  end

  # ===========================================================================
  # Section 5: Handling Multiple Attachments
  # ===========================================================================

  @doc """
  Demonstrates handling multiple attachments in a single SOAP request.

  Multiple attachments can be included in various ways:
  - As separate parameters
  - In a list/array parameter
  - In nested structures
  """
  def demo_multiple_attachments do
    IO.puts("5. Handling Multiple Attachments")
    IO.puts("---------------------------------")

    # Sample data for multiple attachments
    pdf_data = "PDF content here"
    excel_data = "Excel spreadsheet content"
    image1_data = "First image data"
    image2_data = "Second image data"

    # Multiple attachments as separate parameters
    IO.puts("Pattern 1: Multiple attachments as separate parameters")
    IO.puts("")

    params_separate = %{
      "reportTitle" => "Quarterly Analysis",
      "pdfReport" => {:attachment, pdf_data, "application/pdf"},
      "spreadsheet" => {:attachment, excel_data, "application/vnd.ms-excel"},
      "chartImage" => {:attachment, image1_data, "image/png"}
    }

    case Builder.process_parameters(params_separate) do
      {:ok, {_processed, attachments}} ->
        IO.puts("  Extracted #{length(attachments)} attachments from separate parameters")

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
    end

    IO.puts("")

    # Multiple attachments in a list
    IO.puts("Pattern 2: Multiple attachments in a list/array")
    IO.puts("")

    params_list = %{
      "batchUpload" => %{
        "documents" => [
          {:attachment, pdf_data, "application/pdf"},
          {:attachment, excel_data, "application/vnd.ms-excel"}
        ],
        "images" => [
          {:attachment, image1_data, "image/jpeg"},
          {:attachment, image2_data, "image/png"}
        ]
      }
    }

    case Builder.process_parameters(params_list) do
      {:ok, {_processed, attachments}} ->
        IO.puts("  Extracted #{length(attachments)} attachments from list parameters")

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
    end

    IO.puts("")

    # Attachments in deeply nested structures
    IO.puts("Pattern 3: Attachments in nested structures")
    IO.puts("")

    params_nested = %{
      "request" => %{
        "header" => %{
          "requestId" => "req-12345",
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "body" => %{
          "document" => %{
            "title" => "Nested Document",
            "content" => {:attachment, pdf_data, "application/pdf"},
            "attachments" => %{
              "thumbnail" => {:attachment, image1_data, "image/jpeg"},
              "preview" => {:attachment, image2_data, "image/png"}
            }
          }
        }
      }
    }

    case Builder.process_parameters(params_nested) do
      {:ok, {_processed, attachments}} ->
        IO.puts("  Extracted #{length(attachments)} attachments from nested structure")
        IO.puts("")
        IO.puts("  Attachment types found:")

        Enum.each(attachments, fn att ->
          IO.puts("    - #{att.content_type} (#{att.size} bytes)")
        end)

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
    end

    IO.puts("")

    # Attachments with custom content IDs for referencing
    IO.puts("Pattern 4: Attachments with custom IDs for cross-referencing")
    IO.puts("")

    params_with_ids = %{
      "uploadMultiple" => [
        {:attachment, pdf_data, "application/pdf", [content_id: "main-document@upload"]},
        {:attachment, excel_data, "application/vnd.ms-excel", [content_id: "supporting-data@upload"]},
        {:attachment, image1_data, "image/png", [content_id: "figure-1@upload"]}
      ],
      "references" => %{
        "mainDoc" => "cid:main-document@upload",
        "dataSheet" => "cid:supporting-data@upload",
        "figures" => ["cid:figure-1@upload"]
      }
    }

    IO.puts("  Parameters include both attachments and CID references")
    IO.puts("  This allows the SOAP body to reference attachments by their content IDs")
    IO.puts("")

    case Builder.process_parameters(params_with_ids) do
      {:ok, {_processed, attachments}} ->
        IO.puts("  Extracted #{length(attachments)} attachments with custom IDs:")

        Enum.each(attachments, fn att ->
          IO.puts("    - #{att.content_id}")
        end)

      {:error, reason} ->
        IO.puts("  Error: #{inspect(reason)}")
    end

    IO.puts("")
  end

  # ===========================================================================
  # Section 6: Size Estimation and Validation
  # ===========================================================================

  @doc """
  Demonstrates size estimation and validation for MTOM messages.

  Before sending large attachments, it's useful to:
  - Estimate the total message size
  - Validate attachments meet size constraints
  - Check for potential issues before transmission
  """
  def demo_size_estimation_and_validation do
    IO.puts("6. Size Estimation and Validation")
    IO.puts("----------------------------------")

    # Create attachments of various sizes
    small_data = String.duplicate("x", 1024)
    medium_data = String.duplicate("y", 100 * 1024)
    large_data = String.duplicate("z", 1024 * 1024)

    # Size estimation for a message with multiple attachments
    IO.puts("Estimating message sizes:")
    IO.puts("")

    params_small = %{
      "document" => {:attachment, small_data, "application/pdf"}
    }

    params_medium = %{
      "document" => {:attachment, medium_data, "application/pdf"}
    }

    params_large = %{
      "document" => {:attachment, large_data, "application/pdf"}
    }

    params_multiple = %{
      "doc1" => {:attachment, small_data, "application/pdf"},
      "doc2" => {:attachment, medium_data, "application/pdf"},
      "doc3" => {:attachment, large_data, "application/pdf"}
    }

    # Estimate sizes (with base SOAP envelope size of ~1KB)
    base_soap_size = 1024

    small_size = Builder.estimate_message_size(params_small, base_soap_size)
    medium_size = Builder.estimate_message_size(params_medium, base_soap_size)
    large_size = Builder.estimate_message_size(params_large, base_soap_size)
    multiple_size = Builder.estimate_message_size(params_multiple, base_soap_size)

    IO.puts("  Single small attachment (1 KB):   ~#{format_bytes(small_size)}")
    IO.puts("  Single medium attachment (100 KB): ~#{format_bytes(medium_size)}")
    IO.puts("  Single large attachment (1 MB):   ~#{format_bytes(large_size)}")
    IO.puts("  Multiple attachments combined:    ~#{format_bytes(multiple_size)}")
    IO.puts("")

    # Validation examples
    IO.puts("Validating attachments:")
    IO.puts("")

    # Valid attachment
    valid_attachment = Attachment.new(small_data, "application/pdf")

    case Attachment.validate(valid_attachment) do
      :ok ->
        IO.puts("  Valid PDF attachment: OK")

      {:error, reason} ->
        IO.puts("  Valid PDF attachment: Error - #{inspect(reason)}")
    end

    # Validation of attachment parameters in bulk
    IO.puts("")
    IO.puts("Validating all attachments in parameters:")

    params_to_validate = %{
      "file1" => {:attachment, small_data, "application/pdf"},
      "file2" => {:attachment, medium_data, "image/jpeg"},
      "nested" => %{
        "file3" => {:attachment, small_data, "application/xml"}
      }
    }

    case Builder.validate_attachments(params_to_validate) do
      :ok ->
        IO.puts("  All attachments valid!")

      {:error, reason} ->
        IO.puts("  Validation error: #{inspect(reason)}")
    end

    IO.puts("")

    # Check for attachments in parameters
    IO.puts("Detecting attachments in parameters:")
    IO.puts("")

    test_params = [
      {%{"name" => "test"}, "No attachments"},
      {%{"file" => {:attachment, "data", "text/plain"}}, "Has attachment"},
      {%{"items" => [1, 2, {:attachment, "data", "text/plain"}]}, "Attachment in list"},
      {%{"nested" => %{"deep" => {:attachment, "data", "text/plain"}}}, "Nested attachment"}
    ]

    Enum.each(test_params, fn {params, description} ->
      has_att = Builder.has_attachments?(params)
      IO.puts("  #{description}: #{has_att}")
    end)

    IO.puts("")

    # Show default and configurable limits
    IO.puts("Size limits and configuration:")
    IO.puts("")
    IO.puts("  Default max attachment size: 100 MB")
    IO.puts("  Configure via: Application.put_env(:lather, :max_attachment_size, bytes)")
    IO.puts("")
    IO.puts("  Supported transfer encodings: binary, base64, quoted-printable")
    IO.puts("")
  end

  # ===========================================================================
  # Simulated Service Call (for demonstration)
  # ===========================================================================

  @doc """
  Example of a complete document upload workflow.

  This shows how all the pieces fit together in a real application.
  """
  def example_document_upload do
    IO.puts("Complete Document Upload Example")
    IO.puts("================================")
    IO.puts("")

    # In a real application, you would:
    # 1. Connect to the service
    case connect_to_document_service() do
      {:ok, client} ->
        # 2. Prepare your document
        case prepare_document("report.pdf") do
          {:ok, pdf_data} ->
            # 3. Build parameters with attachment
            params = build_upload_params("Monthly Report", pdf_data)

            # 4. Validate before sending
            case validate_upload(params) do
              :ok ->
                # 5. Send the request
                send_upload_request(client, params)

              {:error, reason} ->
                IO.puts("Validation failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("Failed to prepare document: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("Failed to connect: #{inspect(reason)}")
    end
  end

  # Helper functions for the example workflow

  defp connect_to_document_service do
    IO.puts("Connecting to document service...")
    IO.puts("  (Simulated - would use Lather.DynamicClient.new(\"#{@document_service_wsdl}\"))")

    # Simulated successful connection
    {:ok, :simulated_client}
  end

  defp prepare_document(filename) do
    IO.puts("Reading document: #{filename}")
    IO.puts("  (Simulated - would use File.read or Attachment.from_file)")

    # Simulated document content
    {:ok, "Simulated PDF content for #{filename}"}
  end

  defp build_upload_params(title, pdf_data) do
    IO.puts("Building upload parameters...")

    %{
      "documentInfo" => %{
        "title" => title,
        "author" => System.get_env("USER") || "Unknown",
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      },
      "documentContent" => {:attachment, pdf_data, "application/pdf"},
      "options" => %{
        "overwriteExisting" => false,
        "notifyOnComplete" => true
      }
    }
  end

  defp validate_upload(params) do
    IO.puts("Validating upload parameters...")

    # Estimate size
    estimated_size = Builder.estimate_message_size(params)
    IO.puts("  Estimated message size: #{format_bytes(estimated_size)}")

    # Validate attachments
    case Builder.validate_attachments(params) do
      :ok ->
        IO.puts("  Attachments validated successfully")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_upload_request(_client, params) do
    IO.puts("Sending upload request...")

    # In a real application:
    # Lather.DynamicClient.call(client, "UploadDocument", params)

    # Check for attachments and report
    if Builder.has_attachments?(params) do
      IO.puts("  Request will use MTOM encoding for binary attachments")
    end

    IO.puts("  (Simulated - would send actual SOAP request)")
    IO.puts("")
    IO.puts("Upload completed successfully!")
  end

  # Utility function for formatting byte sizes
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
end

# Run the example
if __name__ == :main do
  MtomClientExample.run()
end
