defmodule Lather.PluginTest do
  use ExUnit.Case, async: true

  alias Lather.Plugin

  defmodule HeaderPlugin do
    @moduledoc false
    @impl true
    def before_request(operation, options) do
      {:ok,
       Keyword.put(
         options,
         :headers,
         Keyword.get(options, :headers, []) ++ [{"X-Plugin", operation}]
       )}
    end

    @impl true
    def after_response(_operation, result), do: result

    @impl true
    def on_error(_operation, _error), do: {:ok, :logged}
  end

  defmodule FailingPlugin do
    @moduledoc false
    @impl true
    def before_request(_operation, _options), do: {:error, :plugin_failure}

    @impl true
    def after_response(_operation, result), do: result

    @impl true
    def on_error(_operation, _error), do: {:ok, :logged}
  end

  defmodule TransformPlugin do
    @moduledoc false
    @impl true
    def before_request(_operation, options), do: {:ok, options}

    @impl true
    def after_response(operation, {:ok, body}) do
      {:ok, Map.put(body, "plugin", operation)}
    end

    def after_response(_operation, error), do: {:ok, error}

    @impl true
    def on_error(_operation, _error), do: {:ok, :logged}
  end

  test "before_request threads options through plugins" do
    {:ok, opts} = Plugin.run_before_request([HeaderPlugin], "Echo", [])

    assert {"X-Plugin", "Echo"} in opts[:headers]
  end

  test "failing plugin halts the chain" do
    assert Plugin.run_before_request([HeaderPlugin, FailingPlugin], "Echo", []) ==
             {:error, :plugin_failure}
  end

  test "after_response transforms results" do
    {:ok, result} = Plugin.run_after_response([TransformPlugin], "Echo", {:ok, %{"echo" => "hi"}})

    assert result == %{"echo" => "hi", "plugin" => "Echo"}
  end

  test "on_error runs all plugins" do
    assert Plugin.run_on_error([HeaderPlugin, FailingPlugin], "Echo", :boom) == :ok
  end
end
