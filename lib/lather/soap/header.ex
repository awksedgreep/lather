defmodule Lather.Soap.Header do
  @moduledoc """
  SOAP header utilities.

  Provides functionality for creating and managing SOAP headers,
  including authentication headers and custom header elements.
  """

  alias Lather.Auth.WSSecurity

  @doc """
  Creates a WS-Security UsernameToken header.

  ## Parameters

  * `username` - Username for authentication
  * `password` - Password for authentication
  * `options` - Header options

  ## Options

  * `:password_type` - `:text` or `:digest` (default: `:text`)
  * `:include_nonce` - Whether to include a nonce (default: `true` for digest)
  * `:include_created` - Whether to include timestamp (default: `true`)

  ## Examples

      iex> Header.username_token("user", "pass")
      %{
        "wsse:Security" => %{
          "@xmlns:wsse" => "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
          "wsse:UsernameToken" => %{...}
        }
      }

  """
  @spec username_token(String.t(), String.t(), keyword()) :: map()
  def username_token(username, password, options \\ []) do
    WSSecurity.username_token(username, password, options)
  end

  @doc """
  Creates a WS-Security timestamp header.

  ## Parameters

  * `options` - Options for the timestamp
    * `:ttl` - Time to live in seconds (default: 300)

  ## Examples

      iex> Header.timestamp()
      %{
        "wsse:Security" => %{
          "wsu:Timestamp" => %{...}
        }
      }

  """
  @spec timestamp(keyword()) :: map()
  def timestamp(options \\ []) do
    WSSecurity.timestamp(options)
  end

  @doc """
  Creates a combined WS-Security header with both UsernameToken and Timestamp.

  ## Parameters

  * `username` - Username for authentication
  * `password` - Password for authentication
  * `options` - Combined options for both UsernameToken and Timestamp

  ## Examples

      iex> Header.username_token_with_timestamp("user", "pass")
      %{
        "wsse:Security" => %{
          "wsse:UsernameToken" => %{...},
          "wsu:Timestamp" => %{...}
        }
      }

  """
  @spec username_token_with_timestamp(String.t(), String.t(), keyword()) :: map()
  def username_token_with_timestamp(username, password, options \\ []) do
    WSSecurity.username_token_with_timestamp(username, password, options)
  end

  @doc """
  Creates a session header for maintaining session state.

  ## Parameters

  * `session_id` - The session ID
  * `options` - Additional options
    * `:header_name` - Custom header name (default: "SessionId")
    * `:namespace` - Custom namespace

  ## Examples

      iex> Header.session("session_12345")
      %{"SessionId" => "session_12345"}

  """
  @spec session(String.t(), keyword()) :: map()
  def session(session_id, options \\ []) do
    header_name = Keyword.get(options, :header_name, "SessionId")
    namespace = Keyword.get(options, :namespace)

    if namespace do
      %{header_name => %{"@xmlns" => namespace, "#text" => session_id}}
    else
      %{header_name => session_id}
    end
  end

  @doc """
  Creates a custom header element.

  ## Parameters

  * `name` - Header element name
  * `content` - Header content (map or string)
  * `attributes` - Element attributes

  ## Examples

      iex> Header.custom("MyHeader", %{"value" => "test"}, %{"xmlns" => "http://example.com"})
      %{"MyHeader" => %{"@xmlns" => "http://example.com", "value" => "test"}}

  """
  @spec custom(String.t(), map() | String.t(), map()) :: map()
  def custom(name, content, attributes \\ %{}) do
    element_content = case content do
      content when is_map(content) ->
        content

      content when is_binary(content) ->
        %{"#text" => content}

      content ->
        %{"#text" => to_string(content)}
    end

    element_with_attrs = attributes
    |> Enum.reduce(element_content, fn {key, value}, acc ->
      attr_key = if String.starts_with?(key, "@"), do: key, else: "@#{key}"
      Map.put(acc, attr_key, value)
    end)

    %{name => element_with_attrs}
  end

  @doc """
  Merges multiple header elements into a single header map.

  ## Parameters

  * `headers` - List of header maps to merge

  ## Examples

      iex> header1 = Header.session("session_123")
      iex> header2 = Header.custom("MyApp", "v1.0")
      iex> Header.merge_headers([header1, header2])
      %{"SessionId" => "session_123", "MyApp" => "v1.0"}

  """
  @spec merge_headers([map()]) :: map()
  def merge_headers(headers) when is_list(headers) do
    Enum.reduce(headers, %{}, &deep_merge/2)
  end

  # Private helper functions

  defp deep_merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  defp deep_resolve(_key, left, right) when is_map(left) and is_map(right) do
    deep_merge(left, right)
  end

  defp deep_resolve(_key, _left, right) do
    right
  end
end
