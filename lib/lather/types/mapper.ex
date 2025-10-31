defmodule Lather.Types.Mapper do
  @moduledoc """
  Dynamic type mapping system for SOAP services.

  This module provides utilities to convert between WSDL XML Schema types
  and Elixir data structures dynamically, allowing the library to work
  with any SOAP service's data types without hardcoded implementations.
  """

  @doc """
  Creates a type mapping context from WSDL analysis.

  ## Parameters

    * `service_info` - Service information from WSDL analysis
    * `options` - Mapping configuration options

  ## Options

    * `:generate_structs` - Whether to generate Elixir structs (default: false)
    * `:struct_module` - Module namespace for generated structs
    * `:type_prefix` - Prefix for generated type names
    * `:namespace_mapping` - Custom namespace to module mapping

  ## Examples

      type_context = Lather.Types.Mapper.create_context(service_info)

      type_context = Lather.Types.Mapper.create_context(
        service_info,
        generate_structs: true,
        struct_module: MyApp.SoapTypes
      )
  """
  @spec create_context(map(), keyword()) :: map()
  def create_context(service_info, options \\ []) do
    generate_structs = Keyword.get(options, :generate_structs, false)
    struct_module = Keyword.get(options, :struct_module, DynamicTypes)
    type_prefix = Keyword.get(options, :type_prefix, "")

    # Build type registry from WSDL types
    type_registry = build_type_registry(service_info.types, service_info.namespaces)

    # Build element registry
    element_registry = build_element_registry(service_info.types)

    # Generate structs if requested
    struct_definitions = if generate_structs do
      generate_struct_definitions(type_registry, struct_module, type_prefix)
    else
      %{}
    end

    %{
      type_registry: type_registry,
      element_registry: element_registry,
      struct_definitions: struct_definitions,
      namespaces: service_info.namespaces,
      target_namespace: service_info.target_namespace,
      options: options
    }
  end

  @doc """
  Converts XML data to Elixir data structures based on type context.

  ## Parameters

    * `xml_data` - Parsed XML data (maps with string keys)
    * `type_name` - The expected type name for the data
    * `type_context` - Type mapping context from create_context/2

  ## Examples

      xml_data = %{"name" => "John", "age" => "30", "active" => "true"}
      {:ok, elixir_data} = Lather.Types.Mapper.xml_to_elixir(
        xml_data,
        "User",
        type_context
      )
      # %{name: "John", age: 30, active: true}
  """
  @spec xml_to_elixir(map(), String.t(), map()) :: {:ok, any()} | {:error, term()}
  def xml_to_elixir(xml_data, type_name, type_context) do
    case Map.get(type_context.type_registry, type_name) do
      nil ->
        # Unknown type, return as-is but convert keys to atoms
        {:ok, convert_keys_to_atoms(xml_data)}

      type_definition ->
        convert_xml_with_type(xml_data, type_definition, type_context)
    end
  end

  @doc """
  Converts Elixir data structures to XML data based on type context.

  ## Parameters

    * `elixir_data` - Elixir data structure
    * `type_name` - The target type name for XML conversion
    * `type_context` - Type mapping context from create_context/2

  ## Examples

      elixir_data = %{name: "John", age: 30, active: true}
      {:ok, xml_data} = Lather.Types.Mapper.elixir_to_xml(
        elixir_data,
        "User",
        type_context
      )
      # %{"name" => "John", "age" => "30", "active" => "true"}
  """
  @spec elixir_to_xml(any(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def elixir_to_xml(elixir_data, type_name, type_context) do
    case Map.get(type_context.type_registry, type_name) do
      nil ->
        # Unknown type, convert as-is but ensure string keys
        {:ok, convert_keys_to_strings(elixir_data)}

      type_definition ->
        convert_elixir_with_type(elixir_data, type_definition, type_context)
    end
  end

  @doc """
  Infers the type of XML data based on the type context.

  ## Parameters

    * `xml_data` - Parsed XML data
    * `type_context` - Type mapping context

  ## Examples

      {:ok, type_name} = Lather.Types.Mapper.infer_type(xml_data, type_context)
      # "User"
  """
  @spec infer_type(map(), map()) :: {:ok, String.t()} | {:error, :type_not_found}
  def infer_type(xml_data, type_context) when is_map(xml_data) do
    # Try to match based on structure
    xml_keys = MapSet.new(Map.keys(xml_data))

    type_match = Enum.find(type_context.type_registry, fn {_type_name, type_def} ->
      case type_def.category do
        :complex_type ->
          element_names = Enum.map(type_def.elements, & &1.name)
          element_set = MapSet.new(element_names)

          # Check if XML keys are a subset of expected elements
          MapSet.subset?(xml_keys, element_set)

        _ ->
          false
      end
    end)

    case type_match do
      {type_name, _type_def} -> {:ok, type_name}
      nil -> {:error, :type_not_found}
    end
  end

  @doc """
  Validates data against a type definition.

  ## Parameters

    * `data` - Data to validate
    * `type_name` - Type name to validate against
    * `type_context` - Type mapping context

  ## Examples

      :ok = Lather.Types.Mapper.validate_type(data, "User", type_context)
      {:error, {:missing_required_field, "name"}} =
        Lather.Types.Mapper.validate_type(%{}, "User", type_context)
  """
  @spec validate_type(any(), String.t(), map()) :: :ok | {:error, term()}
  def validate_type(data, type_name, type_context) do
    case Map.get(type_context.type_registry, type_name) do
      nil ->
        {:error, {:unknown_type, type_name}}

      type_definition ->
        validate_data_with_type(data, type_definition, type_context)
    end
  end

  @doc """
  Gets the definition of a specific type.

  ## Examples

      {:ok, type_def} = Lather.Types.Mapper.get_type_definition("User", type_context)
  """
  @spec get_type_definition(String.t(), map()) :: {:ok, map()} | {:error, :type_not_found}
  def get_type_definition(type_name, type_context) do
    case Map.get(type_context.type_registry, type_name) do
      nil -> {:error, :type_not_found}
      type_def -> {:ok, type_def}
    end
  end

  # Private helper functions

  defp build_type_registry(types, namespaces) do
    Enum.reduce(types, %{}, fn type_def, registry ->
      type_name = resolve_type_name(type_def.name, type_def.target_namespace, namespaces)
      Map.put(registry, type_name, type_def)
    end)
  end

  defp build_element_registry(types) do
    Enum.reduce(types, %{}, fn type_def, registry ->
      case type_def.category do
        :element ->
          Map.put(registry, type_def.name, type_def)

        _ ->
          registry
      end
    end)
  end

  defp resolve_type_name(name, _target_namespace, namespaces) do
    # If name has a prefix, resolve it
    case String.split(name, ":", parts: 2) do
      [prefix, local_name] ->
        case Map.get(namespaces, prefix) do
          nil -> name  # Keep original if prefix not found
          _namespace -> local_name  # Use local name
        end

      [local_name] ->
        local_name
    end
  end

  defp generate_struct_definitions(type_registry, struct_module, type_prefix) do
    Enum.reduce(type_registry, %{}, fn {type_name, type_def}, structs ->
      case type_def.category do
        :complex_type ->
          struct_name = "#{type_prefix}#{type_name}"
          struct_fields = extract_struct_fields(type_def)

          struct_definition = %{
            module: Module.concat(struct_module, struct_name),
            fields: struct_fields,
            type_def: type_def
          }

          Map.put(structs, type_name, struct_definition)

        _ ->
          structs
      end
    end)
  end

  defp extract_struct_fields(type_def) do
    Enum.map(type_def.elements, fn element ->
      field_name = String.to_atom(element.name)
      default_value = get_default_value(element)

      {field_name, default_value}
    end)
  end

  defp get_default_value(element) do
    cond do
      element.min_occurs == "0" -> nil
      String.contains?(element.type || "", "string") -> ""
      String.contains?(element.type || "", "int") -> 0
      String.contains?(element.type || "", "boolean") -> false
      true -> nil
    end
  end

  defp convert_xml_with_type(xml_data, type_definition, type_context) do
    case type_definition.category do
      :complex_type ->
        convert_complex_type_from_xml(xml_data, type_definition, type_context)

      :simple_type ->
        convert_simple_type_from_xml(xml_data, type_definition)

      :element ->
        convert_element_from_xml(xml_data, type_definition, type_context)
    end
  end

  defp convert_complex_type_from_xml(xml_data, type_definition, type_context) do
    result = Enum.reduce(type_definition.elements, %{}, fn element, acc ->
      xml_value = Map.get(xml_data, element.name)

      if xml_value do
        elixir_value = convert_element_value_from_xml(xml_value, element, type_context)
        field_name = String.to_atom(element.name)
        Map.put(acc, field_name, elixir_value)
      else
        # Handle optional fields
        if element.min_occurs == "0" do
          acc
        else
          field_name = String.to_atom(element.name)
          Map.put(acc, field_name, nil)
        end
      end
    end)

    {:ok, result}
  end

  defp convert_simple_type_from_xml(xml_data, type_definition) do
    case type_definition.base_type do
      "xsd:string" -> {:ok, to_string(xml_data)}
      "xsd:int" -> {:ok, parse_integer(xml_data)}
      "xsd:boolean" -> {:ok, parse_boolean(xml_data)}
      "xsd:decimal" -> {:ok, parse_decimal(xml_data)}
      "xsd:dateTime" -> {:ok, parse_datetime(xml_data)}
      _ -> {:ok, xml_data}
    end
  end

  defp convert_element_from_xml(xml_data, element_definition, type_context) do
    if element_definition.type do
      # Element has a specific type, recurse with that type
      xml_to_elixir(xml_data, element_definition.type, type_context)
    else
      {:ok, xml_data}
    end
  end

  defp convert_element_value_from_xml(xml_value, element, type_context) do
    cond do
      element.type && Map.has_key?(type_context.type_registry, element.type) ->
        case xml_to_elixir(xml_value, element.type, type_context) do
          {:ok, converted} -> converted
          {:error, _} -> xml_value
        end

      element.max_occurs != "1" ->
        # Handle arrays
        case xml_value do
          values when is_list(values) ->
            Enum.map(values, &convert_element_value_from_xml(&1, element, type_context))

          single_value ->
            [convert_element_value_from_xml(single_value, element, type_context)]
        end

      true ->
        convert_primitive_value(xml_value, element.type)
    end
  end

  defp convert_elixir_with_type(elixir_data, type_definition, type_context) do
    case type_definition.category do
      :complex_type ->
        convert_complex_type_to_xml(elixir_data, type_definition, type_context)

      :simple_type ->
        convert_simple_type_to_xml(elixir_data, type_definition)

      :element ->
        convert_element_to_xml(elixir_data, type_definition, type_context)
    end
  end

  defp convert_complex_type_to_xml(elixir_data, type_definition, type_context) when is_map(elixir_data) do
    result = Enum.reduce(type_definition.elements, %{}, fn element, acc ->
      field_name = String.to_atom(element.name)
      elixir_value = Map.get(elixir_data, field_name)

      if elixir_value do
        xml_value = convert_element_value_to_xml(elixir_value, element, type_context)
        Map.put(acc, element.name, xml_value)
      else
        acc
      end
    end)

    {:ok, result}
  end

  defp convert_simple_type_to_xml(elixir_data, type_definition) do
    case type_definition.base_type do
      "xsd:string" -> {:ok, to_string(elixir_data)}
      "xsd:int" -> {:ok, to_string(elixir_data)}
      "xsd:boolean" -> {:ok, if(elixir_data, do: "true", else: "false")}
      "xsd:decimal" -> {:ok, to_string(elixir_data)}
      "xsd:dateTime" -> {:ok, format_datetime(elixir_data)}
      _ -> {:ok, to_string(elixir_data)}
    end
  end

  defp convert_element_to_xml(elixir_data, element_definition, type_context) do
    if element_definition.type do
      elixir_to_xml(elixir_data, element_definition.type, type_context)
    else
      {:ok, to_string(elixir_data)}
    end
  end

  defp convert_element_value_to_xml(elixir_value, element, type_context) do
    cond do
      element.type && Map.has_key?(type_context.type_registry, element.type) ->
        case elixir_to_xml(elixir_value, element.type, type_context) do
          {:ok, converted} -> converted
          {:error, _} -> to_string(elixir_value)
        end

      element.max_occurs != "1" && is_list(elixir_value) ->
        # Handle arrays
        Enum.map(elixir_value, &convert_element_value_to_xml(&1, element, type_context))

      true ->
        convert_primitive_value_to_xml(elixir_value, element.type)
    end
  end

  defp convert_primitive_value(xml_value, type) do
    case type do
      "xsd:string" -> to_string(xml_value)
      "xsd:int" -> parse_integer(xml_value)
      "xsd:boolean" -> parse_boolean(xml_value)
      "xsd:decimal" -> parse_decimal(xml_value)
      "xsd:dateTime" -> parse_datetime(xml_value)
      _ -> xml_value
    end
  end

  defp convert_primitive_value_to_xml(elixir_value, type) do
    case type do
      "xsd:string" -> to_string(elixir_value)
      "xsd:int" -> to_string(elixir_value)
      "xsd:boolean" -> if(elixir_value, do: "true", else: "false")
      "xsd:decimal" -> to_string(elixir_value)
      "xsd:dateTime" -> format_datetime(elixir_value)
      _ -> to_string(elixir_value)
    end
  end

  defp validate_data_with_type(data, type_definition, type_context) do
    case type_definition.category do
      :complex_type ->
        validate_complex_type(data, type_definition, type_context)

      :simple_type ->
        validate_simple_type(data, type_definition)

      _ ->
        :ok
    end
  end

  defp validate_complex_type(data, type_definition, _type_context) when is_map(data) do
    Enum.reduce_while(type_definition.elements, :ok, fn element, _acc ->
      field_name = String.to_atom(element.name)
      field_value = Map.get(data, field_name)

      cond do
        is_nil(field_value) && element.min_occurs != "0" ->
          {:halt, {:error, {:missing_required_field, element.name}}}

        not is_nil(field_value) ->
          case validate_element_value(field_value, element) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_complex_type(_data, _type_definition, _type_context) do
    {:error, :invalid_data_type}
  end

  defp validate_simple_type(data, type_definition) do
    case type_definition.base_type do
      "xsd:string" when is_binary(data) -> :ok
      "xsd:int" when is_integer(data) -> :ok
      "xsd:boolean" when is_boolean(data) -> :ok
      "xsd:decimal" when is_number(data) -> :ok
      _ -> {:error, {:invalid_type, type_definition.base_type}}
    end
  end

  defp validate_element_value(value, element) do
    cond do
      element.max_occurs != "1" && not is_list(value) ->
        {:error, {:expected_array, element.name}}

      element.max_occurs == "1" && is_list(value) ->
        {:error, {:unexpected_array, element.name}}

      true ->
        :ok
    end
  end

  # Utility functions

  defp convert_keys_to_atoms(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      converted_value = convert_keys_to_atoms(value)
      Map.put(acc, atom_key, converted_value)
    end)
  end

  defp convert_keys_to_atoms(data) when is_list(data) do
    Enum.map(data, &convert_keys_to_atoms/1)
  end

  defp convert_keys_to_atoms(data), do: data

  defp convert_keys_to_strings(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      string_key = to_string(key)
      converted_value = convert_keys_to_strings(value)
      Map.put(acc, string_key, converted_value)
    end)
  end

  defp convert_keys_to_strings(data) when is_list(data) do
    Enum.map(data, &convert_keys_to_strings/1)
  end

  defp convert_keys_to_strings(data), do: data

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: 0

  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean(_), do: false

  defp parse_decimal(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp parse_decimal(value) when is_number(value), do: value
  defp parse_decimal(_), do: 0.0

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(%DateTime{} = datetime), do: datetime
  defp parse_datetime(_), do: nil

  defp format_datetime(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp format_datetime(value) when is_binary(value), do: value
  defp format_datetime(_), do: ""
end
