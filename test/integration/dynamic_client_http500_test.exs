defmodule Lather.Integration.DynamicClientHttp500Test do
  @moduledoc """
  Integration tests for DynamicClient HTTP 500 error handling.

  Verifies that a 500 response whose body is valid XML but not a SOAP fault
  is surfaced as an error rather than silently returned as {:ok, _}.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  # A minimal service used only to generate a valid WSDL and expose an operation.
  defmodule EchoService do
    use Lather.Server

    @namespace "http://test.example.com/echo"
    @service_name "EchoService"

    soap_operation "Echo" do
      description("Echoes the input")

      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end

      soap_action("Echo")
    end

    def echo(%{"message" => msg}), do: {:ok, %{"echo" => msg}}
  end

  @request_table :dynamic_client_http500_requests

  # Router that serves the WSDL through the normal Lather.Server.Plug, but
  # overrides the actual SOAP POST endpoint to return controlled 500 responses.
  defmodule Http500Router do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    # WSDL endpoint – served by Lather so the client can bootstrap.
    get "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(service: Lather.Integration.DynamicClientHttp500Test.EchoService)
      )
    end

    # SOAP call endpoint - responds with either 500 + SOAP fault or 500 + non-fault XML.
    post "/soap" do
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      :ets.insert(
        Lather.Integration.DynamicClientHttp500Test.request_table(),
        {:last_request_body, body}
      )

      if String.contains?(body, "fault-me") do
        soap_fault_xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <soap:Fault>
              <faultcode>Server</faultcode>
              <faultstring>Simulated SOAP fault</faultstring>
            </soap:Fault>
          </soap:Body>
        </soap:Envelope>
        """

        conn
        |> Plug.Conn.put_resp_content_type("text/xml")
        |> Plug.Conn.send_resp(500, soap_fault_xml)
      else
        non_fault_xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Error>
          <Code>INTERNAL_ERROR</Code>
          <Message>Something went wrong</Message>
        </Error>
        """

        conn
        |> Plug.Conn.put_resp_content_type("text/xml")
        |> Plug.Conn.send_resp(500, non_fault_xml)
      end
    end
  end

  def request_table, do: @request_table

  describe "send_request/5 HTTP 500 handling" do
    setup do
      {:ok, _} = Application.ensure_all_started(:lather)

      if :ets.whereis(@request_table) != :undefined do
        :ets.delete(@request_table)
      end

      :ets.new(@request_table, [:named_table, :public, :set])

      port = Enum.random(20000..59000)
      {:ok, server_pid} = Bandit.start_link(plug: Http500Router, port: port, scheme: :http)

      on_exit(fn ->
        try do
          GenServer.stop(server_pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end

        if :ets.whereis(@request_table) != :undefined do
          :ets.delete(@request_table)
        end
      end)

      Process.sleep(50)

      {:ok, base_url: "http://localhost:#{port}"}
    end

    test "returns error when HTTP 500 body is valid XML but not a SOAP fault", %{
      base_url: base_url
    } do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      result = Lather.DynamicClient.call(client, "Echo", %{"message" => "hello"})

      assert {:error, %{status: 500, type: :http_error}} = result,
             "Expected {:error, %{status: 500, type: :http_error}}, got: #{inspect(result)}"
    end

    test "returns soap_fault error when HTTP 500 body is a SOAP fault", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 5000)

      result = Lather.DynamicClient.call(client, "Echo", %{"message" => "fault-me"})

      assert {:error, {:soap_fault, fault}} = result
      assert fault.fault_code == "Server"
      assert fault.fault_string == "Simulated SOAP fault"
    end

    test "per-call namespace_prefix overrides client-level namespace_prefix", %{
      base_url: base_url
    } do
      {:ok, client} =
        Lather.DynamicClient.new("#{base_url}/soap?wsdl",
          timeout: 5000,
          namespace_prefix: "client"
        )

      {:error, %{status: 500, type: :http_error}} =
        Lather.DynamicClient.call(client, "Echo", %{"message" => "hello"},
          namespace_prefix: "call"
        )

      [{:last_request_body, request_body}] = :ets.lookup(@request_table, :last_request_body)

      assert String.contains?(request_body, "<call:Echo")
      assert String.contains?(request_body, ~s(xmlns:call="http://test.example.com/echo"))
      refute String.contains?(request_body, "<client:Echo")
      refute String.contains?(request_body, "xmlns:client")
    end
  end
end
