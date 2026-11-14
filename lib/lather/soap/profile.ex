defmodule Lather.Soap.Profile do
  @moduledoc """
  WS-I Basic Profile compliance checks for SOAP envelopes.

  Validates the structural rules the Basic Profile requires: a single
  Envelope, exactly one Body, a declared SOAP namespace, correctly
  ordered header/body elements, and valid `mustUnderstand` values.

  ## Examples

      iex> Lather.Soap.Profile.validate("<soap:Envelope xmlns:soap=\\"http://www.w3.org/2003/05/soap-envelope\\"><soap:Body><Echo/></soap:Body></soap:Envelope>")
      {:ok, []}
  """

  @soap_namespaces [
    "http://schemas.xmlsoap.org/ws/2003/05/soap-envelope",
    "http://www.w3.org/2003/05/soap-envelope"
  ]

  def validate(xml) when is_binary(xml) do
    problems =
      []
      |> check_envelope(xml)
      |> check_single_body(xml)
      |> check_soap_namespace(xml)
      |> check_header_before_body(xml)
      |> check_must_understand(xml)

    case problems do
      [] -> {:ok, []}
      _ -> {:error, problems}
    end
  end

  def validate(_), do: {:error, [:invalid_input]}

  defp check_envelope(problems, xml) do
    if String.contains?(xml, ":Envelope") or String.contains?(xml, "<Envelope") do
      problems
    else
      problems ++ ["missing Envelope element"]
    end
  end

  defp check_single_body(problems, xml) do
    count =
      Regex.scan(~r/<[A-Za-z0-9-]*:?Body\b/, xml)
      |> length()

    if count == 1 do
      problems
    else
      problems ++ ["exactly one Body element is required (found #{count})"]
    end
  end

  defp check_soap_namespace(problems, xml) do
    known =
      Enum.reduce(@soap_namespaces, false, fn ns, acc ->
        acc || String.contains?(xml, ns)
      end)

    if known do
      problems
    else
      problems ++ ["no SOAP 1.1 or SOAP 1.2 namespace declared"]
    end
  end

  defp check_header_before_body(problems, xml) do
    header_index = first_index(xml, ~r/<[A-Za-z0-9-]*:?Header\b/)
    body_index = first_index(xml, ~r/<[A-Za-z0-9-]*:?Body\b/)

    if header_index != nil and body_index != nil and header_index > body_index do
      problems ++ ["Header must appear before Body"]
    else
      problems
    end
  end

  defp check_must_understand(problems, xml) do
    bad =
      Regex.scan(~r/mustUnderstand="([^"]*)"/, xml)
      |> Enum.flat_map(&fault_values/1)
      |> Enum.reject(&valid_value?/1)

    if bad == [] do
      problems
    else
      problems ++ ["invalid mustUnderstand value(s): #{Enum.join(bad, ", ")}"]
    end
  end

  defp fault_values([_full, value]) do
    [value]
  end

  defp valid_value?(value) do
    value in ["true", "false", "1", "0"]
  end

  defp first_index(xml, pattern) do
    case Regex.run(pattern, xml, return: :index) do
      [{index, _length} | _] -> index
      _other -> nil
    end
  end
end
