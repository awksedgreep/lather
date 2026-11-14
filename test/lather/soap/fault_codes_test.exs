defmodule Lather.Soap.FaultCodesTest do
  use ExUnit.Case, async: true

  alias Lather.Soap.FaultCodes
  alias Lather.Server.ResponseBuilder

  test "spec subcodes are exposed" do
    assert FaultCodes.subcodes("Sender") == ["BadRequest", "MalformedMessage", "DeliveryFailure"]
    assert FaultCodes.subcodes("Receiver") == ["TemporaryFailure", "Unavailable"]
    assert FaultCodes.subcodes("Other") == []
  end

  test "convenience faults build correctly" do
    fault = FaultCodes.bad_request("missing parameter")

    assert fault[:fault_code] == "Sender"
    assert fault[:subcode] == "BadRequest"
    assert fault[:fault_string] == "missing parameter"
  end

  test "SOAP 1.2 faults render subcodes" do
    xml =
      ResponseBuilder.build_fault(
        %{
          fault_code: "Sender",
          subcode: "BadRequest",
          fault_string: "bad request"
        },
        soap_version: :v1_2
      )

    assert xml =~ "soap:Subcode"
    assert xml =~ "BadRequest"
    assert xml =~ "soap:Sender"
  end

  test "SOAP 1.1 faults ignore subcodes" do
    xml =
      ResponseBuilder.build_fault(
        %{
          fault_code: "Client",
          subcode: "BadRequest",
          fault_string: "bad request"
        },
        soap_version: :v1_1
      )

    assert xml =~ "faultcode"
    refute xml =~ "Subcode"
  end
end
