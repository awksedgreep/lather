defmodule Lather.SignatureIntegrationTest do
  use ExUnit.Case, async: true

  alias Lather.TestUtils

  defmodule SignedService do
    use Lather.Server

    @service_name "SignedService"
    @namespace "urn:signed:service"

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
    plug = {Lather.Server.EnhancedPlug, [service: SignedService, verify_signature: "s3cret"]}
    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  test "a correctly signed request succeeds", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:signature, "s3cret"})

    {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "signed"})
    assert response["echo"] == "signed"
  end

  test "a request signed with the wrong key is rejected", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", authentication: {:signature, "wrong-key"})

    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "signature verification failed"
  end

  test "an unsigned request is rejected when verification is required", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl")

    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "hi"})

    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "signature verification failed"
  end
end
