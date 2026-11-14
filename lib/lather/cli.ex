defmodule Lather.CLI do
  @moduledoc """
  Interactive SOAP service explorer for Lather.

  Run against a WSDL endpoint to list operations, inspect schemas, and
  invoke operations from the command line.

  ## Usage

      mix run -e "Lather.CLI.main([\"--wsdl\", \"http://localhost:4000/soap?wsdl\", \"--list\"])"
      mix run -e "Lather.CLI.main([\"--wsdl\", \"http://localhost:4000/soap?wsdl\", \"--op\", \"Echo\", \"--params\", \"{\\\"message\\\": \\\"hi\\\"}\"])"

  In interactive mode (no `--op` given) the explorer prints the service
  summary and available operations.
  """

  alias Lather.DynamicClient

  @doc """
  CLI entry point. Returns an exit code.
  """
  @spec main([String.t()]) :: non_neg_integer()
  def main(argv) do
    case run(argv) do
      {:ok, output} ->
        IO.write(output)
        0

      {:error, reason} ->
        IO.write("Error: #{inspect(reason)}\n")
        1
    end
  end

  @doc """
  Parse arguments and produce explorer output (usable programmatically
  and in tests).
  """
  @spec run([String.t()]) :: {:ok, String.t()} | {:error, term()}
  def run(argv) do
    opts = parse_args(argv, [])

    with {:ok, wsdl} <- fetch_keyword(opts, :wsdl),
         {:ok, client} <- DynamicClient.new(wsdl) do
      cond do
        Keyword.get(opts, :list) ->
          {:ok, list_operations(client)}

        op = Keyword.get(opts, :op) ->
          params = parse_params(Keyword.get(opts, :params, "{}"))

          case DynamicClient.call(client, op, params) do
            {:ok, result} -> {:ok, format_result(op, result)}
            {:error, reason} -> {:error, {:call_failed, reason}}
          end

        true ->
          {:ok, service_summary(client)}
      end
    end
  end

  defp parse_args([], acc), do: acc

  defp parse_args(["--wsdl", value | rest], acc),
    do: parse_args(rest, Keyword.put(acc, :wsdl, value))

  defp parse_args(["--op", value | rest], acc), do: parse_args(rest, Keyword.put(acc, :op, value))

  defp parse_args(["--params", value | rest], acc),
    do: parse_args(rest, Keyword.put(acc, :params, value))

  defp parse_args(["--list" | rest], acc), do: parse_args(rest, Keyword.put(acc, :list, true))
  defp parse_args([_unknown | rest], acc), do: parse_args(rest, acc)

  defp fetch_keyword(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, {:missing_option, key}}
      value -> {:ok, value}
    end
  end

  defp parse_params(raw) do
    case Jason.decode(raw) do
      {:ok, map} -> map
      {:error, _reason} -> %{}
    end
  rescue
    _ -> %{}
  end

  defp list_operations(%DynamicClient{service_info: service_info}) do
    lines =
      Enum.map(service_info.operations, fn op ->
        "  #{op.name} - #{Map.get(op, :description) || "no description"}"
      end)

    "Operations:\n" <> Enum.join(lines, "\n") <> "\n"
  end

  defp service_summary(%DynamicClient{service_info: service_info}) do
    """
    Service: #{Map.get(service_info, :name) || Map.get(service_info, :service_name) || "unknown"}
    Operations: #{length(service_info.operations)}
    SOAP version: #{Map.get(service_info, :soap_version) || :v1_1}

    Use --list to see operations, --op <name> --params '<json>' to invoke one.
    """
  end

  defp format_result(operation, result) do
    "#{operation}: #{inspect(result, pretty: true)}\n"
  end
end
