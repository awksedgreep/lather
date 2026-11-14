defmodule Mix.Tasks.Lather.Call do
  use Mix.Task

  @moduledoc """
  Invoke a SOAP service operation and print the response — a request/response
  debugging tool for any SOAP service.

  List a service's operations:

      mix lather.call --wsdl http://localhost:4000/soap?wsdl --list

  Call an operation:

      mix lather.call --wsdl http://localhost:4000/soap?wsdl \
        --operation Echo --param message=hello

  ## Options

    * `--wsdl` (required) - WSDL URL or file path
    * `--operation` - Operation name to invoke
    * `--param key=value` - Operation parameter; repeatable
    * `--json '{...}'` - Parameters as a JSON object (alternative to `--param`)
    * `--list` - Print available operations and exit
    * `--soap-version` - `1.1` (default) or `1.2`
    * `--endpoint` - Override the service endpoint from the WSDL
    * `--timeout` - Request timeout in milliseconds (default: 30000)
    * `--raw` - Print the raw parsed response instead of JSON
    * `--auth user:pass` - Basic authentication
    * `--ws-auth user:pass` - WS-Security UsernameToken authentication
  """

  alias Lather.DynamicClient

  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          wsdl: :string,
          operation: :string,
          param: :string,
          json: :string,
          list: :boolean,
          soap_version: :string,
          endpoint: :string,
          timeout: :integer,
          raw: :boolean,
          auth: :string,
          ws_auth: :string
        ]
      )

    case opts[:wsdl] do
      nil ->
        IO.puts(
          "Usage: mix lather.call --wsdl URL_OR_FILE [--operation NAME] [--param key=value ...]"
        )

        exit_with(1)

      wsdl ->
        client_options = build_client_options(opts)

        case DynamicClient.new(wsdl, client_options) do
          {:ok, client} ->
            if opts[:list] do
              print_operations(client)
            else
              call_operation(client, opts)
            end

          {:error, reason} ->
            IO.puts("Failed to load WSDL: #{inspect(reason)}")
            exit_with(1)
        end
    end
  end

  defp build_client_options(opts) do
    []
    |> maybe_put(:soap_version, parse_version(opts[:soap_version]))
    |> maybe_put(:endpoint_override, opts[:endpoint])
    |> maybe_put(:timeout, opts[:timeout])
    |> maybe_put(:authentication, parse_auth(opts[:auth], :basic))
    |> maybe_put(:authentication, parse_auth(opts[:ws_auth], :wssecurity))
  end

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)

  defp parse_version(nil), do: nil
  defp parse_version("1.2"), do: :v1_2
  defp parse_version("1.1"), do: :v1_1
  defp parse_version(other), do: raise(ArgumentError, "invalid --soap-version: #{other}")

  defp parse_auth(nil, _kind), do: nil

  defp parse_auth(value, kind) do
    case String.split(value, ":", parts: 2) do
      [user, pass] -> {kind, user, pass}
      _ -> raise(ArgumentError, "invalid --auth/--ws-auth: expected user:pass")
    end
  end

  defp print_operations(client) do
    operations = DynamicClient.list_operations(client)

    IO.puts("Service: #{DynamicClient.get_service_info(client).service_name}")
    IO.puts("Operations (#{length(operations)}):")

    Enum.each(operations, fn operation ->
      IO.puts("  #{operation.name}")
      IO.puts("    required: #{format_names(operation.required_parameters)}")
      IO.puts("    optional: #{format_names(operation.optional_parameters)}")
    end)
  end

  defp format_names(names) do
    case names do
      [] -> "(none)"
      names -> Enum.join(names, ", ")
    end
  end

  defp call_operation(client, opts) do
    operation = opts[:operation]

    if is_nil(operation) do
      IO.puts("Usage: mix lather.call --wsdl URL --operation NAME --param key=value ...")
      IO.puts("       (use --list to see available operations)")
      exit_with(1)
    end

    params = build_params(opts)

    call_options = []
    call_options = call_options |> maybe_put(:timeout, opts[:timeout])

    case DynamicClient.call(client, operation, params, call_options) do
      {:ok, response} ->
        if opts[:raw] do
          IO.inspect(response, label: "response")
        else
          IO.puts(Jason.encode!(normalize_for_json(response), pretty: true))
        end

      {:error, {:soap_fault, fault}} ->
        IO.puts("SOAP fault: #{fault.fault_string} (code: #{fault.fault_code})")
        exit_with(2)

      {:error, reason} ->
        IO.puts("Request failed: #{inspect(reason)}")
        exit_with(2)
    end
  end

  defp build_params(opts) do
    case opts[:json] do
      nil ->
        for {key, pair} <- opts, key == :param, into: %{} do
          case String.split(pair, "=", parts: 2) do
            [name, value] -> {name, value}
            [name] -> {name, ""}
          end
        end

      json ->
        Jason.decode!(json)
    end
  end

  # Responses can contain tuples, atoms and non-JSON scalars; turn them into
  # JSON-encodable values for pretty printing.
  defp normalize_for_json(value) do
    cond do
      is_map(value) ->
        for {k, v} <- value, into: %{} do
          {to_string(k), normalize_for_json(v)}
        end

      is_list(value) ->
        Enum.map(value, &normalize_for_json/1)

      is_tuple(value) ->
        value |> Tuple.to_list() |> Enum.map(&normalize_for_json/1)

      is_atom(value) ->
        to_string(value)

      true ->
        value
    end
  end

  defp exit_with(code) do
    System.halt(code)
  end
end
