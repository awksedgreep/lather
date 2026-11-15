defmodule Mix.Tasks.Lather.ClientTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defmodule ClientService do
    use Lather.Server

    @service_name "ClientService"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    soap_operation "Now" do
      output do
        parameter("time", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
    def now(_params), do: {:ok, %{"time" => "12:00"}}
  end

  defp wsdl_path() do
    path =
      Path.join(
        System.tmp_dir!(),
        "lather_client_#{System.unique_integer([:positive])}.wsdl"
      )

    File.write(
      path,
      Lather.Server.WSDLGenerator.generate(
        ClientService.__soap_service__(),
        "http://localhost:4000/soap"
      )
    )

    on_exit(fn -> File.rm(path) end)
    path
  end

  test "prints a generated client module to stdout" do
    output = capture_io(fn -> Mix.Tasks.Lather.Client.run(["--wsdl", wsdl_path()]) end)

    assert output =~ "defmodule ClientServiceClient do"
    assert output =~ "def echo("
    assert output =~ "def now("
    assert output =~ "Lather.DynamicClient"
  end

  test "--module renames the generated module" do
    output =
      capture_io(fn ->
        Mix.Tasks.Lather.Client.run(["--wsdl", wsdl_path(), "--module", "MyApp.SmallClient"])
      end)

    assert output =~ "defmodule MyApp.SmallClient do"
  end

  test "--output writes the module to a file" do
    wsdl = wsdl_path()

    output_path =
      Path.join(System.tmp_dir!(), "lather_client_out_#{System.unique_integer([:positive])}.ex")

    on_exit(fn -> File.rm(output_path) end)

    capture_io(fn ->
      Mix.Tasks.Lather.Client.run(["--wsdl", wsdl, "--output", output_path])
    end)

    contents = File.read!(output_path)
    assert contents =~ "defmodule ClientServiceClient do"
    assert contents =~ "def echo("
  end

  test "raises when no WSDL is given" do
    assert_raise Mix.Error, fn -> Mix.Tasks.Lather.Client.run([]) end
  end

  test "raises when the WSDL cannot be read" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Lather.Client.run(["--wsdl", "/definitely/missing.wsdl"])
    end
  end
end
