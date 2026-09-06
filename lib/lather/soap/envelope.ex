defmodule Lather.Soap.Envelope do
  @moduledoc """
  SOAP envelope builder and parser.

  Handles creation and parsing of SOAP 1.1 envelopes with support for
  headers, namespaces, and fault detection.
  """

  alias Lather.Soap.Elements
  alias Lather.Xml.Builder
  alias Lather.Xml.Parser

  @soap_1_1_namespace Elements.soap_1_1_namespace()
  @soap_1_2_namespace Elements.soap_1_2_namespace()

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
  * `:namespace_prefix` - Optional namespace prefix for the operation element (e.g. `"ns0"`).
    When set the element is rendered as `<ns0:Op xmlns:ns0="...">` instead of the default
    `<Op xmlns="...">`. When omitted, the existing default-namespace behaviour is preserved.

  ## Examples

      iex> Envelope.build(:get_user, %{id: 123})
      {:ok, "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>..."}

  """
  @spec build(atom() | String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, any()}
  def build(operation, params, options \\ []) do
    version = Keyword.get(options, :version, :v1_1)
    headers = Keyword.get(options, :headers, [])
    namespace = Keyword.get(options, :namespace, "")
    namespace_prefix = Keyword.get(options, :namespace_prefix)
    # raw_body: when true, params are used directly as body content without wrapping
    # in operation element (used for document/literal with element-based parts)
    raw_body = Keyword.get(options, :raw_body, false)

    body_content =
      if raw_body do
        params
      else
        build_body(operation, params, namespace, namespace_prefix)
      end

    envelope = [
      {"soap:Envelope",
       [
         {"@xmlns:soap", namespace_for_version(version)},
         {"soap:Header", build_header(headers)},
         {"soap:Body", body_content}
       ]}
    ]

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

  * `{:ok, result}` - Successful response with parsed body. An empty
    `<Body/>` yields `{:ok, %{}}`.
  * `{:error, {:soap_fault, fault}}` - The body carried a SOAP fault
  * `{:error, :invalid_soap_response}` - No Envelope/Body found
  * `{:error, {:parse_error, reason}}` - The body was not valid XML
  * `{:error, {:http_error, status, body}}` - Non-2xx status without a fault

  Envelope, Body and Fault elements are matched by local name, so any
  namespace prefix (`soap:`, `soapenv:`, `SOAP-ENV:`, `s:`, none, ...) is
  accepted.
  """
  @spec parse_response(map()) :: {:ok, any()} | {:error, any()}
  def parse_response(%{status: status, body: body}) when status in 200..299 do
    case Parser.parse(body) do
      {:ok, parsed} -> extract_body_or_fault(parsed)
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  def parse_response(%{status: status, body: body}) do
    case Parser.parse(body) do
      {:ok, parsed} ->
        case extract_body_or_fault(parsed) do
          {:error, {:soap_fault, _} = fault} -> {:error, fault}
          _ -> {:error, {:http_error, status, body}}
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

  defp build_body(operation, params, namespace, namespace_prefix)

  defp build_body(operation, params, namespace, nil) do
    operation_name = to_string(operation)

    if namespace != "" do
      %{operation_name => Map.merge(%{"@xmlns" => namespace}, params)}
    else
      %{operation_name => params}
    end
  end

  defp build_body(operation, params, namespace, prefix) when is_binary(prefix) do
    operation_name = to_string(operation)
    prefixed_name = "#{prefix}:#{operation_name}"

    if namespace != "" do
      %{prefixed_name => Map.merge(%{"@xmlns:#{prefix}" => namespace}, params)}
    else
      %{prefixed_name => params}
    end
  end

  # Envelope / Body / Fault lookups are prefix-agnostic (see
  # `Lather.Soap.Elements`): peers use `soap:`, `soapenv:`, `SOAP-ENV:`,
  # `s:`, `env:` or no prefix at all.
  defp extract_body_or_fault(parsed_xml) do
    with {:ok, envelope} <- fetch_envelope(parsed_xml),
         {:ok, body} <- fetch_body(envelope) do
      case Elements.get(body, "Fault") do
        nil ->
          {:ok, extract_body(body)}

        fault ->
          {:error, {:soap_fault, extract_fault(fault, Elements.soap_version(parsed_xml))}}
      end
    end
  end

  defp fetch_envelope(parsed_xml) do
    case Elements.get(parsed_xml, "Envelope") do
      envelope when is_map(envelope) -> {:ok, envelope}
      _ -> {:error, :invalid_soap_response}
    end
  end

  # An empty `<Body/>` (legal for one-way / void operations) parses as
  # `""`; normalise it to an empty map instead of crashing on `get_in`.
  defp fetch_body(envelope) do
    case Elements.get(envelope, "Body") do
      body when is_map(body) -> {:ok, body}
      "" -> {:ok, %{}}
      _ -> {:error, :invalid_soap_response}
    end
  end

  defp extract_fault(fault, :v1_2), do: extract_soap_1_2_fault(fault)
  defp extract_fault(fault, :v1_1), do: extract_soap_1_1_fault(fault)

  defp extract_soap_1_1_fault(fault) do
    %{
      code: Elements.get(fault, "faultcode"),
      string: Elements.get(fault, "faultstring"),
      detail: Elements.get(fault, "detail"),
      soap_version: :v1_1
    }
  end

  defp extract_soap_1_2_fault(fault) when is_map(fault) do
    code_element = Elements.get(fault, "Code")

    %{
      code: extract_soap_1_2_code(code_element),
      subcode: extract_soap_1_2_subcode(code_element),
      string: extract_soap_1_2_reason(Elements.get(fault, "Reason")),
      detail: Elements.get(fault, "Detail"),
      soap_version: :v1_2
    }
  end

  defp extract_soap_1_2_fault(_fault) do
    %{code: nil, subcode: nil, string: nil, detail: nil, soap_version: :v1_2}
  end

  # Proper structure is <Code><Value>..</Value></Code>; tolerate a bare
  # string as well.
  defp extract_soap_1_2_code(code) when is_map(code), do: Elements.get(code, "Value") || code
  defp extract_soap_1_2_code(code), do: code

  defp extract_soap_1_2_subcode(code) when is_map(code) do
    case Elements.get(code, "Subcode") do
      subcode when is_map(subcode) -> Elements.get(subcode, "Value") || subcode
      _ -> nil
    end
  end

  defp extract_soap_1_2_subcode(_), do: nil

  defp extract_soap_1_2_reason(reason) when is_map(reason) do
    extract_reason_text(Elements.get(reason, "Text"))
  end

  defp extract_soap_1_2_reason(reason) when is_binary(reason), do: reason
  defp extract_soap_1_2_reason(_), do: nil

  # <Text xml:lang="..."> may repeat; prefer English, else the first one.
  defp extract_reason_text(%{"#text" => text}) when is_binary(text), do: text
  defp extract_reason_text(text) when is_binary(text), do: text

  defp extract_reason_text(texts) when is_list(texts) do
    english = Enum.find(texts, &match?(%{"@xml:lang" => "en"}, &1))

    case english || List.first(texts) do
      %{"#text" => text} -> text
      text when is_binary(text) -> text
      _ -> nil
    end
  end

  defp extract_reason_text(_), do: nil

  # Strip the envelope structure and return the operation result. A body
  # with a single element yields that element's value; otherwise the map
  # of body children (faults excluded) is returned.
  defp extract_body(body) do
    children = Enum.reject(body, fn {key, _} -> Elements.local_name(key) == "Fault" end)

    case children do
      [{_key, value}] -> value
      pairs -> Map.new(pairs)
    end
  end
end
