defmodule Lather.Integration.SoapRolesTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils
  alias Lather.Soap.Header

  defmodule RoleService do
    @moduledoc false
    use Lather.Server

    @service_name "RoleService"
    @namespace "urn:roles:service"

    soap_operation "Echo" do
      input do
        parameter("message", :string, required: true)
      end

      output do
        parameter("echo", :string)
      end
    end

    def echo(%{"message" => message}), do: {:ok, %{"echo" => message}}
  end

  setup do
    plug =
      {Lather.Server.EnhancedPlug,
       [
         service: RoleService,
         understood_headers: ["Routing"],
         soap_roles: ["http://example.org/roles/backends"]
       ]}

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  test "mustUnderstand header with a recognized role is accepted", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", soap_version: :v1_2)

    header =
      Header.custom(
        "Routing",
        "backend",
        %{
          "soap:role" => "http://example.org/roles/backends",
          "soap:mustUnderstand" => "1"
        }
      )

    {:ok, response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "ok"}, headers: [header])

    assert response["echo"] == "ok"
  end

  test "mustUnderstand header with an unrecognized role produces a fault", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", soap_version: :v1_2)

    header =
      Header.custom(
        "Routing",
        "elsewhere",
        %{
          "soap:role" => "http://example.org/roles/unknown",
          "soap:mustUnderstand" => "1"
        }
      )

    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "ok"}, headers: [header])

    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "unrecognized role"
  end

  test "the default power role is always accepted", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", soap_version: :v1_2)

    header =
      Header.custom(
        "Routing",
        "power",
        %{
          "soap:role" => "http://www.w3.org/2003/05/soap/power",
          "soap:mustUnderstand" => "1"
        }
      )

    {:ok, response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "ok"}, headers: [header])

    assert response["echo"] == "ok"
  end

  test "mustUnderstand headers without a role are not affected", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl", soap_version: :v1_2)

    header = Header.custom("Routing", "plain", %{"soap:mustUnderstand" => "1"})

    {:ok, response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "ok"}, headers: [header])

    assert response["echo"] == "ok"
  end
end
