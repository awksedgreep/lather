defmodule Lather.Server.ResponseBuilder do
  @moduledoc """
  Builds SOAP response XML from operation results.
  """

  alias Lather.Xml.Builder

  @doc """
  Builds a SOAP response envelope containing the operation result.
  """
  def build_response(result, operation) do
    response_body = build_response_body(result, operation)

    envelope = %{
      "soap:Envelope" => %{
        "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
        "soap:Body" => response_body
      }
    }

    case Builder.build_fragment(envelope) do
      {:ok, xml} -> "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <> xml
      {:error, _reason} -> build_error_response("Failed to build response XML")
    end
  end

  @doc """
  Builds a SOAP fault response.
  """
  def build_fault(nil) do
    build_fault(%{fault_code: "Server", fault_string: "Internal error"})
  end

  def build_fault(fault) when is_map(fault) do
    fault_code = Map.get(fault, :fault_code) || Map.get(fault, "fault_code", "Server")

    fault_string =
      Map.get(fault, :fault_string) || Map.get(fault, "fault_string", "Internal error")

    fault_body = %{
      "soap:Fault" => %{
        "faultcode" => fault_code,
        "faultstring" => fault_string
      }
    }

    detail = Map.get(fault, :detail) || Map.get(fault, "detail")

    fault_body =
      if detail && detail != %{} do
        put_in(fault_body["soap:Fault"]["detail"], detail)
      else
        fault_body
      end

    envelope = %{
      "soap:Envelope" => %{
        "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
        "soap:Body" => fault_body
      }
    }

    case Builder.build_fragment(envelope) do
      {:ok, xml} -> "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <> xml
      {:error, _reason} -> build_error_response("Failed to build fault XML")
    end
  end

  # Build a simple error response when XML building fails
  defp build_error_response(message) do
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

  # Format response data for XML serialization
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
  defp format_response_data(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_response_data(data), do: inspect(data)
end
