defmodule Lather.Soap.Body do
  @moduledoc """
  SOAP body utilities.

  Provides functionality for creating and managing SOAP body content,
  including parameter serialization and response parsing.
  """

  alias Lather.Xml.Builder

  @doc """
  Creates a SOAP body element for the given operation and parameters.

  ## Parameters

  * `operation` - Operation name (atom or string)
  * `params` - Operation parameters (map)
  * `options` - Body options

  ## Options

  * `:namespace` - Target namespace for the operation
  * `:namespace_prefix` - Prefix for the target namespace

  ## Examples

      iex> Body.create(:get_user, %{id: 123}, namespace: "http://example.com")
      %{
        "get_user" => %{
          "@xmlns" => "http://example.com",
          "id" => 123
        }
      }

  """
  @spec create(atom() | String.t(), map(), keyword()) :: map()
  def create(operation, params, options \\ []) do
    operation_name = to_string(operation)
    namespace = Keyword.get(options, :namespace)
    namespace_prefix = Keyword.get(options, :namespace_prefix)

    operation_element = build_operation_element(operation_name, params, namespace, namespace_prefix)
    operation_element
  end

  @doc """
  Serializes Elixir data structures to XML-compatible format.

  Handles various Elixir types and converts them to XML-safe representations.
  """
  @spec serialize_params(any()) :: any()
  def serialize_params(params) when is_map(params) do
    Enum.into(params, %{}, fn {key, value} ->
      {to_string(key), serialize_params(value)}
    end)
  end

  def serialize_params(params) when is_list(params) do
    Enum.map(params, &serialize_params/1)
  end

  def serialize_params(params) when is_atom(params) and params != nil do
    to_string(params)
  end

  def serialize_params(params) when is_boolean(params) do
    to_string(params)
  end

  def serialize_params(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  def serialize_params(%Date{} = date) do
    Date.to_iso8601(date)
  end

  def serialize_params(%Time{} = time) do
    Time.to_iso8601(time)
  end

  def serialize_params(params) when is_binary(params) do
    Builder.escape_text(params)
  end

  def serialize_params(params), do: to_string(params)

  @doc """
  Validates parameters against expected types and constraints.

  ## Parameters

  * `params` - Parameters to validate
  * `schema` - Validation schema (map)

  ## Schema Format

  The schema is a map where keys are parameter names and values are validation rules:

      %{
        "id" => [:required, :integer],
        "name" => [:required, :string, {:max_length, 50}],
        "email" => [:optional, :string, :email]
      }

  """
  @spec validate_params(map(), map()) :: :ok | {:error, [String.t()]}
  def validate_params(params, schema) do
    errors = Enum.reduce(schema, [], fn {param_name, rules}, acc ->
      case validate_param(params[param_name], param_name, rules) do
        :ok -> acc
        {:error, error} -> [error | acc]
      end
    end)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # Private functions

  defp build_operation_element(operation_name, params, namespace, namespace_prefix) do
    serialized_params = serialize_params(params)

    element_name = if namespace_prefix do
      "#{namespace_prefix}:#{operation_name}"
    else
      operation_name
    end

    element_content = if namespace do
      Map.put(serialized_params, "@xmlns", namespace)
    else
      serialized_params
    end

    %{element_name => element_content}
  end

  defp validate_param(value, param_name, rules) do
    case Enum.reduce_while(rules, :ok, &apply_validation_rule(&1, value, param_name, &2)) do
      :ok -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp apply_validation_rule(:required, nil, param_name, _acc) do
    {:halt, {:error, "#{param_name} is required"}}
  end

  defp apply_validation_rule(:required, _value, _param_name, acc) do
    {:cont, acc}
  end

  defp apply_validation_rule(:optional, _value, _param_name, acc) do
    {:cont, acc}
  end

  defp apply_validation_rule(:integer, value, param_name, _acc) when not is_integer(value) do
    {:halt, {:error, "#{param_name} must be an integer"}}
  end

  defp apply_validation_rule(:string, value, param_name, _acc) when not is_binary(value) do
    {:halt, {:error, "#{param_name} must be a string"}}
  end

  defp apply_validation_rule({:max_length, max}, value, param_name, _acc)
       when is_binary(value) and byte_size(value) > max do
    {:halt, {:error, "#{param_name} must be at most #{max} characters"}}
  end

  defp apply_validation_rule(_rule, _value, _param_name, acc) do
    {:cont, acc}
  end
end
