defmodule Lather.Server.DSL do
  @moduledoc """
  Domain Specific Language for defining SOAP operations and types.

  Provides convenient macros for defining SOAP service operations,
  parameter validation, and type definitions.
  """

  @doc """
  Defines a SOAP operation with metadata for WSDL generation.

  ## Example

      soap_operation "GetUser" do
        description "Retrieves a user by ID"

        input do
          parameter "userId", :string, required: true, description: "User identifier"
          parameter "includeDetails", :boolean, required: false, default: false
        end

        output do
          parameter "user", "User", description: "User information"
        end

        soap_action "http://example.com/GetUser"
      end

      def get_user(params) do
        # Implementation
      end
  """
  defmacro soap_operation(name, do: block) do
    snake_case_name = to_snake_case(name)

    quote do
      @current_operation %{
        name: unquote(name),
        function_name: unquote(snake_case_name),
        input: [],
        output: [],
        description: nil,
        soap_action: nil
      }

      unquote(block)

      @soap_operations @current_operation
    end
  end

  @doc """
  Sets the description for the current operation or type.
  Works in both soap_operation and soap_type blocks.
  """
  defmacro description(text) do
    quote do
      current_op = @current_operation
      current_type = @current_type

      cond do
        is_map(current_op) ->
          @current_operation Map.put(current_op, :description, unquote(text))

        is_map(current_type) ->
          @current_type Map.put(current_type, :description, unquote(text))

        true ->
          :ok
      end
    end
  end

  @doc """
  Sets the description for the current type (deprecated, use description/1).
  """
  defmacro type_description(text) do
    quote do
      @current_type Map.put(@current_type, :description, unquote(text))
    end
  end

  @doc """
  Sets the SOAPAction for the current operation.
  """
  defmacro soap_action(action) do
    quote do
      @current_operation Map.put(@current_operation, :soap_action, unquote(action))
    end
  end

  @doc """
  Defines input parameters for the current operation.
  """
  defmacro input(do: block) do
    quote do
      @current_param_list :input
      unquote(block)
    end
  end

  @doc """
  Defines output parameters for the current operation.
  """
  defmacro output(do: block) do
    quote do
      @current_param_list :output
      unquote(block)
    end
  end

  @doc """
  Defines a parameter within an input or output block.
  """
  defmacro parameter(name, type, opts \\ []) do
    quote do
      param = %{
        name: unquote(name),
        type: unquote(type),
        required: Keyword.get(unquote(opts), :required, false),
        description: Keyword.get(unquote(opts), :description),
        default: Keyword.get(unquote(opts), :default),
        min_occurs: Keyword.get(unquote(opts), :min_occurs, 0),
        max_occurs: Keyword.get(unquote(opts), :max_occurs, 1)
      }

      current_params = Map.get(@current_operation, @current_param_list, [])

      @current_operation Map.put(
                           @current_operation,
                           @current_param_list,
                           current_params ++ [param]
                         )
    end
  end

  @doc """
  Defines a complex type for use in operations.

  ## Example

      soap_type "User" do
        description "User information"

        element "id", :string, required: true
        element "name", :string, required: true
        element "email", :string, required: false
        element "created_at", :dateTime, required: true
      end
  """
  defmacro soap_type(name, do: block) do
    quote do
      @current_type %{
        name: unquote(name),
        elements: [],
        description: nil
      }

      unquote(block)

      @soap_types @current_type
    end
  end

  @doc """
  Defines an element within a complex type.
  """
  defmacro element(name, type, opts \\ []) do
    quote do
      element = %{
        name: unquote(name),
        type: unquote(type),
        required: Keyword.get(unquote(opts), :required, false),
        description: Keyword.get(unquote(opts), :description),
        min_occurs: Keyword.get(unquote(opts), :min_occurs, 0),
        max_occurs: Keyword.get(unquote(opts), :max_occurs, 1)
      }

      @current_type Map.update(@current_type, :elements, [element], fn elements ->
                      elements ++ [element]
                    end)
    end
  end

  @doc """
  Defines authentication requirements for operations.

  ## Example

      soap_auth do
        basic_auth realm: "SOAP Service"
        # or
        ws_security required: true
        # or
        custom_auth handler: MyApp.CustomAuth
      end
  """
  defmacro soap_auth(do: block) do
    quote do
      @current_auth %{}
      unquote(block)
      @soap_auth @current_auth
    end
  end

  @doc """
  Configures Basic Authentication.
  """
  defmacro basic_auth(opts \\ []) do
    quote do
      @current_auth Map.put(@current_auth, :basic_auth, %{
                      realm: Keyword.get(unquote(opts), :realm, "SOAP Service"),
                      required: Keyword.get(unquote(opts), :required, true)
                    })
    end
  end

  @doc """
  Configures WS-Security authentication.
  """
  defmacro ws_security(opts \\ []) do
    quote do
      @current_auth Map.put(@current_auth, :ws_security, %{
                      required: Keyword.get(unquote(opts), :required, true),
                      username_token: Keyword.get(unquote(opts), :username_token, true),
                      timestamp: Keyword.get(unquote(opts), :timestamp, false)
                    })
    end
  end

  @doc """
  Configures custom authentication.
  """
  defmacro custom_auth(opts \\ []) do
    quote do
      @current_auth Map.put(@current_auth, :custom_auth, %{
                      handler: Keyword.fetch!(unquote(opts), :handler),
                      options: Keyword.get(unquote(opts), :options, [])
                    })
    end
  end

  # Helper function to convert CamelCase/PascalCase to snake_case
  defp to_snake_case(string) do
    string
    |> String.replace(~r/([a-z\d])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end
end
