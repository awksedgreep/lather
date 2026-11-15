defmodule Lather.Server.TelemetryTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Lather.Server.EnhancedPlug

  defmodule TelemetryService do
    use Lather.Server

    @service_name "TelemetryService"

    soap_operation "Ping" do
      input do
        parameter("seq", :int, required: true)
      end

      output do
        parameter("pong", :string)
      end
    end

    def ping(%{"seq" => seq}), do: {:ok, %{"pong" => "pong #{seq}"}}
  end

  @config EnhancedPlug.init(service: TelemetryService)

  defp capture_event() do
    event_id = "lather-telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      event_id,
      [:lather, :server, :request, :stop],
      fn _event, measurements, metadata, _config ->
        Process.put(:lather_event, {measurements, metadata})
      end,
      nil
    )

    event_id
  end

  test "requests emit a [:lather, :server, :request] span with duration and status" do
    event_id = capture_event()

    conn(:get, "/soap?health") |> EnhancedPlug.call(@config)

    {measurements, metadata} = Process.get(:lather_event)
    :telemetry.detach(event_id)

    assert measurements.duration >= 0
    assert metadata.status == 200
    assert metadata.service == TelemetryService
    assert metadata.method == "GET"
    assert metadata.path == "/soap"
  end

  test "SOAP invocations are instrumented too" do
    event_id = capture_event()

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <Ping xmlns="urn:example"><seq>1</seq></Ping>
      </soap:Body>
    </soap:Envelope>
    """

    conn(:post, "/soap", body) |> EnhancedPlug.call(@config)

    {_measurements, metadata} = Process.get(:lather_event)
    :telemetry.detach(event_id)

    assert metadata.status == 200
    assert metadata.method == "POST"
  end

  test "error responses are instrumented with their status" do
    event_id = capture_event()

    conn(:post, "/soap", "not xml at all") |> EnhancedPlug.call(@config)

    {_measurements, metadata} = Process.get(:lather_event)
    :telemetry.detach(event_id)

    assert metadata.status == 400
  end

  test "the span reports the SOAP operation that was invoked" do
    event_id = capture_event()

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <Ping xmlns="urn:example"><seq>2</seq></Ping>
      </soap:Body>
    </soap:Envelope>
    """

    conn(:post, "/soap", body) |> EnhancedPlug.call(@config)

    {_measurements, metadata} = Process.get(:lather_event)
    :telemetry.detach(event_id)

    assert metadata.operation == "Ping"
  end

  test "JSON/REST requests report their operation too" do
    event_id = capture_event()

    conn(:post, "/soap/api/Ping", Jason.encode!(%{"seq" => 3})) |> EnhancedPlug.call(@config)

    {_measurements, metadata} = Process.get(:lather_event)
    :telemetry.detach(event_id)

    assert metadata.operation == "Ping"
  end

  test "requests without an operation report none" do
    event_id = capture_event()

    conn(:get, "/soap?health") |> EnhancedPlug.call(@config)

    {_measurements, metadata} = Process.get(:lather_event)
    :telemetry.detach(event_id)

    assert metadata.operation == nil
  end
end
