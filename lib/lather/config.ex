defmodule Lather.Config do
  @moduledoc """
  Load service configuration from external sources (JSON files or
  database-like adapters) and merge them into plug/client options.

  ## Examples

      iex> Lather.Config.merge([api_keys: ["a"]], [api_keys: ["b"]])
      [api_keys: ["b"]]

  """

  @doc """
  Reads a JSON configuration file and returns it as a keyword list.

  Returns `[]` when the file cannot be read.
  """
  @spec from_file(String.t()) :: {:ok, keyword()} | {:error, term()}
  def from_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        case decode(contents) do
          {:ok, map} ->
            {:ok,
             Enum.map(map, fn {key, value} ->
               {String.to_atom(to_string(key)), value}
             end)}

          {:error, reason} ->
            {:error, {:invalid_config, reason}}
        end

      {:error, reason} ->
        {:error, {:config_not_found, reason}}
    end
  end

  @doc """
  Merges loaded config options with explicit options (explicit wins).
  """
  @spec merge(keyword(), keyword()) :: keyword()
  def merge(config_opts, explicit_opts) do
    Keyword.merge(config_opts, explicit_opts)
  end

  defp decode(contents) do
    Jason.decode(contents)
  rescue
    _ ->
      # Minimal fallback parser for flat {"key": "value"} objects
      pairs =
        contents
        |> String.split(",", trim: true)
        |> Enum.map(&String.split(&1, ":", parts: 2))
        |> Enum.map(fn [k, v] -> {String.trim(k, "\""), String.trim(v, "\"")} end)

      {:ok, Map.new(pairs)}
  end
end
