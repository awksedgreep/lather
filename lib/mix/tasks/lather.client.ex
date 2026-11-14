defmodule Mix.Tasks.Lather.Client do
  @shortdoc "Generate an Elixir client module from a WSDL"

  @moduledoc """
  Generates an Elixir client module for a SOAP service from its WSDL.

  ## Usage

      mix lather.client --wsdl https://example.com/service?wsdl
      mix lather.client --wsdl priv/users.wsdl --module MyApp.UserClient --output lib/user_client.ex

  ## Options

    - `--wsdl` - path or URL of the WSDL document (required)
    - `--module` - name of the generated module
      (default: `<ServiceName>Client`)
    - `--output` - file to write the module to (default: print to stdout)

  The generated module wraps `Lather.DynamicClient` with one function per
  operation and a struct for each complex WSDL type.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [wsdl: :string, module: :string, output: :string])

    unless opts[:wsdl] do
      Mix.raise(
        "Usage: mix lather.client --wsdl path/to/service.wsdl [--module Name] [--output file.ex]"
      )
    end

    case Lather.Wsdl.Analyzer.load_and_analyze(opts[:wsdl]) do
      {:ok, service_info} ->
        source =
          Lather.Client.Generator.generate(service_info,
            module: opts[:module],
            wsdl_url: opts[:wsdl]
          )

        if opts[:output] do
          File.write!(opts[:output], source)

          Mix.shell().info(
            "Wrote #{opts[:output]}: #{length(service_info.operations)} operation(s)"
          )
        else
          Mix.shell().info(source)
        end

      {:error, reason} ->
        Mix.raise("Could not analyze WSDL #{opts[:wsdl]}: #{inspect(reason)}")
    end
  end
end
