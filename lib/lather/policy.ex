defmodule Lather.Policy do
  @moduledoc """
  WS-Policy style capability negotiation.

  Services can publish a policy document (fetched from
  `GET <endpoint>?policy`) describing their capabilities and
  requirements. Clients negotiate the policy before calling operations
  and receive clear errors when their request options violate it.

  ## Supported assertions

    * `require_auth` - list of required authentication factors
      (`api_key`, `jwt`, `saml`, `signature`, `basic`)
    * `max_message_size` - maximum request body in bytes
    * `compression` - whether gzip request encoding is supported
    * `operations` - list of operation names the service exposes

  ## Examples

      iex> policy = %{"require_auth" => ["api_key"], "operations" => ["Echo"]}
      iex> xml = Lather.Policy.build_policy_xml(policy)
      iex> parsed = Lather.Policy.parse_policy(xml)
      iex> parsed["require_auth"]
      ["api_key"]

  """

  alias Lather.Xml.Parser

  @wsp_namespace "http://schemas.xmlsoap.org/ws/2004/09/policy"

  @doc """
  Builds a WS-Policy XML document from a policy map.
  """
  @spec build_policy_xml(map()) :: String.t()
  def build_policy_xml(policy) when is_map(policy) do
    assertions =
      policy
      |> Map.to_list()
      |> Enum.map(fn {name, value} ->
        "<wsp:Assertion name=\"#{name}\" value=\"#{format_value(value)}\"/>"
      end)
      |> Enum.join("\n  ")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <wsp:Policy xmlns:wsp="#{@wsp_namespace}">
      #{assertions}
    </wsp:Policy>
    """
  end

  @doc """
  Parses a WS-Policy XML document into a policy map.
  """
  @spec parse_policy(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_policy(xml) when is_binary(xml) do
    case Parser.parse(xml) do
      {:ok, parsed} ->
        policy = get_in(parsed, ["wsp:Policy", "wsp:Assertion"])

        assertions =
          cond do
            is_list(policy) ->
              Enum.reduce(policy, %{}, &assertion_into(&2, &1))

            is_map(policy) ->
              assertion_into(%{}, policy)

            true ->
              %{}
          end

        {:ok, assertions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Negotiates a service's policy over HTTP.

  Fetches `<endpoint>?policy` and returns the parsed assertions.
  """
  @spec negotiate(String.t()) :: {:ok, map()} | {:error, term()}
  def negotiate(endpoint) do
    url = endpoint <> "?policy"

    case Lather.Http.Transport.get(url) do
      {:ok, %{status: 200, body: body}} ->
        parse_policy(body)

      {:ok, %{status: status}} ->
        {:error, {:policy_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates request options against a negotiated policy.

  Returns `:ok` or `{:error, [violations]}`.
  """
  @spec validate(keyword() | map(), map()) :: :ok | {:error, [String.t()]}
  def validate(options, policy) do
    violations = []

    violations =
      violations ++ auth_violations(options, policy)

    if violations == [] do
      :ok
    else
      {:error, violations}
    end
  end

  defp assertion_into(acc, %{"@name" => name, "@value" => value}) do
    Map.put(acc, name, parse_value(value))
  end

  defp assertion_into(acc, %{"name" => name, "value" => value}) do
    Map.put(acc, name, parse_value(value))
  end

  defp assertion_into(acc, _other), do: acc

  defp auth_violations(options, policy) do
    required = normalize_auth(Map.get(policy, "require_auth", []))

    Enum.filter(required, fn factor ->
      provided =
        case Keyword.get(options, :authentication) do
          {kind, _rest} -> to_string(kind)
          _ -> nil
        end

      provided != to_string(factor)
    end)
    |> Enum.map(fn factor -> "policy requires #{factor} authentication" end)
  end

  defp normalize_auth(value) when is_list(value), do: value
  defp normalize_auth(value) when is_binary(value), do: [value]
  defp normalize_auth(_other), do: []

  defp format_value(value) when is_list(value), do: Enum.join(value, ",")
  defp format_value(value), do: to_string(value)

  defp parse_value(value) do
    cond do
      value == "true" -> true
      value == "false" -> false
      String.contains?(value, ",") -> String.split(value, ",")
      match?({_, _}, Integer.parse(value)) -> elem(Integer.parse(value), 0)
      true -> value
    end
  end
end
