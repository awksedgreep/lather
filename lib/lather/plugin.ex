defmodule Lather.Plugin do
  @moduledoc """
  Plugin system for custom request/response behaviors.

  A plugin is a module implementing `Lather.Plugin`. Hooks run around
  each `Lather.DynamicClient.call/4`:

    * `before_request/2` - receives the operation name and options and
      returns adjusted options (e.g. adding headers)
    * `after_response/2` - receives `{:ok, body}` or `{:error, reason}`
      and may transform the result
    * `on_error/2` - receives the error and can log/annotate it

  ## Examples

      defmodule MyPlugin do
        @impl true
        def before_request(operation, options) do
          {:ok, Keyword.put(options, :headers, Keyword.get(options, :headers, []) ++ [{"X-Plugin", operation}])}
        end

        @impl true
        def after_response(_operation, result), do: {:ok, result}

        @impl true
        def on_error(_operation, error), do: {:ok, error}
      end

      client = Lather.DynamicClient.new(wsdl_url, plugins: [MyPlugin])
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

  """

  @callback before_request(String.t(), keyword()) :: {:ok, keyword()} | {:error, term()}
  @callback after_response(String.t(), {:ok, map()} | {:error, term()}) ::
              {:ok, map()} | {:error, term()}
  @callback on_error(String.t(), term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Runs the `before_request` hooks of all plugins, threading the options
  through each.
  """
  @spec run_before_request([module()], String.t(), keyword()) ::
          {:ok, keyword()} | {:error, term()}
  def run_before_request(plugins, operation, options) do
    Enum.reduce_while(plugins, {:ok, options}, fn plugin, {:ok, opts} ->
      case plugin.before_request(operation, opts) do
        {:ok, new_opts} -> {:cont, {:ok, new_opts}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Runs the `after_response` hooks of all plugins.
  """
  @spec run_after_response([module()], String.t(), {:ok, map()} | {:error, term()}) ::
          {:ok, map()} | {:error, term()}
  def run_after_response(plugins, operation, result) do
    Enum.reduce_while(plugins, result, fn plugin, acc ->
      case plugin.after_response(operation, acc) do
        {:error, reason} -> {:halt, {:error, reason}}
        new_result -> {:cont, new_result}
      end
    end)
  end

  @doc """
  Runs the `on_error` hooks of all plugins.
  """
  @spec run_on_error([module()], String.t(), term()) :: :ok
  def run_on_error(plugins, operation, error) do
    Enum.each(plugins, fn plugin -> plugin.on_error(operation, error) end)
    :ok
  end
end
