defmodule Lather.Types.Generator do
  @moduledoc """
  Runtime struct generation for SOAP types.

  This module provides utilities to dynamically generate Elixir structs
  from WSDL type definitions at runtime, enabling type-safe interactions
  with SOAP services.
  """

  @doc """
  Generates Elixir structs at runtime for WSDL types.

  ## Parameters

    * `service_info` - Service information from WSDL analysis
    * `options` - Generation options

  ## Options

    * `:module_prefix` - Module prefix for generated structs (default: DynamicTypes)
    * `:exclude_types` - List of type names to exclude from generation
    * `:include_only` - List of type names to include (excludes all others)
    * `:field_naming` - How to handle field names (:snake_case, :camel_case, :preserve)

  ## Examples

      {:ok, generated_modules} = Lather.Types.Generator.generate_structs(service_info)

      {:ok, modules} = Lather.Types.Generator.generate_structs(
        service_info,
        module_prefix: MyApp.SoapTypes,
        field_naming: :snake_case
      )
  """
  @spec generate_structs(map(), keyword()) :: {:ok, [module()]} | {:error, term()}
  def generate_structs(service_info, options \\ []) do
    module_prefix = Keyword.get(options, :module_prefix, DynamicTypes)
    exclude_types = Keyword.get(options, :exclude_types, [])
    include_only = Keyword.get(options, :include_only, nil)
    field_naming = Keyword.get(options, :field_naming, :preserve)

    # Filter types to generate
    types_to_generate = filter_types(service_info.types, include_only, exclude_types)

    # Generate struct modules
    generated_modules = Enum.map(types_to_generate, fn type_def ->
      case type_def.category do
        :complex_type ->
          generate_struct_module(type_def, module_prefix, field_naming)

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)

    {:ok, generated_modules}
  end

  @doc """
  Creates a struct instance from XML data using generated types.

  ## Parameters

    * `xml_data` - Parsed XML data
    * `type_name` - The struct type to create
    * `generated_modules` - Map of generated modules

  ## Examples

      {:ok, user_struct} = Lather.Types.Generator.create_struct_instance(
        %{"name" => "John", "age" => "30"},
        "User",
        generated_modules
      )
      # %DynamicTypes.User{name: "John", age: 30}
  """
  @spec create_struct_instance(map(), String.t(), map()) :: {:ok, struct()} | {:error, term()}
  def create_struct_instance(xml_data, type_name, generated_modules) do
    case Map.get(generated_modules, type_name) do
      nil ->
        {:error, {:struct_not_found, type_name}}

      struct_module ->
        try do
          # Convert XML data to struct
          struct_data = convert_xml_to_struct_data(xml_data, struct_module)
          struct_instance = struct(struct_module, struct_data)
          {:ok, struct_instance}
        rescue
          error -> {:error, {:struct_creation_failed, error}}
        end
    end
  end

  @doc """
  Converts a struct instance to XML data.

  ## Parameters

    * `struct_instance` - The struct to convert
    * `type_context` - Type mapping context

  ## Examples

      xml_data = Lather.Types.Generator.struct_to_xml(user_struct, type_context)
      # %{"name" => "John", "age" => "30"}
  """
  @spec struct_to_xml(struct(), map()) :: map()
  def struct_to_xml(struct_instance, _type_context) do
    struct_instance
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if value != nil do
        xml_key = to_string(key)
        xml_value = convert_value_to_xml(value)
        Map.put(acc, xml_key, xml_value)
      else
        acc
      end
    end)
  end

  @doc """
  Gets the module name for a generated struct type.

  ## Examples

      module_name = Lather.Types.Generator.get_struct_module("User", DynamicTypes)
      # DynamicTypes.User
  """
  @spec get_struct_module(String.t(), module()) :: module()
  def get_struct_module(type_name, module_prefix) do
    Module.concat(module_prefix, type_name)
  end

  @doc """
  Validates if a module was generated for a type.

  ## Examples

      true = Lather.Types.Generator.struct_exists?("User", generated_modules)
      false = Lather.Types.Generator.struct_exists?("NonExistent", generated_modules)
  """
  @spec struct_exists?(String.t(), map()) :: boolean()
  def struct_exists?(type_name, generated_modules) do
    Map.has_key?(generated_modules, type_name)
  end

  # Private helper functions

  defp filter_types(types, include_only, exclude_types) do
    types
    |> Enum.filter(fn type_def ->
      type_name = type_def.name

      cond do
        include_only && type_name not in include_only ->
          false

        type_name in exclude_types ->
          false

        type_def.category != :complex_type ->
          false

        true ->
          true
      end
    end)
  end

  defp generate_struct_module(type_def, module_prefix, field_naming) do
    struct_name = type_def.name
    module_name = Module.concat(module_prefix, struct_name)

    # Convert type elements to struct fields
    struct_fields = Enum.map(type_def.elements, fn element ->
      field_name = convert_field_name(element.name, field_naming)
      default_value = get_field_default_value(element)
      {field_name, default_value}
    end)

    # Generate the module at runtime
    module_ast = quote do
      defstruct unquote(struct_fields)

      @type t :: %__MODULE__{
        unquote_splicing(
          Enum.map(struct_fields, fn {field_name, _default} ->
            {field_name, quote(do: any())}
          end)
        )
      }

      def __type_definition__, do: unquote(Macro.escape(type_def))
    end

    # Define the module
    Module.create(module_name, module_ast, Macro.Env.location(__ENV__))

    {struct_name, module_name}
  end

  defp convert_field_name(name, :snake_case) do
    name
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp convert_field_name(name, :camel_case) do
    name
    |> Macro.camelize()
    |> String.to_atom()
  end

  defp convert_field_name(name, :preserve) do
    String.to_atom(name)
  end

  defp get_field_default_value(element) do
    cond do
      element.min_occurs == "0" ->
        nil

      element.max_occurs != "1" ->
        []

      String.contains?(element.type || "", "string") ->
        ""

      String.contains?(element.type || "", "int") ->
        0

      String.contains?(element.type || "", "boolean") ->
        false

      String.contains?(element.type || "", "decimal") ->
        0.0

      true ->
        nil
    end
  end

  defp convert_xml_to_struct_data(xml_data, struct_module) do
    type_def = struct_module.__type_definition__()

    Enum.reduce(type_def.elements, %{}, fn element, acc ->
      xml_value = Map.get(xml_data, element.name)

      if xml_value do
        field_name = String.to_atom(element.name)
        converted_value = convert_xml_value(xml_value, element)
        Map.put(acc, field_name, converted_value)
      else
        acc
      end
    end)
  end

  defp convert_xml_value(xml_value, element) do
    case element.type do
      type when type in ["xsd:string", "xs:string"] ->
        to_string(xml_value)

      type when type in ["xsd:int", "xs:int", "xsd:integer", "xs:integer"] ->
        parse_integer(xml_value)

      type when type in ["xsd:boolean", "xs:boolean"] ->
        parse_boolean(xml_value)

      type when type in ["xsd:decimal", "xs:decimal", "xsd:double", "xs:double"] ->
        parse_decimal(xml_value)

      type when type in ["xsd:dateTime", "xs:dateTime"] ->
        parse_datetime(xml_value)

      _ ->
        xml_value
    end
  end

  defp convert_value_to_xml(value) when is_binary(value), do: value
  defp convert_value_to_xml(value) when is_number(value), do: to_string(value)
  defp convert_value_to_xml(true), do: "true"
  defp convert_value_to_xml(false), do: "false"
  defp convert_value_to_xml(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp convert_value_to_xml(value) when is_list(value), do: Enum.map(value, &convert_value_to_xml/1)
  defp convert_value_to_xml(value), do: to_string(value)

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
end
