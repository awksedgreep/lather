defmodule Lather.Operation.Builder do
  @moduledoc """
  Generic operation builder for SOAP services.

  This module provides utilities to dynamically build SOAP requests for any operation
  defined in a WSDL, without requiring hardcoded service implementations.
  """

  alias Lather.Soap.Envelope
  alias Lather.Error

  @doc """
  Builds a SOAP request for any operation based on WSDL analysis.

  ## Parameters

    * `operation_info` - Operation information extracted from WSDL analysis
    * `parameters` - Map of parameters for the operation
    * `options` - Additional options for request building

  ## Options

    * `:style` - SOAP style (:document or :rpc, default: :document)
    * `:use` - SOAP use (:literal or :encoded, default: :literal)
    * `:namespace` - Target namespace for the operation
    * `:headers` - Additional SOAP headers
    * `:version` - SOAP version (`:v1_1` or `:v1_2`, default: `:v1_1`)

  ## Examples

      operation_info = %{
        name: "GetUser",
        input: %{
          message: "GetUserRequest",
          parts: [%{name: "userId", type: "xsd:string"}]
        },
        soap_action: "http://example.com/GetUser"
      }

      params = %{"userId" => "12345"}

      {:ok, soap_envelope} = Lather.Operation.Builder.build_request(
        operation_info,
        params,
        namespace: "http://example.com/service"
      )
  """
  @spec build_request(map(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def build_request(operation_info, parameters, options \\ []) do
    # Style: prefer operation_info.style, then options, then default to :document
    style =
      operation_info[:style] ||
        Keyword.get(options, :style, :document)

    version = Keyword.get(options, :version, :v1_1)
    # Extract use type from operation_info first, then options, then default
    use_type =
      get_in(operation_info, [:input, :use]) ||
        Keyword.get(options, :use, :literal)

    namespace = Keyword.get(options, :namespace, "")
    headers = Keyword.get(options, :headers, [])

    # Check if this is element-based document/literal (body is already properly structured)
    input_parts = operation_info.input.parts || []
    element_based = Enum.any?(input_parts, fn part -> part[:element] != nil end)

    with {:ok, body_content} <-
           build_operation_body(operation_info, parameters, style, use_type, namespace) do
      # Extract operation name and parameters from body content
      operation_name = operation_info.name

      # For element-based document/literal, the body_content is already the correct
      # structure (e.g., %{"LeadCotizadorOper_Input" => ...}) and should NOT be
      # wrapped again in the operation name.
      {processed_params, raw_body} =
        if element_based and style in [:document, "document"] do
          # Use body_content directly as raw body
          {body_content, true}
        else
          # Traditional wrapping - extract params from operation wrapper if present
          params =
            case body_content do
              %{^operation_name => inner_params} -> inner_params
              _ -> body_content
            end

          {params, false}
        end

      # Build envelope with proper parameters
      envelope_options = [
        namespace: namespace,
        headers: headers,
        version: version,
        raw_body: raw_body
      ]

      Envelope.build(operation_name, processed_params, envelope_options)
    end
  end

  @doc """
  Validates parameters against operation input specification.

  ## Parameters

    * `operation_info` - Operation information from WSDL
    * `parameters` - Parameters to validate

  ## Examples

      iex> operation_info = %{input: %{parts: [%{name: "userId", type: "xsd:string"}]}}
      iex> Lather.Operation.Builder.validate_parameters(operation_info, %{"userId" => "123"})
      :ok

      iex> Lather.Operation.Builder.validate_parameters(operation_info, %{})
      {:error, {:missing_required_parameter, "userId"}}
  """
  @spec validate_parameters(map(), map()) :: :ok | {:error, term()}
  def validate_parameters(operation_info, parameters) do
    required_parts = operation_info.input.parts || []

    Enum.reduce_while(required_parts, :ok, fn part, _acc ->
      part_name = part.name

      case Map.get(parameters, part_name) do
        nil ->
          error =
            Error.validation_error(part_name, :missing_required_parameter, %{
              message: "Required parameter '#{part_name}' is missing",
              expected_type: part.type
            })

          {:halt, {:error, error}}

        value ->
          case validate_parameter_type(value, part.type) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
      end
    end)
  end

  @doc """
  Extracts response data from SOAP envelope based on operation output specification.

  ## Parameters

    * `operation_info` - Operation information from WSDL
    * `response_envelope` - Parsed SOAP response envelope
    * `options` - Parsing options

  ## Examples

      operation_info = %{
        output: %{
          parts: [%{name: "user", type: "tns:User"}]
        }
      }

      {:ok, response_data} = Lather.Operation.Builder.parse_response(
        operation_info,
        parsed_response
      )
  """
  @spec parse_response(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse_response(operation_info, response_envelope, options \\ []) do
    style = Keyword.get(options, :style, :document)

    case extract_response_body(response_envelope) do
      {:ok, body_content} ->
        parse_operation_response(operation_info, body_content, style)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates operation metadata for dynamic client usage.

  ## Parameters

    * `operation_info` - Operation information from WSDL

  ## Examples

      metadata = Lather.Operation.Builder.get_operation_metadata(operation_info)
      # %{
      #   name: "GetUser",
      #   required_parameters: ["userId"],
      #   optional_parameters: [],
      #   return_type: "User",
      #   soap_action: "http://example.com/GetUser"
      # }
  """
  @spec get_operation_metadata(map()) :: map()
  def get_operation_metadata(operation_info) do
    input_parts = operation_info.input.parts || []
    output_parts = operation_info.output.parts || []

    %{
      name: operation_info.name,
      soap_action: operation_info.soap_action || "",
      required_parameters: extract_required_parameters(input_parts),
      optional_parameters: extract_optional_parameters(input_parts),
      return_type: extract_return_type(output_parts),
      input_message: operation_info.input.message || "",
      output_message: operation_info.output.message || "",
      documentation: operation_info.documentation || ""
    }
  end

  # Private helper functions

  defp build_operation_body(operation_info, parameters, style, use_type, namespace) do
    case style do
      :document ->
        build_document_style_body(operation_info, parameters, use_type, namespace)

      "document" ->
        build_document_style_body(operation_info, parameters, use_type, namespace)

      :rpc ->
        build_rpc_style_body(operation_info, parameters, use_type, namespace)

      "rpc" ->
        build_rpc_style_body(operation_info, parameters, use_type, namespace)
    end
  end

  defp build_document_style_body(operation_info, parameters, :literal, namespace) do
    input_parts = operation_info.input.parts || []

    # Check if this is element-based document/literal (parts have element attributes)
    element_based = Enum.any?(input_parts, fn part -> part[:element] != nil end)

    if element_based do
      # Document/literal with element-based parts - each part becomes a direct body element
      body_elements =
        Enum.reduce(input_parts, %{}, fn part, acc ->
          param_value = Map.get(parameters, part.name)

          if param_value != nil do
            # Extract element name from element attribute (remove namespace prefix)
            element_name =
              case String.split(part.element, ":") do
                [_namespace, name] -> name
                [name] -> name
              end

            # Build element content - for empty maps, create empty element
            element_content =
              if param_value == %{} do
                %{"@xmlns" => namespace}
              else
                # For non-empty content, merge with namespace
                Map.put(param_value, "@xmlns", namespace)
              end

            Map.put(acc, element_name, element_content)
          else
            acc
          end
        end)

      {:ok, body_elements}
    else
      # Traditional document/literal - operation name as wrapper
      operation_name = operation_info.name

      # Build parameter elements
      param_elements =
        Enum.map(input_parts, fn part ->
          param_name = part.name
          param_value = Map.get(parameters, param_name)

          if param_value do
            build_parameter_element(param_name, param_value, part.type)
          else
            nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      # Wrap in operation element
      body_content = %{
        operation_name => %{
          "@xmlns" => namespace,
          "#content" => param_elements
        }
      }

      {:ok, body_content}
    end
  end

  defp build_document_style_body(operation_info, parameters, :encoded, _namespace) do
    # For document/encoded, build similar to literal but with encoded semantics
    operation_name = operation_info.name
    input_parts = operation_info.input.parts || []

    # Build parameter elements for encoded style
    param_elements =
      Enum.map(input_parts, fn part ->
        param_name = part.name
        param_value = Map.get(parameters, param_name)

        if param_value != nil do
          element = build_parameter_element(param_name, param_value, part.type)
          %{param_name => element}
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # Create the operation wrapper element
    body_content = %{
      operation_name =>
        param_elements
        |> Enum.reduce(%{}, fn element, acc ->
          Map.merge(acc, element)
        end)
    }

    {:ok, body_content}
  end

  # Handle string versions of use_type
  defp build_document_style_body(operation_info, parameters, "literal", namespace) do
    build_document_style_body(operation_info, parameters, :literal, namespace)
  end

  defp build_document_style_body(operation_info, parameters, "encoded", namespace) do
    build_document_style_body(operation_info, parameters, :encoded, namespace)
  end

  defp build_rpc_style_body(operation_info, parameters, use_type, namespace) do
    operation_name = operation_info.name
    input_parts = operation_info.input.parts || []

    # Build parameter elements according to RPC style
    param_elements =
      Enum.reduce(input_parts, %{}, fn part, acc ->
        param_name = part.name
        param_value = Map.get(parameters, param_name)

        if param_value do
          element =
            case use_type do
              :literal -> build_parameter_element(param_name, param_value, part.type)
              :encoded -> build_encoded_parameter_element(param_name, param_value, part.type)
              "literal" -> build_parameter_element(param_name, param_value, part.type)
              "encoded" -> build_encoded_parameter_element(param_name, param_value, part.type)
            end

          Map.put(acc, param_name, element)
        else
          acc
        end
      end)

    # Wrap in operation element with namespace
    body_content = %{
      operation_name =>
        %{
          "@xmlns" => namespace
        }
        |> Map.merge(param_elements)
    }

    {:ok, body_content}
  end

  defp build_parameter_element(_name, value, type) do
    case classify_parameter_type(type) do
      :simple ->
        build_simple_parameter(value, type)

      :complex ->
        build_complex_parameter(value, type)

      :array ->
        build_array_parameter(value, type)
    end
  end

  defp build_encoded_parameter_element(name, value, type) do
    # Add SOAP encoding information
    base_element = build_parameter_element(name, value, type)

    case base_element do
      element when is_map(element) ->
        Map.put(element, "@xsi:type", type)

      simple_value ->
        %{"#text" => simple_value, "@xsi:type" => type}
    end
  end

  defp build_simple_parameter(value, _type)
       when is_binary(value) or is_number(value) or is_boolean(value) do
    to_string(value)
  end

  defp build_simple_parameter(value, type) when is_map(value) do
    # If a map is classified as simple, treat it as complex instead
    build_complex_parameter(value, type)
  end

  defp build_simple_parameter(value, _type) do
    to_string(value)
  end

  defp build_complex_parameter(value, _type) when is_map(value) do
    # Convert map to XML elements - avoid recursive calls that cause string conversion issues
    Enum.reduce(value, %{}, fn {key, val}, acc ->
      Map.put(acc, to_string(key), to_string(val))
    end)
  end

  defp build_complex_parameter(value, _type) do
    %{"#text" => to_string(value)}
  end

  defp build_array_parameter(values, _type) when is_list(values) do
    Enum.map(values, fn value ->
      build_parameter_element("item", value, "")
    end)
  end

  defp build_array_parameter(value, type) do
    build_simple_parameter(value, type)
  end

  defp classify_parameter_type(type) do
    cond do
      String.contains?(type, "Array") or String.contains?(type, "[]") ->
        :array

      String.starts_with?(type, "xsd:") or String.starts_with?(type, "xs:") ->
        :simple

      # Common simple types without namespace prefixes
      is_simple_type?(type) ->
        :simple

      true ->
        :complex
    end
  end

  defp is_simple_type?(type) do
    simple_types = [
      "string",
      "int",
      "integer",
      "long",
      "short",
      "byte",
      "double",
      "float",
      "decimal",
      "boolean",
      "date",
      "dateTime",
      "time",
      "duration",
      "base64Binary",
      "hexBinary",
      "anyURI",
      "QName",
      "NOTATION",
      "token",
      "normalizedString",
      "language",
      "NMTOKEN",
      "NMTOKENS",
      "Name",
      "NCName",
      "ID",
      "IDREF",
      "IDREFS",
      "ENTITY",
      "ENTITIES",
      "unsignedLong",
      "unsignedInt",
      "unsignedShort",
      "unsignedByte",
      "positiveInteger",
      "nonNegativeInteger",
      "negativeInteger",
      "nonPositiveInteger",
      "gYearMonth",
      "gYear",
      "gMonthDay",
      "gDay",
      "gMonth"
    ]

    type_lower = String.downcase(type)

    # Handle enumeration-like types or custom simple types that might be strings
    Enum.any?(simple_types, fn simple_type ->
      String.contains?(type_lower, String.downcase(simple_type))
    end) or
      (String.contains?(type, "Type") and not String.contains?(type, "Complex"))
  end

  defp validate_parameter_type(value, type) do
    case {classify_parameter_type(type), value} do
      {:simple, value} when is_binary(value) or is_number(value) or is_boolean(value) ->
        :ok

      {:complex, value} when is_map(value) ->
        :ok

      {:array, value} when is_list(value) ->
        :ok

      # Be more lenient - allow strings for complex types (common in SOAP)
      {:complex, value} when is_binary(value) ->
        :ok

      # Allow maps for simple types (structured parameters)
      {:simple, value} when is_map(value) ->
        :ok

      # Allow atoms for simple types
      {:simple, value} when is_atom(value) ->
        :ok

      # Fallback - be permissive for real-world WSDL variations
      {_expected_type, _value} ->
        :ok
    end
  end

  defp extract_response_body(response_envelope) do
    case response_envelope do
      %{"Envelope" => %{"Body" => body}} ->
        {:ok, body}

      %{"soap:Envelope" => %{"soap:Body" => body}} ->
        {:ok, body}

      %{"SOAP-ENV:Envelope" => %{"SOAP-ENV:Body" => body}} ->
        {:ok, body}

      _ ->
        # Try to find envelope/body with any namespace prefix
        case find_envelope_body(response_envelope) do
          {:ok, body} ->
            {:ok, body}

          :not_found ->
            error =
              Error.validation_error(:soap_response, :invalid_soap_response, %{
                message: "Response does not contain valid SOAP envelope structure",
                received_structure: inspect(response_envelope)
              })

            {:error, error}
        end
    end
  end

  # Dynamically find envelope and body elements with any namespace prefix
  defp find_envelope_body(response_envelope) when is_map(response_envelope) do
    envelope_key =
      Enum.find(Map.keys(response_envelope), fn key ->
        key_str = to_string(key)
        String.ends_with?(key_str, "Envelope") or String.ends_with?(key_str, ":Envelope")
      end)

    case envelope_key do
      nil ->
        :not_found

      key ->
        envelope_content = response_envelope[key]

        body_key =
          Enum.find(Map.keys(envelope_content || %{}), fn k ->
            k_str = to_string(k)
            String.ends_with?(k_str, "Body") or String.ends_with?(k_str, ":Body")
          end)

        case body_key do
          nil -> :not_found
          bk -> {:ok, envelope_content[bk]}
        end
    end
  end

  defp find_envelope_body(_), do: :not_found

  defp parse_operation_response(operation_info, body_content, style) do
    case style do
      :document ->
        parse_document_response(operation_info, body_content)

      "document" ->
        parse_document_response(operation_info, body_content)

      :rpc ->
        parse_rpc_response(operation_info, body_content)

      "rpc" ->
        parse_rpc_response(operation_info, body_content)
    end
  end

  defp parse_document_response(operation_info, body_content) do
    # For document style, look for the response element
    response_name = get_response_element_name(operation_info)

    case Map.get(body_content, response_name) do
      nil ->
        # Try without operation name wrapper
        {:ok, body_content}

      response_element ->
        {:ok, response_element}
    end
  end

  defp parse_rpc_response(operation_info, body_content) do
    # For RPC style, the response is wrapped in operation response element
    response_name = operation_info.name <> "Response"

    case Map.get(body_content, response_name) do
      nil ->
        {:ok, body_content}

      response_element ->
        {:ok, response_element}
    end
  end

  defp get_response_element_name(operation_info) do
    # Try to determine response element name from operation info
    output_message = operation_info.output.message

    cond do
      String.ends_with?(output_message, "Response") ->
        output_message

      String.ends_with?(output_message, "Output") ->
        output_message

      true ->
        operation_info.name <> "Response"
    end
  end

  defp extract_required_parameters(parts) do
    parts
    |> Enum.filter(fn part -> part[:min_occurs] != "0" end)
    |> Enum.map(fn part -> part.name end)
  end

  defp extract_optional_parameters(parts) do
    parts
    |> Enum.filter(fn part -> part[:min_occurs] == "0" end)
    |> Enum.map(fn part -> part.name end)
  end

  defp extract_return_type(parts) do
    case parts do
      [] -> "void"
      [single_part] -> single_part.type
      multiple_parts -> Enum.map(multiple_parts, & &1.type)
    end
  end
end
