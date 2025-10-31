defmodule Lather.Mtom.Attachment do
  @moduledoc """
  MTOM attachment data structure and utilities.

  This module defines the structure for binary attachments in MTOM messages
  and provides utilities for creating, validating, and managing attachments.

  ## Attachment Structure

  An attachment represents a binary file or data that will be transmitted
  as part of an MTOM message using XOP (XML-binary Optimized Packaging).

  ## Examples

      # Create a simple attachment
      attachment = Attachment.new(pdf_data, "application/pdf")

      # Create attachment with custom content ID
      attachment = Attachment.new(image_data, "image/jpeg", content_id: "image001")

      # Validate attachment
      :ok = Attachment.validate(attachment)

  """

  @type t :: %__MODULE__{
          id: String.t(),
          content_type: String.t(),
          content_transfer_encoding: String.t(),
          data: binary(),
          content_id: String.t(),
          size: non_neg_integer()
        }

  defstruct [
    :id,
    :content_type,
    :content_transfer_encoding,
    :data,
    :content_id,
    :size
  ]

  # Default content transfer encoding for binary data
  @default_encoding "binary"

  # Maximum attachment size (100MB by default)
  @default_max_size 100 * 1024 * 1024

  # Supported content types (can be extended) - commented out to remove unused warning
  # @supported_types [
  # Documents
  # "application/pdf",
  # "application/msword",
  # "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  # "application/vnd.ms-excel",
  # "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  # "application/vnd.ms-powerpoint",
  # "application/vnd.openxmlformats-officedocument.presentationml.presentation",

  # Images
  # "image/jpeg",
  # "image/png",
  # "image/gif",
  # "image/tiff",
  # "image/bmp",
  # "image/webp",

  # Archives
  # "application/zip",
  # "application/x-zip-compressed",
  # "application/gzip",
  # "application/x-tar",

  # Text
  # "text/plain",
  # "text/csv",
  # "text/xml",
  # "application/xml",
  # "application/json",

  # Binary
  # "application/octet-stream",

  # Media
  # "video/mp4",
  # "video/avi",
  # "audio/mp3",
  # "audio/wav"
  # ]

  @doc """
  Creates a new attachment from binary data and content type.

  ## Parameters

    * `data` - Binary data for the attachment
    * `content_type` - MIME content type (e.g., "application/pdf")
    * `options` - Additional options

  ## Options

    * `:content_id` - Custom Content-ID (auto-generated if not provided)
    * `:content_transfer_encoding` - Transfer encoding (default: "binary")
    * `:validate` - Whether to validate the attachment (default: true)

  ## Examples

      attachment = Attachment.new(pdf_data, "application/pdf")

      attachment = Attachment.new(image_data, "image/jpeg",
        content_id: "custom-id-123"
      )

  """
  @spec new(binary(), String.t(), keyword()) :: t()
  def new(data, content_type, options \\ []) when is_binary(data) and is_binary(content_type) do
    content_id = Keyword.get(options, :content_id, generate_content_id())
    encoding = Keyword.get(options, :content_transfer_encoding, @default_encoding)
    validate? = Keyword.get(options, :validate, true)

    attachment = %__MODULE__{
      id: generate_attachment_id(),
      content_type: String.trim(content_type),
      content_transfer_encoding: encoding,
      data: data,
      content_id: content_id,
      size: byte_size(data)
    }

    if validate? do
      case validate(attachment) do
        :ok -> attachment
        {:error, reason} -> raise ArgumentError, "Invalid attachment: #{inspect(reason)}"
      end
    else
      attachment
    end
  end

  @doc """
  Creates an attachment from a file path.

  ## Parameters

    * `file_path` - Path to the file
    * `options` - Additional options (same as `new/3`)

  ## Examples

      {:ok, attachment} = Attachment.from_file("document.pdf")
      {:ok, attachment} = Attachment.from_file("image.jpg", content_type: "image/jpeg")

  """
  @spec from_file(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_file(file_path, options \\ []) when is_binary(file_path) do
    with {:ok, data} <- File.read(file_path),
         content_type <- detect_content_type(file_path, options) do
      attachment = new(data, content_type, options)
      {:ok, attachment}
    else
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  @doc """
  Validates an attachment structure and content.

  ## Parameters

    * `attachment` - The attachment to validate

  ## Returns

    * `:ok` - If the attachment is valid
    * `{:error, reason}` - If the attachment is invalid

  ## Examples

      :ok = Attachment.validate(attachment)
      {:error, :data_too_large} = Attachment.validate(huge_attachment)

  """
  @spec validate(t()) :: :ok | {:error, atom()}
  def validate(%__MODULE__{} = attachment) do
    with :ok <- validate_content_type(attachment.content_type),
         :ok <- validate_size(attachment.size),
         :ok <- validate_content_id(attachment.content_id),
         :ok <- validate_encoding(attachment.content_transfer_encoding),
         :ok <- validate_data(attachment.data) do
      :ok
    end
  end

  @doc """
  Generates a Content-ID header value for the attachment.

  ## Parameters

    * `attachment` - The attachment

  ## Returns

    * Content-ID header value (e.g., "<attachment123@lather.soap>")

  ## Examples

      content_id_header = Attachment.content_id_header(attachment)
      # "<attachment123@lather.soap>"

  """
  @spec content_id_header(t()) :: String.t()
  def content_id_header(%__MODULE__{content_id: content_id}) do
    "<#{content_id}>"
  end

  @doc """
  Generates a CID (Content-ID) reference for XOP includes.

  ## Parameters

    * `attachment` - The attachment

  ## Returns

    * CID reference (e.g., "cid:attachment123@lather.soap")

  ## Examples

      cid_ref = Attachment.cid_reference(attachment)
      # "cid:attachment123@lather.soap"

  """
  @spec cid_reference(t()) :: String.t()
  def cid_reference(%__MODULE__{content_id: content_id}) do
    "cid:#{content_id}"
  end

  @doc """
  Creates an XOP Include element for the attachment.

  ## Parameters

    * `attachment` - The attachment

  ## Returns

    * Map representing XOP Include element

  ## Examples

      xop_include = Attachment.xop_include(attachment)
      # %{"xop:Include" => %{"@href" => "cid:attachment123@lather.soap", "@xmlns:xop" => "..."}}

  """
  @spec xop_include(t()) :: map()
  def xop_include(%__MODULE__{} = attachment) do
    %{
      "xop:Include" => %{
        "@href" => cid_reference(attachment),
        "@xmlns:xop" => "http://www.w3.org/2004/08/xop/include"
      }
    }
  end

  @doc """
  Checks if a parameter value represents an attachment.

  ## Parameters

    * `value` - The value to check

  ## Returns

    * `true` if the value is an attachment tuple, `false` otherwise

  ## Examples

      Attachment.is_attachment?({:attachment, data, "application/pdf"}) # true
      Attachment.is_attachment?("regular string") # false

  """
  @spec is_attachment?(any()) :: boolean()
  def is_attachment?({:attachment, data, content_type})
      when is_binary(data) and is_binary(content_type), do: true

  def is_attachment?({:attachment, _data, _content_type, options})
      when is_list(options), do: true

  def is_attachment?(%__MODULE__{}), do: true
  def is_attachment?(_), do: false

  @doc """
  Converts an attachment tuple to an Attachment struct.

  ## Parameters

    * `attachment_tuple` - Tuple in format `{:attachment, data, content_type}` or
      `{:attachment, data, content_type, options}`

  ## Returns

    * `{:ok, attachment}` - Successfully created attachment
    * `{:error, reason}` - If the tuple is invalid

  ## Examples

      {:ok, attachment} = Attachment.from_tuple({:attachment, data, "application/pdf"})
      {:ok, attachment} = Attachment.from_tuple({:attachment, data, "image/jpeg", [content_id: "img1"]})

  """
  @spec from_tuple(tuple()) :: {:ok, t()} | {:error, term()}
  def from_tuple({:attachment, data, content_type})
      when is_binary(data) and is_binary(content_type) do
    try do
      attachment = new(data, content_type)
      {:ok, attachment}
    rescue
      ArgumentError -> {:error, :invalid_attachment_data}
    end
  end

  def from_tuple({:attachment, data, content_type, options})
      when is_binary(data) and is_binary(content_type) and is_list(options) do
    try do
      attachment = new(data, content_type, options)
      {:ok, attachment}
    rescue
      ArgumentError -> {:error, :invalid_attachment_data}
    end
  end

  def from_tuple(_), do: {:error, :invalid_attachment_tuple}

  # Private functions

  defp generate_attachment_id do
    "att_" <> random_string(16)
  end

  defp generate_content_id do
    random_string(12) <> "@lather.soap"
  end

  defp random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode16(case: :lower)
    |> binary_part(0, length)
  end

  defp detect_content_type(file_path, options) do
    case Keyword.get(options, :content_type) do
      nil ->
        # Simple content type detection based on file extension
        extension = Path.extname(file_path) |> String.downcase()
        extension_to_content_type(extension)

      content_type when is_binary(content_type) ->
        content_type
    end
  end

  defp extension_to_content_type(extension) do
    case extension do
      ".pdf" -> "application/pdf"
      ".doc" -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ".xls" -> "application/vnd.ms-excel"
      ".xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      ".ppt" -> "application/vnd.ms-powerpoint"
      ".pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".tiff" -> "image/tiff"
      ".tif" -> "image/tiff"
      ".bmp" -> "image/bmp"
      ".webp" -> "image/webp"
      ".zip" -> "application/zip"
      ".rar" -> "application/x-rar-compressed"
      ".7z" -> "application/x-7z-compressed"
      ".gz" -> "application/gzip"
      ".txt" -> "text/plain"
      ".csv" -> "text/csv"
      ".json" -> "application/json"
      ".xml" -> "application/xml"
      ".mp4" -> "video/mp4"
      ".avi" -> "video/avi"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      _ -> "application/octet-stream"
    end
  end

  defp validate_content_type(content_type) when is_binary(content_type) do
    if String.contains?(content_type, "/") do
      :ok
    else
      {:error, :invalid_content_type}
    end
  end

  defp validate_content_type(_), do: {:error, :invalid_content_type}

  defp validate_size(size) when is_integer(size) and size >= 0 do
    max_size = Application.get_env(:lather, :max_attachment_size, @default_max_size)

    if size <= max_size do
      :ok
    else
      {:error, :attachment_too_large}
    end
  end

  defp validate_size(_), do: {:error, :invalid_size}

  defp validate_content_id(content_id) when is_binary(content_id) do
    if String.length(content_id) > 0 do
      :ok
    else
      {:error, :invalid_content_id}
    end
  end

  defp validate_content_id(_), do: {:error, :invalid_content_id}

  defp validate_encoding(encoding) when is_binary(encoding) do
    if encoding in ["binary", "base64", "quoted-printable"] do
      :ok
    else
      {:error, :unsupported_encoding}
    end
  end

  defp validate_encoding(_), do: {:error, :invalid_encoding}

  defp validate_data(data) when is_binary(data), do: :ok
  defp validate_data(_), do: {:error, :invalid_data}
end
