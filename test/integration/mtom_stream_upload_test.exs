defmodule Lather.MtomStreamUploadTest do
  use ExUnit.Case, async: false

  alias Lather.Mtom.StreamUploader
  alias Lather.Mtom.{Mime, Builder}
  alias Lather.TestUtils

  defmodule UploadReceiver do
    @moduledoc false
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    post "/upload" do
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 20_000_000)
      content_type = Plug.Conn.get_req_header(conn, "content-type") |> List.first()

      case Mime.parse_multipart_message(content_type, body) do
        {:ok, {_soap, parts}} ->
          sizes = Enum.map(parts, &byte_size(&1.content))

          hashes =
            Enum.map(parts, &Base.encode16(:crypto.hash(:sha256, &1.content), case: :lower))

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{"ok" => true, "sizes" => sizes, "hashes" => hashes})
          )

        {:error, reason} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(400, Jason.encode!(%{"ok" => false, "error" => inspect(reason)}))
      end
    end
  end

  setup do
    {:ok, _pid, port} = TestUtils.start_server({UploadReceiver, []}, 0)

    path =
      Path.join(
        System.tmp_dir!(),
        "mtom_upload_#{:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)}.bin"
      )

    data = :crypto.strong_rand_bytes(1_000_000)
    File.write(path, data)

    on_exit(fn -> File.rm(path) end)

    {:ok, endpoint: "http://127.0.0.1:#{port}/upload", path: path, data: data}
  end

  test "streams a 1MB file attachment to an HTTP endpoint", %{
    endpoint: endpoint,
    path: path,
    data: data
  } do
    {:ok, response} =
      StreamUploader.upload(endpoint, "Upload", %{
        "file" => {:attachment, {:file, path}, "application/octet-stream"}
      })

    assert response.status == 200

    %{"ok" => true, "sizes" => [size], "hashes" => [hash]} = Jason.decode!(response.body)
    assert size == 1_000_000
    assert hash == :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  test "in-memory attachment uploads also work", %{endpoint: endpoint, data: data} do
    {:ok, response} =
      StreamUploader.upload(endpoint, "Upload", %{
        "file" => {:attachment, data, "application/octet-stream"}
      })

    assert response.status == 200
    %{"ok" => true, "sizes" => [size]} = Jason.decode!(response.body)
    assert size == byte_size(data)
  end

  test "builder chunk path is used for large attachments", %{endpoint: _endpoint, path: path} do
    {:ok, {content_type, chunks}} =
      Builder.build_message_chunks("Upload", %{
        "file" => {:attachment, {:file, path}, "application/octet-stream"}
      })

    assert String.contains?(content_type, "multipart/related")
    total = chunks |> Enum.map(&byte_size/1) |> Enum.sum()
    assert total >= 1_000_000
  end
end
