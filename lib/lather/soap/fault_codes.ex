defmodule Lather.Soap.FaultCodes do
  @moduledoc """
  SOAP 1.2 fault code taxonomy per the spec (section 5.2).

  Top-level codes are `soap:Sender`, `soap:Receiver` and
  `soap:Extension`; each has a set of spec-defined subcodes.

  ## Examples

      iex> Lather.Soap.FaultCodes.subcodes("Sender")
      ["BadRequest", "MalformedMessage", "DeliveryFailure"]

  """

  @sender_subcodes ["BadRequest", "MalformedMessage", "DeliveryFailure"]
  @receiver_subcodes ["TemporaryFailure", "Unavailable"]
  @extension_namespace "http://www.w3.org/2003/05/soap-envelope"

  @doc """
  Returns the spec-defined subcodes for a top-level fault code.
  """
  @spec subcodes(String.t()) :: [String.t()]
  def subcodes("Sender"), do: @sender_subcodes
  def subcodes("Receiver"), do: @receiver_subcodes
  def subcodes(_other), do: []

  @doc """
  Builds a fault map with a top-level code and subcode.

      iex> Lather.Soap.FaultCodes.fault("Sender", "BadRequest", "invalid parameter")
      ...> |> Map.get(:fault_code)
      "Sender"

  """
  @spec fault(String.t(), String.t() | nil, String.t(), term()) :: map()
  def fault(code, subcode, fault_string, detail \\ nil) do
    base = %{fault_code: code, fault_string: fault_string, detail: detail}

    if subcode, do: Map.put(base, :subcode, subcode), else: base
  end

  @doc """
  Convenience faults for common SOAP 1.2 conditions.
  """
  def bad_request(message), do: fault("Sender", "BadRequest", message)
  def malformed_message(message), do: fault("Sender", "MalformedMessage", message)
  def delivery_failure(message), do: fault("Sender", "DeliveryFailure", message)
  def temporary_failure(message), do: fault("Receiver", "TemporaryFailure", message)
  def unavailable(message), do: fault("Receiver", "Unavailable", message)

  @doc """
  The SOAP envelope namespace used for fault QNames.
  """
  def extension_namespace, do: @extension_namespace
end
