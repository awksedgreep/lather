defmodule Lather.Auth.APIKey do
  @moduledoc """
  API key authentication for SOAP and JSON endpoints.

  Clients send the key in the `X-API-Key` header. Servers validate against a
  configured list of keys (or a map of key -> metadata, e.g.
  `%{"key-1" => [operations: ["Echo"]]}`).

  ## Examples

      iex> Lather.Auth.APIKey.header("abc")
      [{"x-api-key", "abc"}]

      iex> Lather.Auth.APIKey.valid?(["abc"], "abc")
      true

  """

  @doc """
  Builds the request header carrying an API key.
  """
  @spec header(String.t()) :: [{String.t(), String.t()}]
  def header(key) when is_binary(key) do
    [{"x-api-key", key}]
  end

  @doc """
  Checks a key against the configured API keys.

  `keys` may be a list of strings or a map of key -> metadata.
  """
  @spec valid?(list() | map(), String.t() | nil) :: boolean()
  def valid?(_keys, nil), do: false
  def valid?(_keys, ""), do: false

  def valid?(keys, key) when is_binary(key) do
    cond do
      is_map(keys) -> Map.has_key?(keys, key)
      is_list(keys) -> Enum.member?(keys, key)
      true -> false
    end
  end

  @doc """
  Extracts the API key from request headers.
  """
  @spec extract(list()) :: String.t() | nil
  def extract(headers) when is_list(headers) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(to_string(name)) == "x-api-key", do: value
    end)
  end

  @doc """
  Returns per-key metadata (scopes/allowed operations), or `nil` if absent.
  """
  @spec metadata(map() | list(), String.t()) :: map() | list() | nil
  def metadata(keys, key) when is_map(keys), do: Map.get(keys, key)
  def metadata(_keys, _key), do: nil
end
