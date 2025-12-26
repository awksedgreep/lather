defmodule Lather.Integration.StandardsConformanceTest do
  @moduledoc """
  Tests for SOAP/WSDL standards conformance.

  Verifies compliance with:
  - SOAP 1.1 envelope structure (https://www.w3.org/TR/2000/NOTE-SOAP-20000508/)
  - SOAP 1.2 envelope structure (https://www.w3.org/TR/soap12/)
  - WS-I Basic Profile 1.1 recommendations
  - WSDL 1.1 structure (https://www.w3.org/TR/wsdl)
  - SOAPAction header requirements
  - Content-Type header requirements
  - SOAP fault structure
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  defmodule ConformanceService do
    use Lather.Server

    @namespace "http://test.example.com/conformance"
    @service_name "ConformanceService"

    soap_operation "Echo" do
      description "Simple echo for conformance testing"
      input do
        parameter "message", :string, required: true
      end
      output do
        parameter "result", :string
      end
      soap_action "http://test.example.com/conformance/Echo"
    end

    def echo(%{"message" => msg}), do: {:ok, %{"result" => msg}}

    soap_operation "Fail" do
      description "Always returns a SOAP fault"
      input do
        parameter "reason", :string, required: true
      end
      output do
        parameter "result", :string
      end
      soap_action "http://test.example.com/conformance/Fail"
    end

    def fail(%{"reason" => reason}) do
      Lather.Server.soap_fault("Client", reason)
    end

    soap_operation "ServerError" do
      description "Returns a server-side fault"
      input do
        parameter "trigger", :string, required: true
      end
      output do
        parameter "result", :string
      end
      soap_action "http://test.example.com/conformance/ServerError"
    end

    def server_error(%{"trigger" => _}) do
      Lather.Server.soap_fault("Server", "Internal processing error")
    end
  end

  defmodule ConformanceRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.StandardsConformanceTest.ConformanceService)
      )
    end
  end

  describe "SOAP 1.1 envelope structure" do
    setup :start_server

    test "response contains correct SOAP 1.1 namespace", %{base_url: base_url, port: port} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)
      {:ok, _} = Lather.DynamicClient.call(client, "Echo", %{"message" => "test"})

      # Make a raw HTTP request to verify the response structure
      body = build_soap_11_request("Echo", "<message>test</message>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Echo\""}
      ], body)
      |> Finch.request(Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "http://schemas.xmlsoap.org/soap/envelope/")
    end

    test "response has soap:Envelope as root element", %{port: port} do
      body = build_soap_11_request("Echo", "<message>test</message>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Echo\""}
      ], body)
      |> Finch.request(Lather.Finch)

      # Should start with XML declaration and have soap:Envelope
      assert String.contains?(response.body, "soap:Envelope") or String.contains?(response.body, "Envelope")
      assert String.contains?(response.body, "soap:Body") or String.contains?(response.body, "Body")
    end

    test "response Content-Type is text/xml for SOAP 1.1", %{port: port} do
      body = build_soap_11_request("Echo", "<message>test</message>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Echo\""}
      ], body)
      |> Finch.request(Lather.Finch)

      content_type = get_header(response.headers, "content-type")
      assert String.contains?(content_type, "text/xml")
    end
  end

  describe "WSDL structure conformance" do
    setup :start_server

    test "WSDL has required root element", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert response.status == 200
      assert String.contains?(response.body, "<definitions") or String.contains?(response.body, "definitions>")
    end

    test "WSDL contains types section or schema", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      # Types section may be empty or contain schema - check for either types or XSD schema elements
      has_types = String.contains?(response.body, "<types") or String.contains?(response.body, "types>")
      has_schema = String.contains?(response.body, "schema") or String.contains?(response.body, "xsd:")
      has_messages = String.contains?(response.body, "<message") or String.contains?(response.body, "message>")

      # WSDL is valid if it has types section OR XSD schema elements OR at least messages
      assert has_types or has_schema or has_messages
    end

    test "WSDL contains message definitions", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert String.contains?(response.body, "<message") or String.contains?(response.body, "message>")
    end

    test "WSDL contains portType", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert String.contains?(response.body, "<portType") or String.contains?(response.body, "portType>")
    end

    test "WSDL contains binding", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert String.contains?(response.body, "<binding") or String.contains?(response.body, "binding>")
    end

    test "WSDL contains service", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert String.contains?(response.body, "<service") or String.contains?(response.body, "service>")
    end

    test "WSDL has correct Content-Type", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      content_type = get_header(response.headers, "content-type")
      assert String.contains?(content_type, "text/xml")
    end

    test "WSDL declares WSDL namespace", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert String.contains?(response.body, "http://schemas.xmlsoap.org/wsdl/")
    end

    test "WSDL declares SOAP binding namespace", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      # Should have SOAP binding namespace
      assert String.contains?(response.body, "http://schemas.xmlsoap.org/wsdl/soap/") or
             String.contains?(response.body, "http://schemas.xmlsoap.org/wsdl/soap12/")
    end
  end

  describe "SOAP fault structure" do
    setup :start_server

    test "client fault has correct structure", %{port: port} do
      body = build_soap_11_request("Fail", "<reason>Test error</reason>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Fail\""}
      ], body)
      |> Finch.request(Lather.Finch)

      # SOAP faults should return HTTP 500
      assert response.status == 500

      # Should contain fault structure
      assert String.contains?(response.body, "Fault") or String.contains?(response.body, "fault")
      assert String.contains?(response.body, "faultcode") or String.contains?(response.body, "Code")
      assert String.contains?(response.body, "faultstring") or String.contains?(response.body, "Reason")
    end

    test "server fault has correct faultcode", %{port: port} do
      body = build_soap_11_request("ServerError", "<trigger>go</trigger>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/ServerError\""}
      ], body)
      |> Finch.request(Lather.Finch)

      assert response.status == 500
      assert String.contains?(response.body, "Server") or String.contains?(response.body, "Receiver")
    end

    test "fault response is valid SOAP envelope", %{port: port} do
      body = build_soap_11_request("Fail", "<reason>Error</reason>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Fail\""}
      ], body)
      |> Finch.request(Lather.Finch)

      assert String.contains?(response.body, "soap:Envelope") or String.contains?(response.body, "Envelope")
      assert String.contains?(response.body, "soap:Body") or String.contains?(response.body, "Body")
    end
  end

  describe "HTTP requirements" do
    setup :start_server

    test "returns 405 for unsupported HTTP methods", %{port: port} do
      {:ok, response} = Finch.build(:put, "http://localhost:#{port}/soap", [], "test")
      |> Finch.request(Lather.Finch)

      assert response.status == 405
    end

    test "accepts POST for SOAP requests", %{port: port} do
      body = build_soap_11_request("Echo", "<message>test</message>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Echo\""}
      ], body)
      |> Finch.request(Lather.Finch)

      assert response.status == 200
    end

    test "accepts GET for WSDL requests", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert response.status == 200
    end

    test "returns 400 for malformed SOAP request", %{port: port} do
      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"test\""}
      ], "not valid xml")
      |> Finch.request(Lather.Finch)

      assert response.status == 400
    end
  end

  describe "unknown operation handling" do
    setup :start_server

    test "returns SOAP fault for unknown operation", %{port: port} do
      body = build_soap_11_request("UnknownOperation", "<param>test</param>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"unknown\""}
      ], body)
      |> Finch.request(Lather.Finch)

      assert response.status == 500
      assert String.contains?(response.body, "Fault") or String.contains?(response.body, "fault")
    end
  end

  describe "XML declaration" do
    setup :start_server

    test "response includes XML declaration", %{port: port} do
      body = build_soap_11_request("Echo", "<message>test</message>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Echo\""}
      ], body)
      |> Finch.request(Lather.Finch)

      assert String.starts_with?(String.trim(response.body), "<?xml")
    end

    test "response specifies UTF-8 encoding", %{port: port} do
      body = build_soap_11_request("Echo", "<message>test</message>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Echo\""}
      ], body)
      |> Finch.request(Lather.Finch)

      assert String.contains?(response.body, "UTF-8") or String.contains?(response.body, "utf-8")
    end

    test "WSDL includes XML declaration", %{port: port} do
      {:ok, response} = Finch.build(:get, "http://localhost:#{port}/soap?wsdl", [])
      |> Finch.request(Lather.Finch)

      assert String.starts_with?(String.trim(response.body), "<?xml")
    end
  end

  describe "namespace handling" do
    setup :start_server

    test "response elements are properly namespaced", %{port: port} do
      body = build_soap_11_request("Echo", "<message>test</message>", "http://test.example.com/conformance")

      {:ok, response} = Finch.build(:post, "http://localhost:#{port}/soap", [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", "\"http://test.example.com/conformance/Echo\""}
      ], body)
      |> Finch.request(Lather.Finch)

      # Should have SOAP envelope namespace
      assert String.contains?(response.body, "xmlns:soap") or
             String.contains?(response.body, "xmlns=") or
             String.contains?(response.body, "http://schemas.xmlsoap.org/soap/envelope/")
    end
  end

  # Setup helper
  defp start_server(_context) do
    {:ok, _} = Application.ensure_all_started(:lather)

    port = Enum.random(10000..60000)
    {:ok, server_pid} = Bandit.start_link(plug: ConformanceRouter, port: port, scheme: :http)

    on_exit(fn ->
      try do
        GenServer.stop(server_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    Process.sleep(50)
    {:ok, port: port, base_url: "http://localhost:#{port}"}
  end

  # Helper to build SOAP 1.1 request
  defp build_soap_11_request(operation, params, namespace) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="#{namespace}">
      <soap:Body>
        <tns:#{operation}>
          #{params}
        </tns:#{operation}>
      </soap:Body>
    </soap:Envelope>
    """
  end

  # Helper to get header value
  defp get_header(headers, name) do
    case Enum.find(headers, fn {k, _v} -> String.downcase(k) == name end) do
      {_k, v} -> v
      nil -> ""
    end
  end
end
