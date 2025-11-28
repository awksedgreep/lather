defmodule Lather.Soap.Envelope do
  @moduledoc """
  SOAP envelope builder and parser.

  Handles creation and parsing of SOAP 1.1 envelopes with support for
  headers, namespaces, and fault detection.
  """

  alias Lather.Xml.Builder
  alias Lather.Xml.Parser

  @soap_1_1_namespace "http://schemas.xmlsoap.org/soap/envelope/"
  @soap_1_2_namespace "http://www.w3.org/2003/05/soap-envelope"

  @doc """
  Builds a SOAP envelope for the given operation and parameters.

  ## Parameters

  * `operation` - The operation name (atom or string)
  * `params` - Parameters for the operation (map)
  * `options` - Envelope options

  ## Options

  * `:version` - SOAP version (`:v1_1` or `:v1_2`, default: `:v1_1`)
  * `:headers` - SOAP headers to include
  * `:namespace` - Target namespace for the operation

  ## Examples

      iex> Envelope.build(:get_user, %{id: 123})
      {:ok, "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>..."}

  """
  @spec build(atom() | String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, any()}
  def build(operation, params, options \\ []) do
    version = Keyword.get(options, :version, :v1_1)
    headers = Keyword.get(options, :headers, [])
    namespace = Keyword.get(options, :namespace, "")

    envelope = %{
      "soap:Envelope" => %{
        "@xmlns:soap" => namespace_for_version(version),
        "soap:Header" => build_header(headers),
        "soap:Body" => build_body(operation, params, namespace)
      }
    }

    case Builder.build(envelope) do
      {:ok, xml} -> {:ok, xml}
      {:error, reason} -> {:error, {:envelope_build_error, reason}}
    end
  end

  @doc """
  Parses a SOAP response and extracts the result or fault.

  ## Parameters

  * `response` - HTTP response map with `:body` key containing XML

  ## Returns

  * `{:ok, result}` - Successful response with parsed body
  * `{:error, fault}` - SOAP fault or parsing error

  """
  @spec parse_response(map()) :: {:ok, any()} | {:error, any()}
  def parse_response(%{status: status, body: body}) when status in 200..299 do
    case Parser.parse(body) do
      {:ok, parsed} ->
        case extract_body_or_fault(parsed) do
          {:ok, result} -> {:ok, result}
          {:error, fault} -> {:error, {:soap_fault, fault}}
        end

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  def parse_response(%{status: status, body: body}) do
    case Parser.parse(body) do
      {:ok, parsed} ->
        case extract_body_or_fault(parsed) do
          {:error, fault} -> {:error, {:soap_fault, fault}}
          {:ok, _} -> {:error, {:http_error, status, body}}
        end

      {:error, _reason} ->
        {:error, {:http_error, status, body}}
    end
  end

  # Private functions

  defp namespace_for_version(:v1_1), do: @soap_1_1_namespace
  defp namespace_for_version(:v1_2), do: @soap_1_2_namespace

  defp build_header([]), do: nil

  defp build_header(headers) when is_list(headers) do
    # Headers can be:
    # 1. List of tuples: [{"Key", "Value"}, {"Key2", "Value2"}]
    # 2. List of maps: [%{"wsse:Security" => %{...}}, %{"Header2" => "Value"}]
    # We need to handle both formats and merge them into a single map
    Enum.reduce(headers, %{}, fn
      {key, value}, acc -> Map.put(acc, key, value)
      header_map, acc when is_map(header_map) -> Map.merge(acc, header_map)
    end)
  end

  defp build_body(operation, params, namespace) do
    operation_name = to_string(operation)

    body_content =
      if namespace != "" do
        %{
          operation_name => Map.merge(%{"@xmlns" => namespace}, params)
        }
      else
        %{operation_name => params}
      end

    body_content
  end

  defp extract_body_or_fault(parsed_xml) do
    cond do
      has_soap_fault?(parsed_xml) ->
        {:error, extract_fault(parsed_xml)}

      has_soap_body?(parsed_xml) ->
        {:ok, extract_body(parsed_xml)}

      true ->
        {:error, :invalid_soap_response}
    end
  end

  defp has_soap_fault?(parsed_xml) do
    # Check for SOAP fault in the parsed XML structure
    get_in(parsed_xml, ["soap:Envelope", "soap:Body", "soap:Fault"]) != nil or
      get_in(parsed_xml, ["Envelope", "Body", "Fault"]) != nil
  end

  defp has_soap_body?(parsed_xml) do
    get_in(parsed_xml, ["soap:Envelope", "soap:Body"]) != nil or
      get_in(parsed_xml, ["Envelope", "Body"]) != nil
  end

  defp extract_fault(parsed_xml) do
    fault =
      get_in(parsed_xml, ["soap:Envelope", "soap:Body", "soap:Fault"]) ||
        get_in(parsed_xml, ["Envelope", "Body", "Fault"])

    soap_version = detect_soap_version(parsed_xml)

    case soap_version do
      :v1_2 -> extract_soap_1_2_fault(fault)
      :v1_1 -> extract_soap_1_1_fault(fault)
      # fallback to SOAP 1.1 parsing
      _ -> extract_soap_1_1_fault(fault)
    end
  end

  defp detect_soap_version(parsed_xml) do
    cond do
      # Check for SOAP 1.2 namespace in envelope
      get_in(parsed_xml, ["soap:Envelope", "@xmlns:soap"]) ==
          "http://www.w3.org/2003/05/soap-envelope" ->
        :v1_2

      # Check for SOAP 1.2 namespace without prefix
      get_in(parsed_xml, ["Envelope", "@xmlns"]) == "http://www.w3.org/2003/05/soap-envelope" ->
        :v1_2

      # Check for SOAP 1.2 fault structure (nested Code/Value)
      has_soap_1_2_fault_structure?(parsed_xml) ->
        :v1_2

      # Default to SOAP 1.1
      true ->
        :v1_1
    end
  end

  defp has_soap_1_2_fault_structure?(parsed_xml) do
    fault =
      get_in(parsed_xml, ["soap:Envelope", "soap:Body", "soap:Fault"]) ||
        get_in(parsed_xml, ["Envelope", "Body", "Fault"])

    fault && (get_in(fault, ["soap:Code", "soap:Value"]) || get_in(fault, ["Code", "Value"]))
  end

  defp extract_soap_1_1_fault(fault) do
    %{
      code: get_in(fault, ["faultcode"]),
      string: get_in(fault, ["faultstring"]),
      detail: get_in(fault, ["detail"]),
      soap_version: :v1_1
    }
  end

  defp extract_soap_1_2_fault(fault) do
    # Handle the case where fault might be nil
    if fault do
      # Extract main fault code - handle both nested and simple structures
      code = extract_soap_1_2_code(fault)

      # Extract subcode if present - only for proper nested structure
      subcode = extract_soap_1_2_subcode(fault)

      # Extract reason text
      reason = extract_soap_1_2_reason(fault)

      # Extract detail
      detail =
        get_in(fault, ["soap:Detail"]) ||
          get_in(fault, ["Detail"])

      %{
        code: code,
        subcode: subcode,
        string: reason,
        detail: detail,
        soap_version: :v1_2
      }
    else
      %{
        code: nil,
        subcode: nil,
        string: nil,
        detail: nil,
        soap_version: :v1_2
      }
    end
  end

  defp extract_soap_1_2_code(fault) do
    # First check if we have a nested structure
    soap_code_element = get_in(fault, ["soap:Code"])
    code_element = get_in(fault, ["Code"])

    cond do
      # Try soap:Code with nested soap:Value
      is_map(soap_code_element) ->
        get_in(soap_code_element, ["soap:Value"]) || soap_code_element

      # Try Code with nested Value
      is_map(code_element) ->
        get_in(code_element, ["Value"]) || code_element

      # Fall back to simple string values
      soap_code_element ->
        soap_code_element

      code_element ->
        code_element

      true ->
        nil
    end
  end

  defp extract_soap_1_2_subcode(fault) do
    # Only try nested structure for subcode (simple structure doesn't have subcodes)
    soap_code_element = get_in(fault, ["soap:Code"])
    code_element = get_in(fault, ["Code"])

    cond do
      is_map(soap_code_element) ->
        subcode_element = get_in(soap_code_element, ["soap:Subcode"])

        if is_map(subcode_element) do
          get_in(subcode_element, ["soap:Value"]) || subcode_element
        end

      is_map(code_element) ->
        subcode_element = get_in(code_element, ["Subcode"])

        if is_map(subcode_element) do
          get_in(subcode_element, ["Value"]) || subcode_element
        end

      true ->
        nil
    end
  end

  defp extract_soap_1_2_reason(fault) do
    # Get reason element - could be nested structure or simple string
    soap_reason_element = get_in(fault, ["soap:Reason"])
    reason_element = get_in(fault, ["Reason"])

    cond do
      # Handle nested soap:Reason structure (proper SOAP 1.2)
      is_map(soap_reason_element) ->
        extract_nested_reason_text(soap_reason_element, ["soap:Text", "Text"])

      # Handle nested Reason structure
      is_map(reason_element) ->
        extract_nested_reason_text(reason_element, ["soap:Text", "Text"])

      # Handle simple string soap:Reason
      is_binary(soap_reason_element) ->
        soap_reason_element

      # Handle simple string Reason
      is_binary(reason_element) ->
        reason_element

      # No reason found
      true ->
        nil
    end
  end

  defp extract_nested_reason_text(reason_element, text_keys) do
    # Try to find text element using provided keys
    text_element =
      Enum.find_value(text_keys, fn key ->
        get_in(reason_element, [key])
      end)

    case text_element do
      # Single text element with #text content (most common case)
      %{"#text" => text} when is_binary(text) ->
        text

      # Simple string content
      text when is_binary(text) ->
        text

      # Multiple text elements - handle as list
      text_list when is_list(text_list) ->
        # Try to find English text first
        english_text =
          Enum.find(text_list, fn text ->
            case text do
              %{"@xml:lang" => "en", "#text" => _} -> true
              %{"@xml:lang" => "en"} -> true
              _ -> false
            end
          end)

        case english_text do
          %{"#text" => text} ->
            text

          _ ->
            # Fall back to first available text
            case List.first(text_list) do
              %{"#text" => text} -> text
              text when is_binary(text) -> text
              _ -> nil
            end
        end

      # Fallback for other structures
      _ ->
        nil
    end
  end

  defp extract_body(parsed_xml) do
    body =
      get_in(parsed_xml, ["soap:Envelope", "soap:Body"]) ||
        get_in(parsed_xml, ["Envelope", "Body"])

    # Remove SOAP envelope structure and return the operation result
    case Map.keys(body) do
      [key] when key not in ["soap:Fault", "Fault"] ->
        Map.get(body, key)

      keys ->
        # Multiple top-level elements, return the whole body except faults
        Enum.reduce(keys, %{}, fn key, acc ->
          if key not in ["soap:Fault", "Fault"] do
            Map.put(acc, key, Map.get(body, key))
          else
            acc
          end
        end)
    end
  end
end
