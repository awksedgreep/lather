defmodule Lather.MultiVersionIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  defmodule VersionService do
    @moduledoc false
    use Lather.Server

    @service_name "VersionService"
    @namespace "urn:version:service"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}

    soap_operation "Fail" do
      output do
        parameter("error", :string)
      end
    end

    def fail(_params), do: {:error, :boom}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: VersionService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, port: port}
  end

  test "same service works via SOAP 1.1", %{port: port} do
    {:ok, client} =
      Lather.DynamicClient.new(
        "http://127.0.0.1:#{port}/soap?wsdl",
        soap_version: :v1_1
      )

    {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "v11"})

    assert response["echo"] == "v11"
  end

  test "same service works via SOAP 1.2", %{port: port} do
    {:ok, client} =
      Lather.DynamicClient.new(
        "http://127.0.0.1:#{port}/soap?wsdl",
        soap_version: :v1_2
      )

    {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "v12"})

    assert response["echo"] == "v12"
  end

  test "faults render in the client's SOAP version", %{port: port} do
    {:ok, client} =
      Lather.DynamicClient.new(
        "http://127.0.0.1:#{port}/soap?wsdl",
        soap_version: :v1_2
      )

    {:error, {:soap_fault, fault}} = Lather.DynamicClient.call(client, "Fail", %{})

    assert fault[:fault_code]
  end
end
