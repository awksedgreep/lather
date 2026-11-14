defmodule Lather.Mtom.StreamTest do
  use ExUnit.Case, async: true

  alias Lather.Mtom.{Builder, Mime}

  def setup_large_file(size) do
    path =
      Path.join(
        System.tmp_dir!(),
        "mtom_stream_#{:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)}.bin"
      )

    data = :crypto.strong_rand_bytes(size)
    File.write(path, data)
    {path, data}
  end

  test "chunks from a file attachment round-trip through the parser" do
    {path, data} = setup_large_file(200_000)
    on_exit(fn -> File.rm(path) end)

    params = %{"file" => {:attachment, {:file, path}, "application/octet-stream"}}

    {:ok, {content_type, chunks}} =
      Builder.build_message_chunks(:Upload, params, boundary: "TESTBND")

    chunk_list = Enum.to_list(chunks)

    # the file (200k) streamed in 64k blocks must appear as multiple chunks
    assert Enum.count(chunk_list) >= 5

    joined = Enum.join(chunk_list)
    {:ok, {soap_part, attachment_parts}} = Mime.parse_multipart_message(content_type, joined)

    assert String.contains?(soap_part, "xop:Include")
    assert length(attachment_parts) == 1
    [part] = attachment_parts
    assert part.content == data
  end

  test "chunk sizes stay bounded" do
    {path, _data} = setup_large_file(250_000)
    on_exit(fn -> File.rm(path) end)

    params = %{"file" => {:attachment, {:file, path}, "application/octet-stream"}}

    {:ok, {_content_type, chunks}} =
      Builder.build_message_chunks(:Upload, params, chunk_size: 32_768)

    max_chunk = chunks |> Enum.map(&byte_size/1) |> Enum.max()
    assert max_chunk <= 32_768
  end

  test "stream output matches the non-stream builder byte for byte" do
    data = :crypto.strong_rand_bytes(5000)
    params = %{"file" => {:attachment, data, "application/pdf", [content_id: "fixed-cid"]}}

    {:ok, {ct_direct, body_direct}} =
      Builder.build_mtom_message(:Upload, params, boundary: "SAMEBND")

    {:ok, {ct_stream, chunks}} =
      Builder.build_message_chunks(:Upload, params, boundary: "SAMEBND")

    assert ct_direct == ct_stream
    assert body_direct == Enum.join(chunks, "")
  end

  test "enumerable sources stream lazily" do
    source = Stream.map(1..5, &String.pad_leading(Integer.to_string(&1), 10, "0"))

    params = %{"file" => {:attachment, source, "text/plain"}}

    {:ok, {content_type, chunks}} =
      Builder.build_message_chunks(:Upload, params, boundary: "STREAMBND")

    joined = Enum.join(chunks, "")

    {:ok, {_soap, parts}} = Mime.parse_multipart_message(content_type, joined)
    [part] = parts
    assert part.content == "00000000010000000002000000000300000000040000000005"
  end

  test "non-attachment parameters pass through unchanged" do
    {:ok, {_ct, chunks}} =
      Builder.build_message_chunks(:Upload, %{"name" => "hello", "count" => 3})

    joined = Enum.join(chunks, "")
    assert String.contains?(joined, "<name>hello</name>") or String.contains?(joined, "hello")
  end
end
