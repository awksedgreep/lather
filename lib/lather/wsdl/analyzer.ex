defmodule Lather.Wsdl.Analyzer do
  @moduledoc """
  WSDL analysis utilities for extracting service information.

  This module provides functions to analyze WSDL documents and extract
  relevant information for generating service clients.
  """

  alias Lather.Xml.Parser

  @doc """
  Analyzes a WSDL document and extracts service information.

  ## Parameters

  * `wsdl_content` - WSDL XML content as a string
  * `options` - Analysis options

  ## Returns

  * `{:ok, service_info}` - Extracted service information
  * `{:error, reason}` - Analysis error

  ## Service Info Structure

      %{
        service_name: "ServiceName",
        target_namespace: "http://example.com/service",
        endpoint: "https://example.com/soap",
        operations: [
          %{
            name: "operation_name",
            input: %{message: "InputMessage", parts: [...]},
            output: %{message: "OutputMessage", parts: [...]},
            soap_action: "http://example.com/action"
          }
        ],
        types: [...],
        authentication: %{type: :basic | :wssecurity | :custom}
      }

  """
  @spec analyze(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def analyze(wsdl_content, options \\ []) do
    with {:ok, parsed_wsdl} <- Parser.parse(wsdl_content),
         {:ok, service_info} <- extract_service_info(parsed_wsdl, options) do
      {:ok, service_info}
    end
  end

  @doc """
  Loads and analyzes a WSDL from a URL or file path.
  """
  @spec load_and_analyze(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def load_and_analyze(source, options \\ []) do
    with {:ok, wsdl_content} <- load_wsdl(source),
         {:ok, service_info} <- analyze(wsdl_content, options) do
      {:ok, service_info}
    end
  end

  @doc """
  Generates a summary report of WSDL analysis.
  """
  @spec generate_report(map()) :: String.t()
  def generate_report(service_info) do
    endpoints_summary =
      case service_info.endpoints do
        [] ->
          "No endpoints found"

        endpoints ->
          Enum.map_join(endpoints, "\n", fn ep ->
            "  - #{ep.name}: #{ep.address.location} (#{ep.address.type})"
          end)
      end

    """
    # WSDL Analysis Report

    ## Service: #{service_info.service_name}
    - **Target Namespace**: #{service_info.target_namespace}
    - **Authentication**: #{service_info.authentication.type}

    ## Endpoints (#{length(service_info.endpoints)})
    #{endpoints_summary}

    ## Operations (#{length(service_info.operations)})
    #{Enum.map_join(service_info.operations, "\n", &format_operation/1)}

    ## Messages (#{length(service_info.messages)})
    #{Enum.map_join(service_info.messages, "\n", &format_message/1)}

    ## Types (#{length(service_info.types)})
    #{Enum.map_join(service_info.types, "\n", &format_type/1)}

    ## Bindings (#{length(service_info.bindings)})
    #{Enum.map_join(service_info.bindings, "\n", &format_binding/1)}

    ## Port Types (#{length(service_info.port_types)})
    #{Enum.map_join(service_info.port_types, "\n", &format_port_type/1)}

    ## Namespaces
    #{Enum.map_join(service_info.namespaces, "\n", fn {prefix, uri} -> "  - #{prefix}: #{uri}" end)}
    """
  end

  # Private functions

  defp load_wsdl("http" <> _ = url) do
    # Load WSDL from URL using Finch directly
    try do
      request = Finch.build(:get, url)

      case Finch.request(request, Lather.Finch) do
        {:ok, %Finch.Response{status: 200, body: content}} -> {:ok, content}
        {:ok, %Finch.Response{status: status}} -> {:error, {:http_error, status}}
        {:error, reason} -> {:error, {:transport_error, reason}}
      end
    rescue
      error ->
        {:error, {:transport_error, error}}
    catch
      :exit, reason ->
        {:error, {:transport_error, reason}}
    end
  end

  defp load_wsdl(file_path) do
    # Load WSDL from file
    case File.read(file_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  def extract_service_info(parsed_wsdl, _options) do
    # Extract comprehensive service information
    service_info = %{
      service_name: extract_service_name(parsed_wsdl),
      target_namespace: extract_target_namespace(parsed_wsdl),
      endpoints: extract_endpoints(parsed_wsdl),
      operations: extract_operations(parsed_wsdl),
      messages: extract_messages(parsed_wsdl),
      types: extract_types(parsed_wsdl),
      bindings: extract_bindings(parsed_wsdl),
      port_types: extract_port_types(parsed_wsdl),
      authentication: detect_authentication(parsed_wsdl),
      namespaces: extract_namespaces(parsed_wsdl),
      soap_version: detect_soap_version(parsed_wsdl)
    }

    {:ok, service_info}
  end

  defp extract_service_name(parsed_wsdl) do
    # Extract service name from WSDL (handle both with and without namespace prefix)
    services =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:service"]) ||
        get_in(parsed_wsdl, ["definitions", "service"])

    case services do
      services when is_list(services) ->
        # Multiple services - get name from first service
        case List.first(services) do
          %{"@name" => name} -> name
          _ -> "UnknownService"
        end

      %{"@name" => name} ->
        # Single service
        name

      _ ->
        "UnknownService"
    end
  end

  defp extract_target_namespace(parsed_wsdl) do
    # Extract target namespace (handle both with and without namespace prefix)
    get_in(parsed_wsdl, ["wsdl:definitions", "@targetNamespace"]) ||
      get_in(parsed_wsdl, ["definitions", "@targetNamespace"]) ||
      ""
  end

  defp extract_endpoints(parsed_wsdl) do
    # Extract all service endpoints (handle both with and without namespace prefix)
    services =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:service"]) ||
        get_in(parsed_wsdl, ["definitions", "service"]) || []

    case services do
      services when is_list(services) ->
        Enum.flat_map(services, &extract_service_endpoints/1)

      single_service ->
        extract_service_endpoints(single_service)
    end
  end

  defp extract_service_endpoints(service) do
    ports = service["wsdl:port"] || service["port"] || []

    case ports do
      ports when is_list(ports) ->
        Enum.map(ports, &parse_port/1)

      single_port ->
        [parse_port(single_port)]
    end
  end

  defp parse_port(port) do
    %{
      name: port["@name"] || "unknown",
      binding: port["@binding"] || "",
      address: get_address_from_port(port)
    }
  end

  defp get_address_from_port(port) do
    # Handle different address types (SOAP, HTTP, etc.)
    cond do
      address = port["soap:address"] || port["soap12:address"] || port["address"] ->
        %{
          type: :soap,
          location: address["@location"] || ""
        }

      http_address = port["http:address"] ->
        %{
          type: :http,
          location: http_address["@location"] || ""
        }

      true ->
        %{type: :unknown, location: ""}
    end
  end

  defp extract_messages(parsed_wsdl) do
    # Extract message definitions (handle both with and without namespace prefix)
    messages =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:message"]) ||
        get_in(parsed_wsdl, ["definitions", "message"]) || []

    case messages do
      messages when is_list(messages) ->
        Enum.map(messages, &parse_message/1)

      single_message ->
        [parse_message(single_message)]
    end
  end

  defp parse_message(message) do
    parts = message["wsdl:part"] || message["part"] || []

    parsed_parts =
      case parts do
        parts when is_list(parts) ->
          Enum.map(parts, &parse_message_part/1)

        single_part ->
          [parse_message_part(single_part)]
      end

    %{
      name: message["@name"] || "unknown",
      parts: parsed_parts
    }
  end

  defp parse_message_part(part) do
    %{
      name: part["@name"] || "unknown",
      type: part["@type"] || part["@element"] || "",
      element: part["@element"]
    }
  end

  defp extract_bindings(parsed_wsdl) do
    # Extract binding definitions (handle both with and without namespace prefix)
    bindings =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:binding"]) ||
        get_in(parsed_wsdl, ["definitions", "binding"]) || []

    case bindings do
      bindings when is_list(bindings) ->
        Enum.map(bindings, &parse_binding/1)

      single_binding ->
        [parse_binding(single_binding)]
    end
  end

  defp parse_binding(binding) do
    operations = binding["wsdl:operation"] || binding["operation"] || []

    parsed_operations =
      case operations do
        operations when is_list(operations) ->
          Enum.map(operations, &parse_binding_operation/1)

        single_operation ->
          [parse_binding_operation(single_operation)]
      end

    binding_style = extract_binding_style(binding)

    # Add binding style to each operation for easy access
    operations_with_style =
      Enum.map(parsed_operations, fn op ->
        Map.put(op, :binding_style, binding_style)
      end)

    %{
      name: binding["@name"] || "unknown",
      type: binding["@type"] || "",
      transport: extract_binding_transport(binding),
      style: binding_style,
      operations: operations_with_style
    }
  end

  defp parse_binding_operation(operation) do
    # Handle both SOAP 1.1 and SOAP 1.2 operations
    soap_operation =
      operation["soap:operation"] || operation["soap12:operation"] || operation["operation"]

    %{
      name: operation["@name"] || "unknown",
      soap_action: if(soap_operation, do: soap_operation["@soapAction"], else: ""),
      input: parse_binding_io(operation["wsdl:input"] || operation["input"]),
      output: parse_binding_io(operation["wsdl:output"] || operation["output"])
    }
  end

  defp parse_binding_io(message) when is_map(message) do
    soap_body = message["soap:body"] || message["body"]

    %{
      use: if(soap_body, do: soap_body["@use"], else: "literal"),
      encoding_style: if(soap_body, do: soap_body["@encodingStyle"], else: ""),
      namespace: if(soap_body, do: soap_body["@namespace"], else: "")
    }
  end

  defp parse_binding_io(_), do: %{}

  defp extract_binding_transport(binding) do
    soap_binding = binding["soap:binding"] || binding["binding"]
    if soap_binding, do: soap_binding["@transport"], else: ""
  end

  defp extract_binding_style(binding) do
    # Handle both SOAP 1.1 and SOAP 1.2 bindings
    soap_binding = binding["soap:binding"] || binding["soap12:binding"] || binding["binding"]
    if soap_binding, do: soap_binding["@style"] || "document", else: "document"
  end

  defp extract_port_types(parsed_wsdl) do
    # Extract port type definitions (handle both with and without namespace prefix)
    port_types =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:portType"]) ||
        get_in(parsed_wsdl, ["definitions", "portType"]) || []

    case port_types do
      port_types when is_list(port_types) ->
        Enum.map(port_types, &parse_port_type/1)

      single_port_type ->
        [parse_port_type(single_port_type)]
    end
  end

  defp parse_port_type(port_type) do
    operations = port_type["wsdl:operation"] || port_type["operation"] || []

    parsed_operations =
      case operations do
        operations when is_list(operations) ->
          Enum.map(operations, &parse_port_type_operation/1)

        single_operation ->
          [parse_port_type_operation(single_operation)]
      end

    %{
      name: port_type["@name"] || "unknown",
      operations: parsed_operations
    }
  end

  defp parse_port_type_operation(operation) do
    %{
      name: operation["@name"] || "unknown",
      input: parse_operation_message(operation["wsdl:input"] || operation["input"]),
      output: parse_operation_message(operation["wsdl:output"] || operation["output"]),
      fault: parse_operation_faults(operation["wsdl:fault"] || operation["fault"]),
      documentation: extract_documentation(operation)
    }
  end

  defp parse_operation_message(message) when is_map(message) do
    %{
      name: message["@name"] || "",
      message: message["@message"] || ""
    }
  end

  defp parse_operation_message(_), do: %{}

  defp parse_operation_faults(faults) when is_list(faults) do
    Enum.map(faults, &parse_operation_fault/1)
  end

  defp parse_operation_faults(fault) when is_map(fault) do
    [parse_operation_fault(fault)]
  end

  defp parse_operation_faults(_), do: []

  defp parse_operation_fault(fault) do
    %{
      name: fault["@name"] || "unknown",
      message: fault["@message"] || ""
    }
  end

  defp extract_documentation(element) do
    # Check for both namespaced and non-namespaced documentation
    doc = element["wsdl:documentation"] || element["documentation"]

    cond do
      is_binary(doc) -> doc
      is_map(doc) -> doc["#text"] || ""
      true -> ""
    end
  end

  defp extract_namespaces(parsed_wsdl) do
    # Extract all namespace declarations (handle both with and without namespace prefix)
    definitions =
      get_in(parsed_wsdl, ["wsdl:definitions"]) ||
        get_in(parsed_wsdl, ["definitions"]) || %{}

    definitions
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "@xmlns") end)
    |> Enum.into(%{}, fn {key, value} ->
      namespace_key =
        case key do
          "@xmlns" -> "default"
          "@xmlns:" <> prefix -> prefix
          key -> key
        end

      {namespace_key, value}
    end)
  end

  defp extract_operations(parsed_wsdl) do
    # Extract comprehensive operation information by combining port types and bindings
    port_types = extract_port_types(parsed_wsdl)
    bindings = extract_bindings(parsed_wsdl)
    messages = extract_messages(parsed_wsdl)

    # Combine information from different WSDL sections
    Enum.flat_map(port_types, fn port_type ->
      Enum.map(port_type.operations, fn operation ->
        binding_info = find_binding_operation(bindings, port_type.name, operation.name)
        input_message = find_message(messages, operation.input.message)
        output_message = find_message(messages, operation.output.message)

        %{
          name: operation.name,
          port_type: port_type.name,
          soap_action: get_soap_action(binding_info),
          style: get_operation_style(binding_info),
          input: %{
            name: operation.input.name,
            message: operation.input.message,
            parts: if(input_message, do: input_message.parts, else: []),
            use: get_message_use(binding_info, :input)
          },
          output: %{
            name: operation.output.name,
            message: operation.output.message,
            parts: if(output_message, do: output_message.parts, else: []),
            use: get_message_use(binding_info, :output)
          },
          faults: operation.fault,
          documentation: operation.documentation
        }
      end)
    end)
  end

  defp find_binding_operation(bindings, port_type_name, operation_name) do
    binding =
      Enum.find(bindings, fn binding ->
        # Match binding to port type (remove namespace prefix if present)
        binding_type = binding.type |> String.split(":") |> List.last()
        port_type_clean = port_type_name |> String.split(":") |> List.last()
        binding_type == port_type_clean
      end)

    if binding do
      Enum.find(binding.operations, fn op -> op.name == operation_name end)
    end
  end

  defp find_message(messages, message_name) do
    # Remove namespace prefix if present
    clean_name = message_name |> String.split(":") |> List.last()
    Enum.find(messages, fn msg -> msg.name == clean_name end)
  end

  defp get_soap_action(binding_operation) do
    if binding_operation, do: binding_operation.soap_action, else: ""
  end

  defp get_operation_style(binding_operation) do
    # Extract style from binding operation or default to document
    if binding_operation && binding_operation.binding_style do
      binding_operation.binding_style
    else
      "document"
    end
  end

  defp get_message_use(binding_operation, direction) when direction in [:input, :output] do
    if binding_operation do
      message_info = Map.get(binding_operation, direction)
      if message_info, do: message_info.use, else: "literal"
    else
      "literal"
    end
  end

  defp extract_types(parsed_wsdl) do
    # Extract comprehensive type definitions from schema
    schemas = get_schema_elements(parsed_wsdl)

    Enum.flat_map(schemas, fn schema ->
      types = []

      # Extract complex types
      complex_types = schema["complexType"] || []

      complex_list =
        case complex_types do
          types when is_list(types) -> types
          single_type -> [single_type]
        end

      # Extract simple types
      simple_types = schema["simpleType"] || []

      simple_list =
        case simple_types do
          types when is_list(types) -> types
          single_type -> [single_type]
        end

      # Extract elements
      elements = schema["element"] || []

      element_list =
        case elements do
          elems when is_list(elems) -> elems
          single_elem -> [single_elem]
        end

      parsed_complex = Enum.map(complex_list, &parse_complex_type/1)
      parsed_simple = Enum.map(simple_list, &parse_simple_type/1)
      parsed_elements = Enum.map(element_list, &parse_element_type/1)

      types ++ parsed_complex ++ parsed_simple ++ parsed_elements
    end)
  end

  defp get_schema_elements(parsed_wsdl) do
    # Get schemas from types section and imported schemas (handle both with and without namespace prefix)
    types_schemas =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:types", "s:schema"]) ||
        get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:types", "xsd:schema"]) ||
        get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:types", "schema"]) ||
        get_in(parsed_wsdl, ["definitions", "types", "schema"]) || []

    case types_schemas do
      schemas when is_list(schemas) -> schemas
      single_schema -> [single_schema]
    end
  end

  defp parse_complex_type(type_def) do
    %{
      category: :complex_type,
      name: type_def["@name"] || "unknown",
      target_namespace: type_def["@targetNamespace"],
      elements: extract_complex_type_elements(type_def),
      attributes: extract_complex_type_attributes(type_def),
      base_type: extract_base_type(type_def),
      documentation: extract_documentation(type_def)
    }
  end

  defp parse_simple_type(type_def) do
    %{
      category: :simple_type,
      name: type_def["@name"] || "unknown",
      target_namespace: type_def["@targetNamespace"],
      base_type: extract_simple_base_type(type_def),
      restrictions: extract_restrictions(type_def),
      documentation: extract_documentation(type_def)
    }
  end

  defp parse_element_type(element_def) do
    %{
      category: :element,
      name: element_def["@name"] || "unknown",
      type: element_def["@type"],
      min_occurs: element_def["@minOccurs"] || "1",
      max_occurs: element_def["@maxOccurs"] || "1",
      nillable: element_def["@nillable"] == "true",
      documentation: extract_documentation(element_def)
    }
  end

  defp extract_complex_type_elements(type_def) do
    # Extract elements from sequence, choice, or all
    elements = []

    # Check sequence
    elements =
      if sequence = type_def["sequence"] do
        elements ++ extract_sequence_elements(sequence)
      else
        elements
      end

    # Check choice
    elements =
      if choice = type_def["choice"] do
        elements ++ extract_choice_elements(choice)
      else
        elements
      end

    # Check all
    elements =
      if all = type_def["all"] do
        elements ++ extract_all_elements(all)
      else
        elements
      end

    # Check complexContent
    if complex_content = type_def["complexContent"] do
      elements ++ extract_complex_content_elements(complex_content)
    else
      elements
    end
  end

  defp extract_sequence_elements(sequence) do
    elements = sequence["element"] || []

    case elements do
      elements when is_list(elements) ->
        Enum.map(elements, &parse_element_type/1)

      single_element ->
        [parse_element_type(single_element)]
    end
  end

  defp extract_choice_elements(choice) do
    elements = choice["element"] || []

    case elements do
      elements when is_list(elements) ->
        Enum.map(elements, &parse_element_type/1)

      single_element ->
        [parse_element_type(single_element)]
    end
  end

  defp extract_all_elements(all) do
    elements = all["element"] || []

    case elements do
      elements when is_list(elements) ->
        Enum.map(elements, &parse_element_type/1)

      single_element ->
        [parse_element_type(single_element)]
    end
  end

  defp extract_complex_content_elements(complex_content) do
    # Handle extension or restriction
    extension = complex_content["extension"]
    restriction = complex_content["restriction"]

    cond do
      extension -> extract_extension_elements(extension)
      restriction -> extract_restriction_elements(restriction)
      true -> []
    end
  end

  defp extract_extension_elements(extension) do
    sequence = extension["sequence"]
    if sequence, do: extract_sequence_elements(sequence), else: []
  end

  defp extract_restriction_elements(restriction) do
    sequence = restriction["sequence"]
    if sequence, do: extract_sequence_elements(sequence), else: []
  end

  defp extract_complex_type_attributes(type_def) do
    attributes = type_def["attribute"] || []

    case attributes do
      attributes when is_list(attributes) ->
        Enum.map(attributes, &parse_attribute/1)

      single_attribute ->
        [parse_attribute(single_attribute)]
    end
  end

  defp parse_attribute(attr_def) do
    %{
      name: attr_def["@name"] || "unknown",
      type: attr_def["@type"],
      use: attr_def["@use"] || "optional",
      default: attr_def["@default"]
    }
  end

  defp extract_base_type(type_def) do
    # Check for extension or restriction
    complex_content = type_def["complexContent"]
    simple_content = type_def["simpleContent"]

    cond do
      complex_content ->
        extension = complex_content["extension"]
        restriction = complex_content["restriction"]

        cond do
          extension -> extension["@base"]
          restriction -> restriction["@base"]
          true -> nil
        end

      simple_content ->
        extension = simple_content["extension"]
        restriction = simple_content["restriction"]

        cond do
          extension -> extension["@base"]
          restriction -> restriction["@base"]
          true -> nil
        end

      true ->
        nil
    end
  end

  defp extract_simple_base_type(type_def) do
    restriction = type_def["restriction"]
    if restriction, do: restriction["@base"], else: nil
  end

  defp extract_restrictions(type_def) do
    restriction = type_def["restriction"]

    if restriction do
      %{
        base: restriction["@base"],
        enumerations: extract_enumerations(restriction),
        pattern: restriction["pattern"]["@value"],
        min_length: restriction["minLength"]["@value"],
        max_length: restriction["maxLength"]["@value"],
        min_inclusive: restriction["minInclusive"]["@value"],
        max_inclusive: restriction["maxInclusive"]["@value"]
      }
    else
      %{}
    end
  end

  defp extract_enumerations(restriction) do
    enums = restriction["enumeration"] || []

    case enums do
      enums when is_list(enums) ->
        Enum.map(enums, fn enum -> enum["@value"] end)

      single_enum ->
        [single_enum["@value"]]
    end
  end

  defp detect_authentication(parsed_wsdl) do
    # Detect authentication requirements
    cond do
      has_wssecurity_policy?(parsed_wsdl) ->
        %{type: :wssecurity, details: extract_wssecurity_details(parsed_wsdl)}

      has_basic_auth_requirement?(parsed_wsdl) ->
        %{type: :basic, details: %{}}

      true ->
        %{type: :none, details: %{}}
    end
  end

  defp has_wssecurity_policy?(parsed_wsdl) do
    # Check for WS-Security policy in WSDL (handle both with and without namespace prefix)
    # Note: bindings, services, and ports can be lists, so we need to check recursively
    check_for_policy_in_bindings(parsed_wsdl) or
      check_for_policy_in_services(parsed_wsdl) or
      check_for_wssecurity_in_map(parsed_wsdl)
  end

  defp check_for_policy_in_bindings(parsed_wsdl) do
    bindings =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:binding"]) ||
        get_in(parsed_wsdl, ["definitions", "binding"]) || []

    case bindings do
      bindings when is_list(bindings) ->
        Enum.any?(bindings, fn binding ->
          is_map(binding) and Map.has_key?(binding, "Policy")
        end)

      binding when is_map(binding) ->
        Map.has_key?(binding, "Policy")

      _ ->
        false
    end
  end

  defp check_for_policy_in_services(parsed_wsdl) do
    services =
      get_in(parsed_wsdl, ["wsdl:definitions", "wsdl:service"]) ||
        get_in(parsed_wsdl, ["definitions", "service"]) || []

    case services do
      services when is_list(services) ->
        Enum.any?(services, fn service ->
          check_for_policy_in_ports(service)
        end)

      service when is_map(service) ->
        check_for_policy_in_ports(service)

      _ ->
        false
    end
  end

  defp check_for_policy_in_ports(service) when is_map(service) do
    ports = service["wsdl:port"] || service["port"] || []

    case ports do
      ports when is_list(ports) ->
        Enum.any?(ports, fn port ->
          is_map(port) and Map.has_key?(port, "Policy")
        end)

      port when is_map(port) ->
        Map.has_key?(port, "Policy")

      _ ->
        false
    end
  end

  defp check_for_policy_in_ports(_), do: false

  defp check_for_wssecurity_in_map(data) when is_map(data) do
    Enum.any?(data, fn {k, v} ->
      (is_binary(k) and
         (String.contains?(k, "wssecurity") or String.contains?(k, "UsernameToken"))) or
        (is_binary(v) and
           (String.contains?(v, "wssecurity") or String.contains?(v, "UsernameToken"))) or
        check_for_wssecurity_in_map(v)
    end)
  end

  defp check_for_wssecurity_in_map(data) when is_list(data) do
    Enum.any?(data, &check_for_wssecurity_in_map/1)
  end

  defp check_for_wssecurity_in_map(data) when is_binary(data) do
    String.contains?(data, "wssecurity") or String.contains?(data, "UsernameToken")
  end

  defp check_for_wssecurity_in_map(_), do: false

  defp has_basic_auth_requirement?(parsed_wsdl) do
    # Check for basic auth requirements in documentation or annotations
    check_for_basic_auth_in_map(parsed_wsdl)
  end

  defp check_for_basic_auth_in_map(data) when is_map(data) do
    Enum.any?(data, fn {k, v} ->
      (is_binary(k) and
         (String.contains?(k, "BasicAuth") or String.contains?(k, "basic-auth") or
            String.contains?(k, "HTTP_BASIC"))) or
        (is_binary(v) and
           (String.contains?(v, "BasicAuth") or String.contains?(v, "basic-auth") or
              String.contains?(v, "HTTP_BASIC"))) or
        check_for_basic_auth_in_map(v)
    end)
  end

  defp check_for_basic_auth_in_map(data) when is_list(data) do
    Enum.any?(data, &check_for_basic_auth_in_map/1)
  end

  defp check_for_basic_auth_in_map(data) when is_binary(data) do
    String.contains?(data, "BasicAuth") or
      String.contains?(data, "basic-auth") or
      String.contains?(data, "HTTP_BASIC")
  end

  defp check_for_basic_auth_in_map(_), do: false

  defp extract_wssecurity_details(_parsed_wsdl) do
    %{}
  end

  defp format_operation(operation) do
    "- **#{operation.name}**: #{operation.input.message} → #{operation.output.message} (SOAPAction: \"#{operation.soap_action}\")"
  end

  defp format_message(message) do
    parts_summary =
      case message.parts do
        [] -> "no parts"
        parts -> "#{length(parts)} parts: #{Enum.map_join(parts, ", ", & &1.name)}"
      end

    "- **#{message.name}**: #{parts_summary}"
  end

  defp format_binding(binding) do
    "- **#{binding.name}**: #{binding.type} (#{binding.transport}, #{binding.style}) - #{length(binding.operations)} operations"
  end

  defp format_port_type(port_type) do
    "- **#{port_type.name}**: #{length(port_type.operations)} operations"
  end

  defp format_type(type) do
    case type.category do
      :complex_type -> "- **#{type.name}** (ComplexType): #{length(type.elements)} elements"
      :simple_type -> "- **#{type.name}** (SimpleType): #{type.base_type}"
      :element -> "- **#{type.name}** (Element): #{type.type}"
    end
  end

  defp detect_soap_version(parsed_wsdl) do
    # Check for SOAP 1.2 indicators in the raw WSDL structure
    if has_soap_1_2_elements?(parsed_wsdl) do
      :v1_2
    else
      :v1_1
    end
  end

  defp has_soap_1_2_elements?(data) when is_map(data) do
    # Check for soap12: prefixed keys or xmlns declarations
    # Check values for soap12 namespace URLs
    Enum.any?(Map.keys(data), fn key ->
      String.contains?(key, "soap12:") ||
        (String.contains?(key, "xmlns") && String.contains?(key, "soap12"))
    end) ||
      Enum.any?(Map.values(data), fn value ->
        (is_binary(value) && String.contains?(value, "soap12")) ||
          has_soap_1_2_elements?(value)
      end)
  end

  defp has_soap_1_2_elements?(data) when is_list(data) do
    Enum.any?(data, &has_soap_1_2_elements?/1)
  end

  defp has_soap_1_2_elements?(_), do: false
end
