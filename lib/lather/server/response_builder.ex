defmodule Lather.Server.ResponseBuilder do
  @moduledoc """
  Builds SOAP response XML from operation results.

  Responses and faults can be rendered for SOAP 1.1 (default) or SOAP 1.2
  via the `:soap_version` option; SOAP 1.2 uses the
  `http://www.w3.org/2003/05/soap-envelope` namespace and the
  `Code/Value` + `Reason/Text` fault structure.
  """

  alias Lather.Soap.Elements
  alias Lather.Xml.Builder

  @type soap_version :: :v1_1 | :v1_2

  @doc """
  The MIME type for a response of the given SOAP version
  (`text/xml` for 1.1, `application/soap+xml` for 1.2).
  """
  @spec content_type(soap_version()) :: String.t()
  def content_type(:v1_2), do: "application/soap+xml"
  def content_type(_), do: "text/xml"

  @doc """
  Builds a SOAP response envelope containing the operation result.

  ## Options

  * `:soap_version` - `:v1_1` (default) or `:v1_2`
  """
  def build_response(result, operation, opts \\ []) do
    version = Keyword.get(opts, :soap_version, :v1_1)
    response_body = build_response_body(result, operation)

    case Builder.build_fragment(envelope(response_body, version)) do
      {:ok, xml} -> "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <> xml
      {:error, _reason} -> build_error_response("Failed to build response XML", version)
    end
  end

  @doc """
  Builds a SOAP fault response.

  The fault map may carry `:fault_code`, `:fault_string` and `:detail`
  (atom or string keys). For SOAP 1.2 the 1.1 codes `Client`/`Server` are
  mapped to `soap:Sender`/`soap:Receiver`.

  ## Options

  * `:soap_version` - `:v1_1` (default) or `:v1_2`
  """
  def build_fault(fault, opts \\ [])

  def build_fault(nil, opts) do
    build_fault(%{fault_code: "Server", fault_string: "Internal error"}, opts)
  end

  def build_fault(fault, opts) when is_map(fault) do
    version = Keyword.get(opts, :soap_version, :v1_1)
    fault_code = Map.get(fault, :fault_code) || Map.get(fault, "fault_code", "Server")

    fault_string =
      Map.get(fault, :fault_string) || Map.get(fault, "fault_string", "Internal error")

    detail = Map.get(fault, :detail) || Map.get(fault, "detail")
    detail = if detail && detail != %{}, do: format_response_data(detail), else: nil

    fault_body = %{"soap:Fault" => fault_element(version, fault_code, fault_string, detail)}

    case Builder.build_fragment(envelope(fault_body, version)) do
      {:ok, xml} -> "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <> xml
      {:error, _reason} -> build_error_response("Failed to build fault XML", version)
    end
  end

  defp envelope(body, version) do
    %{
      "soap:Envelope" => %{
        "@xmlns:soap" => namespace(version),
        "soap:Body" => body
      }
    }
  end

  defp namespace(:v1_2), do: Elements.soap_1_2_namespace()
  defp namespace(_), do: Elements.soap_1_1_namespace()

  defp fault_element(:v1_2, code, string, detail) do
    %{
      "soap:Code" => %{"soap:Value" => soap_1_2_code(code)},
      "soap:Reason" => %{"soap:Text" => %{"@xml:lang" => "en", "#text" => string}}
    }
    |> maybe_put("soap:Detail", detail)
  end

  defp fault_element(_v1_1, code, string, detail) do
    %{"faultcode" => code, "faultstring" => string}
    |> maybe_put("detail", detail)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # SOAP 1.2 fault codes are QNames in the envelope namespace.
  defp soap_1_2_code(code) do
    code = to_string(code)

    cond do
      String.contains?(code, ":") -> code
      String.starts_with?(code, "Client") -> "soap:Sender"
      String.starts_with?(code, "Server") -> "soap:Receiver"
      code in ["VersionMismatch", "MustUnderstand", "DataEncodingUnknown"] -> "soap:" <> code
      code in ["Sender", "Receiver"] -> "soap:" <> code
      true -> "soap:Receiver"
    end
  end

  # Build a simple error response when XML building fails
  defp build_error_response(message, :v1_2) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
      <soap:Body>
        <soap:Fault>
          <soap:Code><soap:Value>soap:Receiver</soap:Value></soap:Code>
          <soap:Reason><soap:Text xml:lang="en">#{message}</soap:Text></soap:Reason>
        </soap:Fault>
      </soap:Body>
    </soap:Envelope>
    """
  end

  defp build_error_response(message, _v1_1) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <soap:Fault>
          <faultcode>Server</faultcode>
          <faultstring>#{message}</faultstring>
        </soap:Fault>
      </soap:Body>
    </soap:Envelope>
    """
  end

  # Build the response body based on operation result
  defp build_response_body(result, operation) when is_map(operation) do
    operation_name = Map.get(operation, :name) || Map.get(operation, "name", "")
    response_name = "#{operation_name}Response"

    # Unwrap {:ok, data} tuples from service functions
    unwrapped_result =
      case result do
        {:ok, data} -> data
        {:error, _} = err -> err
        other -> other
      end

    case unwrapped_result do
      {:error, reason} ->
        %{response_name => %{"error" => format_response_data(reason)}}

      %{^response_name => data} ->
        %{response_name => format_response_data(data)}

      data when is_map(data) ->
        %{response_name => format_response_data(data)}

      data ->
        %{response_name => %{"result" => format_response_data(data)}}
    end
  end

  # Handle case where operation is not a map
  defp build_response_body(result, _operation) do
    %{"Response" => format_response_data(result)}
  end

  # Format response data for XML serialization.
  # Struct clauses must precede the generic `is_map` clause: structs are
  # maps, so the reverse order would make these unreachable (issue #7).
  defp format_response_data(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_response_data(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_response_data(%Date{} = date), do: Date.to_iso8601(date)
  defp format_response_data(%Time{} = time), do: Time.to_iso8601(time)

  defp format_response_data(data) when is_map(data) do
    Enum.into(data, %{}, fn {key, value} ->
      {to_string(key), format_response_data(value)}
    end)
  end

  defp format_response_data(data) when is_list(data) do
    Enum.map(data, &format_response_data/1)
  end

  defp format_response_data(data) when is_binary(data), do: data
  defp format_response_data(data) when is_number(data), do: to_string(data)
  defp format_response_data(data) when is_boolean(data), do: to_string(data)
  defp format_response_data(data), do: inspect(data)
end
