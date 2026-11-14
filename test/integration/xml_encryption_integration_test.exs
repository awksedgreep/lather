defmodule Lather.XMLEncryptionIntegrationTest do
  use ExUnit.Case, async: true

  alias Lather.TestUtils

  defmodule EncryptedService do
    @moduledoc false
    use Lather.Server

    @service_name "EncryptedService"
    @namespace "urn:encrypted:service"

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
      {Lather.Server.EnhancedPlug, [service: EncryptedService, encryption_key: "aes-secret"]}

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, base_url: "http://127.0.0.1:#{port}/soap"}
  end

  test "an encrypted request is decrypted and processed", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", encryption: {:aes256, "aes-secret"})

    {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "top secret"})
    assert response["echo"] == "top secret"
  end

  test "a request encrypted with the wrong key is rejected", %{base_url: base_url} do
    {:ok, client} =
      Lather.DynamicClient.new("#{base_url}?wsdl", encryption: {:aes256, "wrong-key"})

    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "x"})

    reason = fault.fault_string
    reason = if is_map(reason), do: reason["#text"], else: reason
    assert reason =~ "XML decryption failed"
  end

  test "plain requests still work on an encryption-capable server", %{base_url: base_url} do
    {:ok, client} = Lather.DynamicClient.new("#{base_url}?wsdl")

    {:ok, response} = Lather.DynamicClient.call(client, "Echo", %{"message" => "plain"})
    assert response["echo"] == "plain"
  end
end
