defmodule Lather.CLIIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.CLI
  alias Lather.TestUtils

  defmodule ExplorerService do
    @moduledoc false
    use Lather.Server

    @service_name "ExplorerService"
    @namespace "urn:explorer:service"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: ExplorerService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, port: port}
  end

  test "summary lists the service", %{port: port} do
    {:ok, output} = CLI.run(["--wsdl", "http://127.0.0.1:#{port}/soap?wsdl"])

    assert output =~ "Service: ExplorerService"
  end

  test "--list enumerates operations", %{port: port} do
    {:ok, output} = CLI.run(["--wsdl", "http://127.0.0.1:#{port}/soap?wsdl", "--list"])

    assert output =~ "Echo"
  end

  test "--op invokes an operation", %{port: port} do
    {:ok, output} =
      CLI.run([
        "--wsdl",
        "http://127.0.0.1:#{port}/soap?wsdl",
        "--op",
        "Echo",
        "--params",
        "{\"message\": \"hello\"}"
      ])

    assert output =~ "\"echo\" => \"hello\""
  end

  test "missing wsdl is an error" do
    assert {:error, {:missing_option, :wsdl}} = CLI.run([])
  end
end
