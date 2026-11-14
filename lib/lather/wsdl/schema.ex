defmodule Lather.Wsdl.Schema do
  @moduledoc """
  Generates XSD schemas from Lather service modules and validates
  operation parameters against them on the client side.

  ## Examples

      iex> schema = Lather.Wsdl.Schema.from_operations([%{name: "Echo", input: [%{name: "message", type: :string, required: true, default: nil, enum: nil, min: nil, max: nil, pattern: nil}]}])
      iex> schema =~ "<xs:element name=\\"message\\" type=\\"xs:string\\" use=\\"required\\"/>"
      true
  """

  @xsd_types %{
    string: "xs:string",
    integer: "xs:integer",
    float: "xs:double",
    boolean: "xs:boolean",
    datetime: "xs:dateTime"
  }

  def from_operations(operations) do
    elements =
      operations
      |> Enum.map(&operation_elements/1)
      |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
    #{elements}
    </xs:schema>
    """
  end

  def validate(service_module, operation_name, params) do
    operations = service_module.__soap_operations__()

    operation =
      Enum.find(operations, fn op ->
        String.downcase(op.name) == String.downcase(operation_name)
      end)

    case operation do
      nil ->
        {:error, ["unknown operation: #{operation_name}"]}

      op ->
        case Lather.Server.validate_param_types(params, op) do
          {:ok, validated} -> {:ok, validated}
          {:error, reason} -> {:error, [reason]}
        end
    end
  end

  defp operation_elements(op) do
    body =
      op.input
      |> Enum.map(&element_line/1)
      |> Enum.join("  ")

    "  <xs:element name=\"#{op.name}\">\n    <xs:complexType>\n      <xs:sequence>\n#{body}\n      </xs:sequence>\n    </xs:complexType>\n  </xs:element>"
  end

  defp element_line(param) do
    type = Map.get(@xsd_types, param.type, "xs:string")
    attrs = attribute_attrs(param)

    "        <xs:element name=\"#{param.name}\" type=\"#{type}\"#{attrs}/>"
  end

  defp attribute_attrs(param) do
    parts = []

    parts =
      if param.required do
        parts ++ [" use=\"required\""]
      else
        parts
      end

    parts =
      if param.default != nil do
        parts ++ [" default=\"#{param.default}\""]
      else
        parts
      end

    parts =
      if param.pattern do
        parts ++ [" pattern=\"#{param.pattern}\""]
      else
        parts
      end

    parts =
      if param.min != nil or param.max != nil do
        parts ++ [" nillable=\"false\""]
      else
        parts
      end

    Enum.join(parts, "")
  end
end
