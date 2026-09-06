defmodule Lather.Soap.Elements do
  @moduledoc """
  Prefix-agnostic access to parsed SOAP documents.

  `Lather.Xml.Parser` keeps namespace prefixes in element names, so the
  same envelope can arrive as `"soap:Envelope"`, `"soapenv:Envelope"`,
  `"SOAP-ENV:Envelope"`, `"s:Envelope"` or plain `"Envelope"` depending on
  the peer. The functions here look elements up by *local name* so callers
  do not have to enumerate prefixes.
  """

  @soap_1_1_namespace "http://schemas.xmlsoap.org/soap/envelope/"
  @soap_1_2_namespace "http://www.w3.org/2003/05/soap-envelope"

  @doc "SOAP 1.1 envelope namespace URI."
  def soap_1_1_namespace, do: @soap_1_1_namespace

  @doc "SOAP 1.2 envelope namespace URI."
  def soap_1_2_namespace, do: @soap_1_2_namespace

  @doc """
  Returns the local part of a possibly prefixed element name.

      iex> Lather.Soap.Elements.local_name("soapenv:Body")
      "Body"
      iex> Lather.Soap.Elements.local_name("Body")
      "Body"
  """
  @spec local_name(String.t() | atom()) :: String.t()
  def local_name(name) do
    name = to_string(name)

    case :binary.match(name, ":") do
      {pos, 1} -> binary_part(name, pos + 1, byte_size(name) - pos - 1)
      :nomatch -> name
    end
  end

  @doc """
  Returns the prefix of an element name, or `nil` when it has none.
  """
  @spec prefix(String.t() | atom()) :: String.t() | nil
  def prefix(name) do
    name = to_string(name)

    case :binary.match(name, ":") do
      {pos, 1} -> binary_part(name, 0, pos)
      :nomatch -> nil
    end
  end

  @doc """
  Finds the child of `map` whose local name is `local`.

  Returns `{key, value}` with the *actual* (possibly prefixed) key, or
  `nil` when there is no such child or `map` is not a map. An exact key
  match wins over a prefixed one; attribute keys (`@...`) and `#text` are
  never matched.
  """
  @spec find(any(), String.t()) :: {String.t(), any()} | nil
  def find(map, local) when is_map(map) do
    case Map.fetch(map, local) do
      {:ok, value} ->
        {local, value}

      :error ->
        Enum.find(map, fn {key, _} ->
          key = to_string(key)
          not String.starts_with?(key, "@") and local_name(key) == local
        end)
    end
  end

  def find(_, _), do: nil

  @doc """
  Returns the value of the child of `map` with local name `local`, or
  `nil`.
  """
  @spec get(any(), String.t()) :: any()
  def get(map, local) do
    case find(map, local) do
      {_key, value} -> value
      nil -> nil
    end
  end

  @doc """
  Walks a path of local names, like `get_in/2` but prefix-agnostic and
  safe against non-map intermediate values.

      Elements.get_in(parsed, ["Envelope", "Body", "Fault"])
  """
  @spec get_in(any(), [String.t()]) :: any()
  def get_in(value, []), do: value

  def get_in(map, [local | rest]) do
    case find(map, local) do
      {_key, value} -> __MODULE__.get_in(value, rest)
      nil -> nil
    end
  end

  @doc """
  Returns the namespace URI declared for `element_key`'s prefix on
  `element` (a parsed element map), or `nil`.

  Looks for `@xmlns:prefix` when the key is prefixed and `@xmlns` when it
  is not.
  """
  @spec namespace_of(String.t(), any()) :: String.t() | nil
  def namespace_of(element_key, element) when is_map(element) do
    case prefix(element_key) do
      nil -> Map.get(element, "@xmlns")
      pfx -> Map.get(element, "@xmlns:#{pfx}")
    end
  end

  def namespace_of(_, _), do: nil

  @doc """
  Detects the SOAP version of a parsed document from the namespace bound
  to the Envelope element. Falls back to the fault structure (SOAP 1.2
  faults carry `Code/Value`) and finally to `:v1_1`.
  """
  @spec soap_version(map()) :: :v1_1 | :v1_2
  def soap_version(parsed) when is_map(parsed) do
    case find(parsed, "Envelope") do
      {key, envelope} ->
        cond do
          namespace_of(key, envelope) == @soap_1_2_namespace -> :v1_2
          namespace_of(key, envelope) == @soap_1_1_namespace -> :v1_1
          soap_1_2_fault?(envelope) -> :v1_2
          true -> :v1_1
        end

      nil ->
        :v1_1
    end
  end

  def soap_version(_), do: :v1_1

  defp soap_1_2_fault?(envelope) do
    __MODULE__.get_in(envelope, ["Body", "Fault", "Code", "Value"]) != nil
  end
end
