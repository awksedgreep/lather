defmodule Lather.CertificateIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.TestUtils

  @cert_pem """
  -----BEGIN CERTIFICATE-----
  MIIDETCCAfmgAwIBAgIUDySvIcaKPWrEVuatm0tBLdVxibswDQYJKoZIhvcNAQEL
  BQAwGDEWMBQGA1UEAwwNbGF0aGVyLWNsaWVudDAeFw0yNjExMTQyMDUwNDJaFw0y
  NzExMTQyMDUwNDJaMBgxFjAUBgNVBAMMDWxhdGhlci1jbGllbnQwggEiMA0GCSqG
  SIb3DQEBAQUAA4IBDwAwggEKAoIBAQC1Fgn/+aayZuyYXhCW6d8WLCjCmxfNSsWf
  Ds8i7iguxx429W5ANiNeQeAd2Gw50Vi1ASCI7FQTkHbet/YenqqtqeSowcrGRrqg
  RYZxnzidHuUJU+PYJheDoRlyaGRLbluf66CnJiHPr3HpzoY2BFBPD8CjymEps+i0
  Zs+Fa+BMfBtTL6tE1+qU8ggLp7DFk1sx8bYVf11F0Bn6pgqb2LMXaLq8uFRis8zG
  g0XhZRav8cBN5FnV5HUiDhwSti0VVeVZFs3m9TwisdWiqB6v39UVrauB/Pl2To6L
  0vP8MjzU86GYuYwjeTKLzne/StrRel0UE7xd+b/6e6Lds8fNSwi3AgMBAAGjUzBR
  MB0GA1UdDgQWBBRbAZliIWNGTiW7KD1Eujo4Hg7BqjAfBgNVHSMEGDAWgBRbAZli
  IWNGTiW7KD1Eujo4Hg7BqjAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUA
  A4IBAQBcM4wEjMLM3p35Tph8RHw3cdMk2sxq4IHxvP2LEUAy/qWtHrz6nU8JgFBb
  1KVBx1pO790fYLvr7V14vSIpzRxFEBfZKc6tbmcI0KgTSAS83WmEKj1O9a52Kz9+
  +oPAuA+2A8yuHaM+kCYhd23Ub0DxrZ80WdtjnYHjS8Ju+0NcsvPMR3MNlUw3k1X2
  A6bwFxAL0LbtCCIPxWsWuQkNxZbq2lBEpN+DXzeeJ5cO6e82xcHnk99DIVMoFURs
  EmE+Bj0J0Q8SsHSL95YWuFqCSq4kdeRRTWG9ELW7sVavHzYpCRIXGqrY8niBek1N
  q5GdQp27fDgBT0Wp7VKjlIobILsS
  -----END CERTIFICATE-----
  """

  defmodule CertService do
    @moduledoc false
    use Lather.Server

    @service_name "CertService"
    @namespace "urn:cert:service"

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
    fingerprint = Lather.Auth.Certificate.fingerprint(@cert_pem)

    plug = {
      Lather.Server.EnhancedPlug,
      [service: CertService, client_certificates: %{"lather-client" => fingerprint}]
    }

    {:ok, _pid, port} = TestUtils.start_server(plug, 0)

    {:ok, client} = Lather.DynamicClient.new("http://127.0.0.1:#{port}/soap?wsdl")

    {:ok, client: client}
  end

  test "valid client certificate authenticates", %{client: client} do
    {:ok, response} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "certified"},
        authentication: {:certificate, @cert_pem}
      )

    assert response["echo"] == "certified"
  end

  test "requests without a certificate are rejected", %{client: client} do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "x"})

    assert fault[:fault_string] =~ "certificate"
  end

  test "unknown certificates are rejected", %{client: client} do
    {:error, {:soap_fault, fault}} =
      Lather.DynamicClient.call(client, "Echo", %{"message" => "x"},
        authentication:
          {:certificate, "-----BEGIN CERTIFICATE-----\nnot-valid\n-----END CERTIFICATE-----"}
      )

    assert fault[:fault_string] =~ "certificate"
  end
end
