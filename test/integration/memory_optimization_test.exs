defmodule Lather.MemoryOptimizationTest do
  use ExUnit.Case, async: false

  alias Lather.Http.Transport
  alias Lather.TestUtils

  defmodule BigEchoService do
    @moduledoc false
    use Lather.Server

    @service_name "BigEchoService"
    @namespace "urn:big:service"

    soap_operation "BigEcho" do
      input do
        parameter("payload", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def big_echo(%{"payload" => payload}), do: {:ok, %{"echo" => payload}}
  end

  setup do
    plug = {Lather.Server.EnhancedPlug, [service: BigEchoService]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, port: port}
  end

  test "normal requests are not affected by the streaming path", %{port: port} do
    {:ok, response} =
      Transport.post(
        "http://127.0.0.1:#{port}/soap",
        "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/wsdl/soap/\" xmlns=\"urn:big:service\"><soap:Body><BigEcho><payload>small</payload></BigEcho></soap:Body></soap:Envelope>",
        max_response_bytes: 1_000_000
      )

    assert response.status == 200
    assert response.body =~ "small"
  end

  test "oversized responses are rejected without buffering", %{port: port} do
    payload = String.duplicate("x", 100_000)

    envelope =
      "<soap:Envelope xmlns:soap=\"http://schemas.xmlsoap.org/wsdl/soap/\" xmlns=\"urn:big:service\"><soap:Body><BigEcho><payload>" <>
        payload <> "</payload></BigEcho></soap:Body></soap:Envelope>"

    {:error, error} =
      Transport.post(
        "http://127.0.0.1:#{port}/soap",
        envelope,
        max_response_bytes: 10_000
      )

    assert error.type == :transport_error
    assert error.reason == :response_too_large
  end
end
