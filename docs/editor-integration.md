# Editor and Tooling Integration

Lather ships a CLI and a browsable HTTP surface that work with any
editor; the notes below cover VS Code and ElixirLS specifics.

## VS Code + ElixirLS

- Install the Elixir extension (ElixirLS) for IntelliSense on
  `Lather.Server` macros: `soap_operation`, `input`, `output`, `error`,
  and `parameter` are all real macros, so autocomplete and hover docs
  work out of the box.
- Enable "Explain warnings" in the ElixirLS settings; DSL mistakes
  (missing `do`, unknown option keys) show inline hints.

## Syntax highlighting

- The `?docs` page renders operations with highlighted example
  envelopes; copy them straight into your code.
- For .soap/.wsdl files, the VS Code XML extension highlights SOAP
  envelopes; `.ex` service files get standard Elixir highlighting.

## Quick exploration without an editor

```bash
mix run -e 'Lather.CLI.run(["--wsdl", "http://localhost:4000/soap?wsdl", "--list"])'
Lather.CLI.run(["--wsdl", url, "--op", "GetUser", "--params", '{"id": 1}'])
```

## LiveView components

Phoenix LiveView can render a service's `?docs` and `?dashboard` HTML
directly:

```elixir
defmodule SoapExplorerLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~H"""
    <div id="soap-endpoint">{Phoenix.HTML.Form.html_escape(@doc_html)}</div>
    """
  end
end
```

For in-process LiveView widgets, read the operation list from
`service_module.__soap_operations__()` and the metrics snapshot from
the server's `Metrics` state rather than HTTP-fetching the dashboard.
