defmodule Lather.TestClientTest do
  use ExUnit.Case, async: true

  alias Lather.TestClient

  defmodule TestService do
    use Lather.Server

    @service_name "TestService"
    @namespace "urn:test:service"
    @api_version "1.0.0"

    soap_operation "Echo" do
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

  @config TestClient.new(TestService)

  test "call_json invokes an operation and returns parsed JSON" do
    conn = TestClient.call_json(@config, "Echo", %{"message" => "hello"})

    assert TestClient.status(conn) == 200
    assert TestClient.json_body(conn)["data"]["echo"] == "hello"
  end

  test "call_json surfaces validation errors as 400" do
    conn = TestClient.call_json(@config, "Echo", %{})
    assert TestClient.status(conn) == 400
  end

  test "call_soap builds a SOAP 1.1 envelope" do
    conn = TestClient.call_soap(@config, "Add", %{"a" => "2", "b" => "3"})

    assert TestClient.status(conn) == 200
    assert TestClient.body(conn) =~ "<sum>5</sum>"
    assert TestClient.body(conn) =~ "schemas.xmlsoap.org/soap/envelope"
  end

  test "call_soap supports SOAP 1.2" do
    conn = TestClient.call_soap(@config, "Echo", %{"message" => "twelve"}, version: :v1_2)

    assert TestClient.status(conn) == 200
    assert TestClient.body(conn) =~ "www.w3.org/2003/05/soap-envelope"
    assert TestClient.body(conn) =~ "twelve"
  end

  test "call_soap escapes special characters in values" do
    conn = TestClient.call_soap(@config, "Echo", %{"message" => "a < b & c"})

    assert TestClient.status(conn) == 200
    assert TestClient.body(conn) =~ "a &lt; b &amp; c"
  end

  test "wsdl/health/openapi helpers return the expected documents" do
    wsdl_conn = TestClient.wsdl(@config)
    assert TestClient.status(wsdl_conn) == 200
    assert TestClient.body(wsdl_conn) =~ "TestService"

    health_conn = TestClient.health(@config)
    assert TestClient.json_body(health_conn)["status"] == "ok"

    openapi_conn = TestClient.openapi(@config)
    assert TestClient.json_body(openapi_conn)["openapi"] == "3.1.0"
  end

  test "standard WSDL is available via wsdl/2" do
    conn = TestClient.wsdl(@config, false)
    assert TestClient.status(conn) == 200
    assert TestClient.body(conn) =~ "urn:test:service"
  end
end
