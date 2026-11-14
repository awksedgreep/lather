defmodule Lather.Client.Generator do
  @moduledoc """
  Generates Elixir client modules from WSDL service definitions.

  The generated module wraps `Lather.DynamicClient` with one function per
  WSDL operation, so callers get named, documented functions instead of
  string-keyed parameter maps:

      wsdl = File.read!("users.wsdl")
      {:ok, service_info} = Lather.Wsdl.Analyzer.analyze(wsdl)
      source = Lather.Client.Generator.generate(service_info,
        module: "MyApp.UserClient",
        wsdl_url: "https://example.com/users?wsdl"
      )

  The result is Elixir source code as a string. Complex XSD types become
  structs under `ClientName.TypeName`.

  ## Options

    - `:module` - name of the generated module (default: `<ServiceName>Client`)
    - `:wsdl_url` - URL the generated client loads the WSDL from

  Use `Mix.Tasks.Lather.Client` for a command-line entry point.
  """

  @elixir_keywords ~w(do end fn nil true false if unless case cond for with when in and or not
    after rescue catch else begin)

  @doc """
  Returns the source of a client module generated from analyzed service info.
  """
  def generate(service_info, opts \\ []) do
    module = opts[:module] || default_module(Map.get(service_info, :service_name))
    wsdl_url = opts[:wsdl_url] || ""

    operations = Map.get(service_info, :operations, [])
    types = Map.get(service_info, :types, [])

    source = """
    defmodule #{module} do
      @moduledoc \"\"\"
      Generated Lather client for the #{Map.get(service_info, :service_name)} SOAP service.

      Create a client with #{module}.new(), then call one of the operation
      functions. Operations: #{operation_index(operations)}.
      \"\"\"

      alias Lather.DynamicClient

      @wsdl_url #{inspect(wsdl_url)}

      @doc "Creates a dynamic client connected to the service."
      def new(opts \\\\ []) do
        case DynamicClient.new(@wsdl_url, opts) do
          {:ok, client} -> client
          {:error, reason} -> raise "Could not connect to service: " <> inspect(reason)
        end
      end

    #{Enum.map_join(operations, "\n", &operation_function(&1, module))}
    #{type_structs(types)}

      defp drop_nil(params) do
        params
        |> Map.to_list()
        |> Enum.reject(fn {_, value} -> value == nil end)
        |> Map.new()
      end
    end
    """

    Code.format_string!(source) |> IO.iodata_to_binary()
  end

  defp operation_index(operations) do
    operations |> Enum.map(&(&1.name <> " (#{function_name(&1.name)}/2+)")) |> Enum.join(", ")
  end

  defp operation_function(operation, module) do
    name = function_name(operation.name)
    parts = Map.get(operation, :input, %{}) |> Map.get(:parts, [])

    args =
      parts
      |> Enum.map(fn part ->
        arg_name(part.name)
      end)

    args_string = (["client" | args] ++ ["opts \\\\ []"]) |> Enum.join(", ")

    params =
      parts
      |> Enum.map(fn part ->
        "#{inspect(part.name)} => #{arg_name(part.name)}"
      end)
      |> Enum.join(", ")

    doc_params =
      parts
      |> Enum.map(fn part ->
        type = part.type || "any"
        "    * `#{arg_name(part.name)}` (#{type})"
      end)
      |> Enum.join("\n")

    doc =
      if parts == [] do
        "Calls #{operation.name}."
      else
        "Calls #{operation.name}.\n\n## Parameters\n#{doc_params}"
      end

    """

      @doc \"\"\"
      #{doc}

      Example:

          {:ok, result} = #{module}.#{name}(client#{example_args(parts)})
      \"\"\"
      def #{name}(#{args_string}) do
        params = %{#{params}}
        DynamicClient.call(client, #{inspect(operation.name)}, drop_nil(params), opts)
      end
    """
  end

  defp example_args(parts) do
    Enum.map(parts, fn _ ->
      ", \"...\""
    end)
    |> Enum.join("")
  end

  defp type_structs(types) do
    types
    |> Enum.filter(&(&1.category == :complex_type))
    |> Enum.map_join("\n", fn type ->
      fields =
        type.elements
        |> Enum.map(fn element ->
          ":" <> safe_atom_name(element.name)
        end)
        |> Enum.join(", ")

      """

        defmodule #{module_part(type.name)} do
          @moduledoc \"\"\"
          Struct for the WSDL type #{type.name}.
          \"\"\"
          defstruct [#{fields}]
        end
      """
    end)
  end

  defp default_module(service_name) do
    name = module_part(service_name || "Service")
    if String.ends_with?(name, "Client"), do: name, else: name <> "Client"
  end

  defp module_part(name) do
    name
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_]+/, "_")
    |> String.split("_")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn token ->
      if String.match?(token, ~r/[A-Z]/) do
        token
      else
        String.capitalize(token)
      end
    end)
    |> Enum.join("")
  end

  defp function_name(operation_name) do
    name = Macro.underscore(operation_name)

    if name == "" or String.starts_with?(name, "_") do
      "operation"
    else
      keyword_guard(name)
    end
  end

  defp arg_name(name) do
    name
    |> to_string()
    |> Macro.underscore()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> keyword_guard()
  end

  defp safe_atom_name(name) do
    name |> to_string() |> Macro.underscore() |> String.replace(~r/[^a-z0-9_]+/, "_")
  end

  defp keyword_guard(name) do
    if name in @elixir_keywords do
      "param_" <> name
    else
      name
    end
  end
end
