defmodule Mix.Tasks.Lather.Analyze do
  @shortdoc "Analyze a WSDL and print a summary report"

  @moduledoc """
  Analyzes a WSDL document and prints a summary report: service name,
  endpoints, operations, messages, types, bindings, port types, and
  namespaces.

  ## Usage

      mix lather.analyze --wsdl https://example.com/service?wsdl
      mix lather.analyze --wsdl priv/users.wsdl
      mix lather.analyze --wsdl priv/users.wsdl --json

  ## Options

    - `--wsdl` - path or URL of the WSDL document (required)
    - `--json` - print the analyzed service info as JSON instead of the
      human-readable report (requires `Jason`)
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [wsdl: :string, json: :boolean])

    unless opts[:wsdl] do
      Mix.raise("Usage: mix lather.analyze --wsdl path/to/service.wsdl [--json]")
    end

    case Lather.Wsdl.Analyzer.load_and_analyze(opts[:wsdl]) do
      {:ok, service_info} ->
        if opts[:json] do
          unless Code.ensure_loaded?(Jason) do
            Mix.raise(
              "The --json flag requires Jason. Add {:jason, \"~> 1.4\"} to your dependencies."
            )
          end

          Mix.shell().info(Jason.encode!(service_info, pretty: true))
        else
          Mix.shell().info(Lather.Wsdl.Analyzer.generate_report(service_info))
        end

      {:error, reason} ->
        Mix.raise("Could not analyze WSDL #{opts[:wsdl]}: #{inspect(reason)}")
    end
  end
end
