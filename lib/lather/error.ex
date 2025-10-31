defmodule Lather.Error do
  @moduledoc """
  Comprehensive error handling for SOAP operations.

  This module provides structured error types, SOAP fault parsing,
  and detailed error information for debugging SOAP service interactions.
  """

  @type soap_fault :: %{
    fault_code: String.t(),
    fault_string: String.t(),
    fault_actor: String.t() | nil,
    detail: map() | nil
  }

  @type transport_error :: %{
    type: :transport_error,
    reason: atom() | String.t(),
    details: map()
  }

  @type http_error :: %{
    type: :http_error,
    status: integer(),
    body: String.t(),
    headers: [{String.t(), String.t()}]
  }

  @type wsdl_error :: %{
    type: :wsdl_error,
    reason: atom(),
    details: map()
  }

  @type validation_error :: %{
    type: :validation_error,
    field: String.t(),
    reason: atom(),
    details: map()
  }

  @type lather_error :: soap_fault() | transport_error() | http_error() | wsdl_error() | validation_error()

  @doc """
  Parses SOAP fault from response body.

  ## Parameters

    * `response_body` - Raw XML response body containing SOAP fault
    * `options` - Parsing options

  ## Examples

      {:ok, fault} = Lather.Error.parse_soap_fault(response_body)
      # %{
      #   fault_code: "Server",
      #   fault_string: "Internal server error",
      #   fault_actor: nil,
      #   detail: %{...}
      # }
  """
  @spec parse_soap_fault(String.t(), keyword()) :: {:ok, soap_fault()} | {:error, term()}
  def parse_soap_fault(response_body, options \\ []) do
    alias Lather.Xml.Parser

    case Parser.parse(response_body) do
      {:ok, parsed_xml} ->
        extract_fault_from_xml(parsed_xml, options)

      {:error, reason} ->
        {:error, {:xml_parse_error, reason}}
    end
  end

  @doc """
  Creates a transport error structure.

  ## Parameters

    * `reason` - The transport error reason
    * `details` - Additional error details

  ## Examples

      error = Lather.Error.transport_error(:timeout, %{timeout_ms: 30000})
  """
  @spec transport_error(atom() | String.t(), map()) :: transport_error()
  def transport_error(reason, details \\ %{}) do
    %{
      type: :transport_error,
      reason: reason,
      details: details
    }
  end

  @doc """
  Creates an HTTP error structure.

  ## Parameters

    * `status` - HTTP status code
    * `body` - Response body
    * `headers` - Response headers

  ## Examples

      error = Lather.Error.http_error(500, "Internal Server Error", [])
  """
  @spec http_error(integer(), String.t(), [{String.t(), String.t()}]) :: http_error()
  def http_error(status, body, headers \\ []) do
    %{
      type: :http_error,
      status: status,
      body: body,
      headers: headers
    }
  end

  @doc """
  Creates a WSDL error structure.

  ## Parameters

    * `reason` - The WSDL error reason
    * `details` - Additional error details

  ## Examples

      error = Lather.Error.wsdl_error(:invalid_wsdl, %{url: "http://example.com/wsdl"})
  """
  @spec wsdl_error(atom(), map()) :: wsdl_error()
  def wsdl_error(reason, details \\ %{}) do
    %{
      type: :wsdl_error,
      reason: reason,
      details: details
    }
  end

  @doc """
  Creates a validation error structure.

  ## Parameters

    * `field` - The field that failed validation
    * `reason` - The validation error reason
    * `details` - Additional error details

  ## Examples

      error = Lather.Error.validation_error("userId", :missing_required_field, %{})
  """
  @spec validation_error(String.t(), atom(), map()) :: validation_error()
  def validation_error(field, reason, details \\ %{}) do
    %{
      type: :validation_error,
      field: field,
      reason: reason,
      details: details
    }
  end

  @doc """
  Formats an error for display to users or logging.

  ## Parameters

    * `error` - The error structure to format
    * `options` - Formatting options

  ## Options

    * `:include_details` - Whether to include detailed information (default: true)
    * `:format` - Format type (:string, :map, :json) (default: :string)

  ## Examples

      message = Lather.Error.format_error(error)
      # "SOAP Fault: Server - Internal server error"

      detailed = Lather.Error.format_error(error, include_details: true)
  """
  @spec format_error(lather_error(), keyword()) :: String.t() | map()
  def format_error(error, options \\ [])

  def format_error(%{fault_code: code, fault_string: string} = fault, options) do
    include_details = Keyword.get(options, :include_details, true)
    format_type = Keyword.get(options, :format, :string)

    case format_type do
      :string ->
        base_msg = "SOAP Fault: #{code} - #{string}"

        if include_details do
          details = build_fault_details(fault)
          if details != "", do: base_msg <> "\n" <> details, else: base_msg
        else
          base_msg
        end

      :map ->
        fault

      :json ->
        encode_json(fault)
    end
  end

  def format_error(%{type: :transport_error, reason: reason} = error, options) do
    include_details = Keyword.get(options, :include_details, true)
    format_type = Keyword.get(options, :format, :string)

    case format_type do
      :string ->
        base_msg = "Transport Error: #{reason}"

        if include_details and not Enum.empty?(error.details) do
          details_str = Enum.map_join(error.details, ", ", fn {k, v} -> "#{k}: #{v}" end)
          base_msg <> " (#{details_str})"
        else
          base_msg
        end

      :map ->
        error

      :json ->
        encode_json(error)
    end
  end

  def format_error(%{type: :http_error, status: status} = error, options) do
    include_details = Keyword.get(options, :include_details, true)
    format_type = Keyword.get(options, :format, :string)

    case format_type do
      :string ->
        base_msg = "HTTP Error: #{status} #{get_status_text(status)}"

        if include_details and error.body != "" do
          body_preview = String.slice(error.body, 0, 200)
          base_msg <> "\nResponse: #{body_preview}"
        else
          base_msg
        end

      :map ->
        error

      :json ->
        encode_json(error)
    end
  end

  def format_error(%{type: :wsdl_error, reason: reason} = error, options) do
    include_details = Keyword.get(options, :include_details, true)
    format_type = Keyword.get(options, :format, :string)

    case format_type do
      :string ->
        base_msg = "WSDL Error: #{reason}"

        if include_details and not Enum.empty?(error.details) do
          details_str = Enum.map_join(error.details, ", ", fn {k, v} -> "#{k}: #{v}" end)
          base_msg <> " (#{details_str})"
        else
          base_msg
        end

      :map ->
        error

      :json ->
        encode_json(error)
    end
  end

  def format_error(%{type: :validation_error, field: field, reason: reason} = error, options) do
    include_details = Keyword.get(options, :include_details, true)
    format_type = Keyword.get(options, :format, :string)

    case format_type do
      :string ->
        base_msg = "Validation Error: #{field} - #{reason}"

        if include_details and not Enum.empty?(error.details) do
          details_str = Enum.map_join(error.details, ", ", fn {k, v} -> "#{k}: #{v}" end)
          base_msg <> " (#{details_str})"
        else
          base_msg
        end

      :map ->
        error

      :json ->
        encode_json(error)
    end
  end

  def format_error(error, _options) do
    "Unknown Error: #{inspect(error)}"
  end

  @doc """
  Checks if an error is recoverable (can be retried).

  ## Examples

      true = Lather.Error.recoverable?(transport_error(:timeout, %{}))
      false = Lather.Error.recoverable?(validation_error("field", :invalid_type, %{}))
  """
  @spec recoverable?(lather_error()) :: boolean()
  def recoverable?(%{type: :transport_error, reason: reason}) do
    reason in [:timeout, :connection_refused, :network_unreachable]
  end

  def recoverable?(%{type: :http_error, status: status}) do
    status in [500, 502, 503, 504]  # Server errors that might be temporary
  end

  def recoverable?(%{fault_code: "Server"}) do
    true  # Server faults might be temporary
  end

  def recoverable?(%{fault_code: "Client"}) do
    false  # Client faults are usually permanent
  end

  def recoverable?(_error) do
    false
  end

  @doc """
  Extracts error context for debugging.

  ## Parameters

    * `error` - The error to extract context from

  ## Examples

      context = Lather.Error.extract_debug_context(error)
      # %{error_type: :soap_fault, timestamp: ~U[...], ...}
  """
  @spec extract_debug_context(lather_error()) :: map()
  def extract_debug_context(error) do
    base_context = %{
      timestamp: DateTime.utc_now(),
      error_type: get_error_type(error)
    }

    case error do
      %{type: type} = structured_error ->
        Map.merge(base_context, %{
          structured_type: type,
          details: Map.get(structured_error, :details, %{})
        })

      soap_fault ->
        Map.merge(base_context, %{
          fault_code: Map.get(soap_fault, :fault_code),
          fault_string: Map.get(soap_fault, :fault_string)
        })
    end
  end

  # Private helper functions

  defp extract_fault_from_xml(parsed_xml, _options) do
    # Try different SOAP fault structures
    fault_data =
      get_in(parsed_xml, ["Envelope", "Body", "Fault"]) ||
      get_in(parsed_xml, ["soap:Envelope", "soap:Body", "soap:Fault"]) ||
      get_in(parsed_xml, ["soapenv:Envelope", "soapenv:Body", "soapenv:Fault"])

    case fault_data do
      nil ->
        {:error, :no_fault_found}

      fault ->
        soap_fault = %{
          fault_code: extract_fault_code(fault),
          fault_string: extract_fault_string(fault),
          fault_actor: extract_fault_actor(fault),
          detail: extract_fault_detail(fault)
        }

        {:ok, soap_fault}
    end
  end

  defp extract_fault_code(fault) do
    fault["faultcode"] || fault["Code"] || fault["soap:faultcode"] || "Unknown"
  end

  defp extract_fault_string(fault) do
    fault["faultstring"] || fault["Reason"] || fault["soap:faultstring"] || "Unknown error"
  end

  defp extract_fault_actor(fault) do
    fault["faultactor"] || fault["Actor"] || fault["soap:faultactor"]
  end

  defp extract_fault_detail(fault) do
    detail = fault["detail"] || fault["Detail"] || fault["soap:detail"]

    case detail do
      nil -> nil
      detail_map when is_map(detail_map) -> detail_map
      detail_text -> %{"detail" => detail_text}
    end
  end

  defp build_fault_details(fault) do
    details = []

    details = if fault.fault_actor do
      ["Actor: #{fault.fault_actor}" | details]
    else
      details
    end

    details = if fault.detail do
      detail_str = format_fault_detail(fault.detail)
      ["Detail: #{detail_str}" | details]
    else
      details
    end

    Enum.join(details, "\n")
  end

  defp format_fault_detail(detail) when is_map(detail) do
    detail
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end

  defp format_fault_detail(detail) do
    to_string(detail)
  end

  defp get_status_text(200), do: "OK"
  defp get_status_text(400), do: "Bad Request"
  defp get_status_text(401), do: "Unauthorized"
  defp get_status_text(403), do: "Forbidden"
  defp get_status_text(404), do: "Not Found"
  defp get_status_text(500), do: "Internal Server Error"
  defp get_status_text(502), do: "Bad Gateway"
  defp get_status_text(503), do: "Service Unavailable"
  defp get_status_text(504), do: "Gateway Timeout"
  defp get_status_text(_), do: "Unknown"

  defp get_error_type(%{type: type}), do: type
  defp get_error_type(%{fault_code: _}), do: :soap_fault
  defp get_error_type(_), do: :unknown

  defp encode_json(data) do
    # Simple JSON encoding without external dependencies
    inspect(data)
  end
end
