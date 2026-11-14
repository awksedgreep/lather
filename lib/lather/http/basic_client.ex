defmodule Lather.Http.BasicClient do
  @moduledoc """
  Minimal stdlib HTTP/1.1 client using Erlang's `:gen_tcp`, usable as an
  alternative transport when Finch is unavailable.

  Enable per-request with `client: :basic` passed to
  `Lather.Http.Transport.get/2` or `post/3`, or globally with
  `Application.put_env(:lather, :http_client, :basic)`.

  Supports plain (non-TLS) requests and returns the same response shape
  as the Finch path: `{:ok, %{status: status, headers: headers, body: body}}`.
  """

  @doc """
  Perform an HTTP request over a plain TCP socket.

  ## Examples

      iex> is_binary("http://example.com")
      true
  """
  @spec request(
          atom(),
          String.t(),
          [{String.t(), String.t()}],
          String.t() | nil,
          non_neg_integer()
        ) ::
          {:ok, map()} | {:error, any()}
  def request(method, url, headers, body, timeout) do
    uri = URI.parse(url)
    port = uri.port || 80
    path = (uri.path || "/") <> query_part(uri)

    case :gen_tcp.connect(to_charlist(uri.host), port, [:binary, active: false], timeout) do
      {:ok, socket} ->
        payload = build_request(method, path, uri.host, headers, body)

        case :gen_tcp.send(socket, payload) do
          :ok ->
            raw = recv_all(socket, timeout)
            :gen_tcp.close(socket)
            parse_response(raw)

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, {:transport_error, to_string(reason)}}
        end

      {:error, reason} ->
        {:error, {:transport_error, to_string(reason)}}
    end
  end

  defp query_part(uri) do
    if uri.query, do: "?" <> uri.query, else: ""
  end

  defp build_request(method, path, host, headers, body) do
    body_content = body || ""

    all_headers =
      [
        {"host", host},
        {"connection", "close"},
        {"content-length", to_string(byte_size(body_content))}
      ] ++
        headers

    header_lines = for {k, v} <- all_headers, do: "#{k}: #{v}\r\n"

    method_str = method |> to_string |> String.upcase()

    "#{method_str} #{path} HTTP/1.1\r\n#{header_lines |> Enum.join("")}\r\n#{body_content}"
  end

  defp recv_all(socket, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, chunk} -> chunk <> recv_all(socket, timeout)
      {:error, :closed} -> ""
      {:error, _reason} -> ""
    end
  end

  defp parse_response("") do
    {:error, {:transport_error, "empty response"}}
  end

  defp parse_response(raw) do
    case String.split(raw, "\r\n\r\n", parts: 2) do
      [head, body] ->
        [status_line | header_lines] = String.split(head, "\r\n")

        [_method, status, _version] = String.split(status_line, " ", parts: 3)

        headers =
          for line <- header_lines do
            [key, value] = String.split(line, ":", parts: 2)
            {String.trim(key), String.trim(value)}
          end

        {:ok, %{status: String.to_integer(status), headers: headers, body: body}}

      _other ->
        {:error, {:transport_error, "malformed response"}}
    end
  end
end
