defmodule Mix.Tasks.Lather.AnalyzeTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defmodule AnalyzeService do
    use Lather.Server

    @service_name "AnalyzeService"

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

    soap_type "Note" do
      element("text", :string, required: true)
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
    def now(_params), do: {:ok, %{"time" => "12:00"}}
  end

  defp wsdl_path() do
    path =
      Path.join(
        System.tmp_dir!(),
        "lather_analyze_#{System.unique_integer([:positive])}.wsdl"
      )

    File.write(
      path,
      Lather.Server.WSDLGenerator.generate(
        AnalyzeService.__soap_service__(),
        "http://localhost:4000/soap"
      )
    )

    on_exit(fn -> File.rm(path) end)
    path
  end

  test "prints a report with the service's operations and endpoints" do
    output = capture_io(fn -> Mix.Tasks.Lather.Analyze.run(["--wsdl", wsdl_path()]) end)

    assert output =~ "# WSDL Analysis Report"
    assert output =~ "## Service: AnalyzeService"
    assert output =~ "## Operations (2)"
    assert output =~ "Echo"
    assert output =~ "Now"
    assert output =~ "http://localhost:4000/soap"
  end

  test "--json emits parseable service info" do
    output =
      capture_io(fn -> Mix.Tasks.Lather.Analyze.run(["--wsdl", wsdl_path(), "--json"]) end)

    document = Jason.decode!(output)
    assert document["service_name"] == "AnalyzeService"
    assert length(document["operations"]) == 2
  end

  test "raises when no WSDL is given" do
    assert_raise Mix.Error, fn -> Mix.Tasks.Lather.Analyze.run([]) end
  end

  test "raises when the WSDL cannot be read" do
    assert_raise Mix.Error, fn ->
      Mix.Tasks.Lather.Analyze.run(["--wsdl", "/definitely/missing.wsdl"])
    end
  end
end
