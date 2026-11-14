defmodule Lather.Mtom.StreamUploader do
  @moduledoc """
  Upload large MTOM attachments as streamed multipart messages.

  Builds the multipart message lazily (see `Lather.Mtom.Builder.build_message_chunks/3`)
  and posts it with a streaming request body, so a multi-megabyte attachment
  is never fully materialized in memory.

  ## Examples

      {:ok, response} =
        Lather.Mtom.StreamUploader.upload(
          "http://localhost:4000/upload",
          "Upload",
          %{"file" => {:attachment, {:file, "huge.pdf"}, "application/pdf"}}
        )

  """

  alias Lather.Http.Transport
  alias Lather.Mtom.Builder

  @doc """
  Streams an MTOM message to `endpoint`.

  Attachment sources may be binaries, `{:file, path}` tuples, or enumerables
  of binary chunks. Options are forwarded to the builder (`:boundary`,
  `:chunk_size`) and to the HTTP transport (`:timeout`, `:headers`).
  """
  @spec upload(String.t(), any(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def upload(endpoint, operation, parameters, options \\ []) do
    with {:ok, {content_type, chunks}} <-
           Builder.build_message_chunks(operation, parameters, options) do
      Transport.post_stream(endpoint, content_type, chunks, options)
    end
  end
end
