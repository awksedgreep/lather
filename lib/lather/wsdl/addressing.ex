defmodule Lather.Wsdl.Addressing do
  @moduledoc """
  WS-Addressing support for routing SOAP messages.

  Provides message-id generation, extraction of addressing headers from
  parsed SOAP requests, and a simple router that maps `wsa:Action` values
  to operation names.

  ## Examples

      iex> Lather.Wsdl.Addressing.generate_message_id() |> String.contains?("-")
      true

  """

  alias Lather.Soap.Elements

  @addressing_namespace "http://www.w3.org/2005/08/addressing"

  @doc """
  Generates a UUID-style WS-Addressing MessageID.
  """
  @spec generate_message_id() :: String.t()
  def generate_message_id do
    bytes = :crypto.strong_rand_bytes(16)
    hex = Base.encode16(bytes, case: :lower)

    [a, b, c, d, e] = [
      String.slice(hex, 0, 8),
      String.slice(hex, 8, 4),
      String.slice(hex, 12, 4),
      String.slice(hex, 16, 4),
      String.slice(hex, 20, 12)
    ]

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  @doc """
  Extracts WS-Addressing header values from a parsed request's headers.

  Returns `%{to:, from:, action:, message_id:}` (nil for absent headers).
  """
  @spec extract(list()) :: map()
  def extract(headers) when is_list(headers) do
    found = %{to: nil, from: nil, action: nil, message_id: nil}

    Enum.reduce(headers, found, fn pair, acc ->
      {name, value} = pair
      local = Elements.local_name(to_string(name))

      cond do
        local == "To" -> Map.put(acc, :to, value)
        local == "From" -> Map.put(acc, :from, value)
        local == "Action" -> Map.put(acc, :action, value)
        local == "MessageID" -> Map.put(acc, :message_id, value)
        true -> acc
      end
    end)
  end

  @doc """
  Returns `:ok` if the request carries `wsa:To` and `wsa:Action`,
  otherwise an error suitable for EnhancedPlug's fault pipeline.
  """
  @spec validate(list()) :: :ok | {:error, term()}
  def validate(headers) do
    addressing = extract(headers)

    if addressing[:to] && addressing[:action] do
      :ok
    else
      {:error,
       {:soap_fault,
        %{
          fault_code: "Client",
          fault_string: "WS-Addressing headers (To and Action) are required"
        }}}
    end
  end

  @doc """
  Resolves an operation name from the WS-Addressing Action header, using
  a service's operation list as the mapping.
  """
  @spec resolve_operation(list(), [map()]) :: {:ok, String.t()} | {:error, :unknown_action}
  def resolve_operation(headers, operations) do
    action = extract(headers)[:action]

    match =
      Enum.find(operations, fn op ->
        op_name = Map.get(op, :name) || Map.get(op, "name")
        action == op_name
      end)

    if match do
      {:ok, Map.get(match, :name) || Map.get(match, "name")}
    else
      {:error, :unknown_action}
    end
  end

  @doc """
  The WS-Addressing namespace URI.
  """
  def namespace, do: @addressing_namespace
end
