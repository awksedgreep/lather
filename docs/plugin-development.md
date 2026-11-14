# Plugin Development Guide

Plugins implement the `Lather.Plugin` behaviour and are passed to
`DynamicClient.new/2` as `plugins: [MyPlugin]`. Hooks run around every
`DynamicClient.call/4`:

```elixir
defmodule AuditPlugin do
  @behaviour Lather.Plugin

  def before_request(request, options) do
    Map.put(request, "headers", Map.get(request, "headers", []) ++
      [{"X-Audit", "1"}])
  end

  def after_response(result, options) do
    result
  end

  def on_error(error, options) do
    Lather.Logger.warn("soap error: #{inspect(error)}")
    error
  end
end
```

## Rules

- `before_request/2` may add headers or mutate the body; it must return
  the request map.
- `after_response/2` receives the parsed result and may transform it.
- `on_error/2` receives `{:error, reason}` and decides whether to
  re-raise or return a fallback.
- Plugins run in list order; keep them pure and cheap — expensive work
  belongs in the service or a queue (`Lather.Queue`).

## Testability

Integration tests use a plugin that stamps a header and asserts it
appears in the outgoing envelope
(`test/integration/plugin_integration_test.exs`).
