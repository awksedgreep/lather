defmodule Mix.Tasks.Lather.CallTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  alias Lather.TestUtils

  defmodule EchoService do
    use Lather.Server

    @service_name "EchoService"
    @api_version "1.0.0"

    soap_operation "Echo" do
      description("Echoes the message back")

      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    soap_operation "Add" do
      input do
        parameter("a", :int, required: true)
        parameter("b", :int, required: true)
      end

      output do
        parameter("sum", :int)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}

    def add(%{"a" => a, "b" => b}),
      do: {:ok, %{"sum" => String.to_integer(a) + String.to_integer(b)}}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: EchoService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)
    {:ok, wsdl: "http://127.0.0.1:#{port}/soap?wsdl"}
  end

  test "--list shows the operations and their parameters", %{wsdl: wsdl} do
    output = capture_io(fn -> Mix.Tasks.Lather.Call.run(["--wsdl", wsdl, "--list"]) end)

    assert output =~ "Service: EchoService"
    assert output =~ "Operations (2)"
    assert output =~ "Echo"
    assert output =~ "required: message"
    assert output =~ "Add"
    assert output =~ "required: a, b"
  end

  test "invokes an operation with --param values", %{wsdl: wsdl} do
    output =
      capture_io(fn ->
        Mix.Tasks.Lather.Call.run([
          "--wsdl",
          wsdl,
          "--operation",
          "Echo",
          "--param",
          "message=hello world"
        ])
      end)

    body = Jason.decode!(output)
    assert body["echo"] == "hello world"
  end

  test "invokes an operation with --json parameters", %{wsdl: wsdl} do
    output =
      capture_io(fn ->
        Mix.Tasks.Lather.Call.run([
          "--wsdl",
          wsdl,
          "--operation",
          "Add",
          "--json",
          "{\"a\": \"2\", \"b\": \"3\"}"
        ])
      end)

    body = Jason.decode!(output)
    assert body["sum"] == "5"
  end

  test "supports SOAP 1.2 requests", %{wsdl: wsdl} do
    output =
      capture_io(fn ->
        Mix.Tasks.Lather.Call.run([
          "--wsdl",
          wsdl,
          "--operation",
          "Echo",
          "--param",
          "message=version two",
          "--soap-version",
          "1.2"
        ])
      end)

    body = Jason.decode!(output)
    assert body["echo"] == "version two"
  end

  test "--raw prints the parsed response structure", %{wsdl: wsdl} do
    output =
      capture_io(fn ->
        Mix.Tasks.Lather.Call.run([
          "--wsdl",
          wsdl,
          "--operation",
          "Echo",
          "--param",
          "message=raw",
          "--raw"
        ])
      end)

    assert output =~ "response"
    assert output =~ "echo"
  end
end
