defmodule Mix.Tasks.Lather.Openapi do
  @shortdoc "Generate an OpenAPI 3.1 spec from a Lather SOAP service or a WSDL"

  @moduledoc """
  Generates an OpenAPI 3.1 specification (JSON) from a Lather SOAP service
  module or a WSDL document.

  ## Usage

    # From a service module in the project
    mix lather.openapi --service MyApp.UserService

    # From a WSDL file or URL
    mix lather.openapi --wsdl priv/users.wsdl
    mix lather.openapi --wsdl https://example.com/service?wsdl

  ## Options

    - `--service` - a module that `use Lather.Server`
    - `--wsdl` - path or URL of a WSDL document (used when `--service` is not given)
    - `--output` - output file (default: `openapi.json`)
    - `--base-url` - base URL advertised in `servers` (default:
      `http://localhost:4000/soap`, or the service endpoint found in the WSDL)
    - `--version` - API version (default: the service's `@api_version`, else `1.0.0`)
    - `--description` - description placed in `info.description`

  Exactly one of `--service` or `--wsdl` is required. JSON encoding requires
  `Jason`, so add `{:jason, "~> 1.4"}` if your project does not already have it.

  The generated document is OpenAPI 3.1 and round-trips through code
  generators such as `infusion` (`mix infusion.gen`).
  """

  use Mix.Task

  @default_output "openapi.json"
  @default_base_url "http://localhost:4000/soap"

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          service: :string,
          wsdl: :string,
          output: :string,
          base_url: :string,
          version: :string,
          description: :string
        ]
      )

    case {opts[:service], opts[:wsdl]} do
      {nil, nil} ->
        Mix.raise(
          "Usage: mix lather.openapi --service MyApp.UserService | --wsdl path/to/service.wsdl"
        )

      {service, nil} ->
        generate_from_module(service, opts)

      {nil, wsdl} ->
        generate_from_wsdl(wsdl, opts)

      {_, _} ->
        Mix.raise("Use either --service or --wsdl, not both.")
    end
  end

  defp generate_from_module(module_name, opts) do
    module = Module.concat(String.split(module_name, "."))

    unless Code.ensure_loaded?(module) and function_exported?(module, :__soap_service__, 0) do
      Mix.raise(
        "#{module_name} is not a Lather SOAP service module. Did you forget `use Lather.Server`?"
      )
    end

    write_spec(
      module.__soap_service__(),
      opts[:base_url] || @default_base_url,
      opts
    )
  end

  defp generate_from_wsdl(source, opts) do
    case Lather.Wsdl.Analyzer.load_and_analyze(source) do
      {:ok, info} ->
        service_info = %{
          name: info.service_name,
          version: nil,
          operations: Enum.map(info.operations, &operation_from_wsdl/1),
          types: []
        }

        write_spec(
          service_info,
          opts[:base_url] || endpoint_from(info) || @default_base_url,
          opts
        )

      {:error, reason} ->
        Mix.raise("Could not analyze WSDL #{source}: #{inspect(reason)}")
    end
  end

  defp operation_from_wsdl(operation) do
    %{
      name: operation.name,
      description: operation.soap_action,
      input: parts_to_params(Map.get(operation, :input)),
      output: parts_to_params(Map.get(operation, :output))
    }
  end

  defp parts_to_params(message) do
    message
    |> Map.get(:parts, [])
    |> Enum.map(fn part ->
      %{
        name: part.name,
        type: part.type || "string",
        required: false
      }
    end)
  end

  defp endpoint_from(info) do
    case Map.get(info, :endpoints) do
      [endpoint | _] -> endpoint.address.location
      _ -> Map.get(info, :endpoint)
    end
  end

  defp write_spec(service_info, base_url, opts) do
    unless Code.ensure_loaded?(Jason) do
      Mix.raise(
        "OpenAPI generation requires Jason. Add {:jason, \"~> 1.4\"} to your dependencies."
      )
    end

    spec =
      Lather.Server.OpenAPIGenerator.generate(service_info, base_url,
        version: opts[:version],
        description: opts[:description]
      )

    output = opts[:output] || @default_output
    File.write!(output, Jason.encode!(spec, pretty: true))

    Mix.shell().info("Wrote #{output}: #{length(service_info.operations)} operation(s)")
  end
end
