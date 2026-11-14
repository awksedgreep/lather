defmodule Lather.Wsdl.AddressingTest do
  use ExUnit.Case, async: true

  alias Lather.Wsdl.Addressing

  test "message ids are UUID-shaped" do
    id = Addressing.generate_message_id()

    assert String.length(id) == 36
    assert String.contains?(id, "-")
    assert id != Addressing.generate_message_id()
  end

  test "extract reads addressing headers" do
    headers = [
      {"wsa:To", "http://example.com/soap"},
      {"wsa:From", "http://client.example.com"},
      {"wsa:Action", "urn:do:thing"},
      {"wsa:MessageID", "abc-123"}
    ]

    addressing = Addressing.extract(headers)

    assert addressing[:to] == "http://example.com/soap"
    assert addressing[:from] == "http://client.example.com"
    assert addressing[:action] == "urn:do:thing"
    assert addressing[:message_id] == "abc-123"
  end

  test "validate requires To and Action" do
    assert Addressing.validate([{"wsa:To", "x"}, {"wsa:Action", "y"}]) == :ok
    assert match?({:error, {:soap_fault, _}}, Addressing.validate([]))
  end

  test "resolve_operation maps actions to operations" do
    operations = [%{name: "GetUser"}, %{name: "CreateUser"}]

    assert Addressing.resolve_operation([{"wsa:Action", "GetUser"}], operations) ==
             {:ok, "GetUser"}

    assert Addressing.resolve_operation([{"wsa:Action", "Nope"}], operations) ==
             {:error, :unknown_action}
  end
end
