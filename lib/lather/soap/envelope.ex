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
    Enum.into(headers, %{})
  end

  defp build_body(operation, params, namespace) do
    operation_name = to_string(operation)

    body_content = if namespace != "" do
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
    fault = get_in(parsed_xml, ["soap:Envelope", "soap:Body", "soap:Fault"]) ||
            get_in(parsed_xml, ["Envelope", "Body", "Fault"])

    %{
      code: get_in(fault, ["faultcode"]) || get_in(fault, ["Code"]),
      string: get_in(fault, ["faultstring"]) || get_in(fault, ["Reason"]),
      detail: get_in(fault, ["detail"]) || get_in(fault, ["Detail"])
    }
  end

  defp extract_body(parsed_xml) do
    body = get_in(parsed_xml, ["soap:Envelope", "soap:Body"]) ||
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
