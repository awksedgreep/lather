defmodule Lather.Server do
  @moduledoc """
  SOAP Server implementation for Lather.

  Provides a framework for building SOAP web services in Elixir with:
  - Automatic WSDL generation from module definitions
  - Request/response handling and validation
  - Authentication and authorization support
  - Phoenix/Plug integration
  - Comprehensive error handling with SOAP faults

  ## Usage

  Define a SOAP service module:

      defmodule MyApp.UserService do
        use Lather.Server

        @namespace "http://myapp.com/users"
        @service_name "UserService"

        @soap_operation %{
          name: "GetUser",
          input: [%{name: "userId", type: "string", required: true}],
          output: [%{name: "user", type: "User"}]
        }
        def get_user(%{"userId" => user_id}) do
          case fetch_user(user_id) do
            {:ok, user} -> {:ok, %{"user" => user}}
            {:error, :not_found} -> soap_fault("Client", "User not found")
          end
        end

        defp fetch_user(id), do: {:ok, %{"id" => id, "name" => "John Doe"}}
      end

  Then mount it in your Phoenix router or Plug application:

      # In Phoenix router
      scope "/soap" do
        pipe_through :api
        post "/users", Lather.Server.Plug, service: MyApp.UserService
      end

      # Or as a standalone Plug
      plug Lather.Server.Plug, service: MyApp.UserService
  """

  @doc """
  Macro for creating SOAP service modules.
  """
  defmacro __using__(opts \\ []) do
    quote do
      import Lather.Server
      import Lather.Server.DSL

      @before_compile Lather.Server

      # Service configuration
      Module.register_attribute(__MODULE__, :soap_operations, accumulate: true)
      Module.register_attribute(__MODULE__, :soap_types, accumulate: true)
      Module.register_attribute(__MODULE__, :soap_auth, persist: true)
      Module.register_attribute(__MODULE__, :namespace, persist: true)
      Module.register_attribute(__MODULE__, :service_name, persist: true)
      Module.register_attribute(__MODULE__, :target_namespace, persist: true)

      # Set defaults
      @namespace unquote(opts[:namespace] || "http://tempuri.org/")
      @service_name unquote(opts[:service_name] || to_string(__MODULE__))
      @target_namespace @namespace
    end
  end

  @doc """
  Callback executed before module compilation to generate service metadata.
  """
  defmacro __before_compile__(env) do
    operations = Module.get_attribute(env.module, :soap_operations, [])
    types = Module.get_attribute(env.module, :soap_types, [])
    auth = Module.get_attribute(env.module, :soap_auth, %{})
    namespace = Module.get_attribute(env.module, :namespace)
    service_name = Module.get_attribute(env.module, :service_name)

    quote do
      @doc """
      Returns service metadata for WSDL generation and request routing.
      """
      def __soap_service__ do
        %{
          name: unquote(service_name),
          namespace: unquote(namespace),
          target_namespace: unquote(namespace),
          operations: unquote(Macro.escape(operations)),
          types: unquote(Macro.escape(types)),
          authentication: unquote(Macro.escape(auth)),
          module: __MODULE__
        }
      end

      @doc """
      Lists all available SOAP operations.
      """
      def __soap_operations__ do
        unquote(Macro.escape(operations))
      end

      @doc """
      Gets information about a specific operation.
      """
      def __soap_operation__(name) do
        Enum.find(unquote(Macro.escape(operations)), &(&1.name == name))
      end

      @doc """
      Lists all available SOAP types.
      """
      def __soap_types__ do
        unquote(Macro.escape(types))
      end

      @doc """
      Gets authentication configuration.
      """
      def __soap_auth__ do
        unquote(Macro.escape(auth))
      end
    end
  end

  @doc """
  Creates a SOAP fault response.
  """
  def soap_fault(fault_code, fault_string, detail \\ nil) do
    {:soap_fault,
     %{
       fault_code: fault_code,
       fault_string: fault_string,
       detail: detail
     }}
  end

  @doc """
  Validates that required operation parameters are present.
  """
  def validate_required_params(params, operation) do
    required_params =
      operation.input
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)

    missing = required_params -- Map.keys(params)

    case missing do
      [] ->
        :ok

      missing_params ->
        {:error, "Missing required parameters: #{Enum.join(missing_params, ", ")}"}
    end
  end

  @doc """
  Validates parameter types according to operation definition.
  """
  def validate_param_types(params, operation) do
    Enum.reduce_while(operation.input, :ok, fn param, _acc ->
      case Map.get(params, param.name) do
        nil ->
          if param.required do
            {:halt, {:error, "Missing required parameter: #{param.name}"}}
          else
            {:cont, :ok}
          end

        value ->
          case validate_type(value, param.type) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, "Invalid #{param.name}: #{reason}"}}
          end
      end
    end)
  end

  defp validate_type(value, "string") when is_binary(value), do: :ok
  defp validate_type(value, "int") when is_integer(value), do: :ok
  defp validate_type(value, "boolean") when is_boolean(value), do: :ok
  defp validate_type(value, "decimal") when is_number(value), do: :ok

  defp validate_type(value, "dateTime") do
    case DateTime.from_iso8601(value) do
      {:ok, _, _} -> :ok
      _ -> {:error, "invalid dateTime format"}
    end
  end

  # Allow any for complex types
  defp validate_type(_value, _type), do: :ok

  @doc """
  Formats operation response according to SOAP conventions.
  """
  def format_response(result, operation) do
    case result do
      {:ok, data} ->
        {:ok, %{"#{operation.name}Response" => data}}

      {:soap_fault, fault} ->
        {:soap_fault, fault}

      {:error, reason} ->
        soap_fault("Server", reason)

      data when is_map(data) ->
        {:ok, %{"#{operation.name}Response" => data}}

      _ ->
        {:ok, %{"#{operation.name}Response" => %{"result" => result}}}
    end
  end
end
