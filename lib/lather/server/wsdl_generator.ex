defmodule Lather.Server.WSDLGenerator do
  @moduledoc """
  Generates WSDL files from SOAP service definitions.

  Creates complete WSDL documents with types, messages, port types,
  bindings, and service definitions based on the service module metadata.
  """

  @doc """
  Generates a complete WSDL document for a SOAP service.
  """
  def generate(service_info, base_url) do
    target_namespace = service_info.target_namespace
    service_name = service_info.name
    endpoint_url = "#{base_url}#{service_name}"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <definitions xmlns="http://schemas.xmlsoap.org/wsdl/"
                 xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
                 xmlns:tns="#{target_namespace}"
                 xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                 targetNamespace="#{target_namespace}">

    #{generate_types(service_info)}

    #{generate_messages(service_info)}

    #{generate_port_type(service_info)}

    #{generate_binding(service_info)}

    #{generate_service(service_info, endpoint_url)}

    </definitions>
    """
  end

  # Generate XSD types section
  defp generate_types(service_info) do
    if Enum.empty?(service_info.types) do
      ""
    else
      """
      <types>
        <xsd:schema targetNamespace="#{service_info.target_namespace}">
      #{Enum.map_join(service_info.types, "\n", &generate_complex_type/1)}
        </xsd:schema>
      </types>
      """
    end
  end

  # Generate a complex type definition
  defp generate_complex_type(type) do
    """
        <xsd:complexType name="#{type.name}">
          <xsd:sequence>
    #{Enum.map_join(type.elements, "\n", &generate_element/1)}
          </xsd:sequence>
        </xsd:complexType>
    """
  end

  # Generate an element definition
  defp generate_element(element) do
    type_attr = map_elixir_type_to_xsd(element.type)
    min_occurs = if element.required, do: "1", else: "0"
    max_occurs = element.max_occurs || "1"

    """
            <xsd:element name="#{element.name}" type="#{type_attr}"
                         minOccurs="#{min_occurs}" maxOccurs="#{max_occurs}"/>
    """
  end

  # Generate messages for all operations
  defp generate_messages(service_info) do
    service_info.operations
    |> Enum.map_join("\n", &generate_operation_messages/1)
  end

  # Generate input and output messages for an operation
  defp generate_operation_messages(operation) do
    """
    <message name="#{operation.name}Request">
    #{Enum.map_join(operation.input, "\n", &generate_message_part/1)}
    </message>

    <message name="#{operation.name}Response">
    #{Enum.map_join(operation.output, "\n", &generate_message_part/1)}
    </message>
    """
  end

  # Generate a message part
  defp generate_message_part(param) do
    type_attr = map_elixir_type_to_xsd(param.type)
    """
      <part name="#{param.name}" type="#{type_attr}"/>
    """
  end

  # Generate port type with operations
  defp generate_port_type(service_info) do
    """
    <portType name="#{service_info.name}PortType">
    #{Enum.map_join(service_info.operations, "\n", &generate_port_operation/1)}
    </portType>
    """
  end

  # Generate a port type operation
  defp generate_port_operation(operation) do
    description = if operation.description do
      "\n      <documentation>#{operation.description}</documentation>"
    else
      ""
    end

    """
      <operation name="#{operation.name}">#{description}
        <input message="tns:#{operation.name}Request"/>
        <output message="tns:#{operation.name}Response"/>
      </operation>
    """
  end

  # Generate SOAP binding
  defp generate_binding(service_info) do
    """
    <binding name="#{service_info.name}Binding" type="tns:#{service_info.name}PortType">
      <soap:binding transport="http://schemas.xmlsoap.org/soap/http"/>
    #{Enum.map_join(service_info.operations, "\n", &generate_binding_operation/1)}
    </binding>
    """
  end

  # Generate a binding operation
  defp generate_binding_operation(operation) do
    soap_action = operation.soap_action || "#{operation.name}"

    """
      <operation name="#{operation.name}">
        <soap:operation soapAction="#{soap_action}"/>
        <input>
          <soap:body use="literal"/>
        </input>
        <output>
          <soap:body use="literal"/>
        </output>
      </operation>
    """
  end

  # Generate service definition
  defp generate_service(service_info, endpoint_url) do
    """
    <service name="#{service_info.name}">
      <port name="#{service_info.name}Port" binding="tns:#{service_info.name}Binding">
        <soap:address location="#{endpoint_url}"/>
      </port>
    </service>
    """
  end

  # Map Elixir/internal types to XSD types
  defp map_elixir_type_to_xsd(:string), do: "xsd:string"
  defp map_elixir_type_to_xsd(:int), do: "xsd:int"
  defp map_elixir_type_to_xsd(:integer), do: "xsd:int"
  defp map_elixir_type_to_xsd(:boolean), do: "xsd:boolean"
  defp map_elixir_type_to_xsd(:decimal), do: "xsd:decimal"
  defp map_elixir_type_to_xsd(:float), do: "xsd:float"
  defp map_elixir_type_to_xsd(:dateTime), do: "xsd:dateTime"
  defp map_elixir_type_to_xsd("string"), do: "xsd:string"
  defp map_elixir_type_to_xsd("int"), do: "xsd:int"
  defp map_elixir_type_to_xsd("integer"), do: "xsd:int"
  defp map_elixir_type_to_xsd("boolean"), do: "xsd:boolean"
  defp map_elixir_type_to_xsd("decimal"), do: "xsd:decimal"
  defp map_elixir_type_to_xsd("float"), do: "xsd:float"
  defp map_elixir_type_to_xsd("dateTime"), do: "xsd:dateTime"
  defp map_elixir_type_to_xsd(type) when is_binary(type), do: "tns:#{type}"
  defp map_elixir_type_to_xsd(type), do: "tns:#{type}"
end
