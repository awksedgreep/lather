defmodule Lather.Auth.CertificateTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.Certificate

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

  test "parses a PEM certificate" do
    {:ok, info} = Certificate.parse_pem(@cert_pem)

    assert info.common_name == "lather-client"
    assert is_integer(info.serial)
    assert is_integer(info.not_before)
    assert is_integer(info.not_after)
    assert info.not_after > info.not_before
    assert String.length(info.fingerprint) == 64
  end

  test "verify accepts an allowed fingerprint" do
    fp = Certificate.fingerprint(@cert_pem)

    assert {:ok, info} = Certificate.verify(@cert_pem, %{"lather-client" => fp})
    assert info.common_name == "lather-client"

    assert {:ok, _} = Certificate.verify(@cert_pem, [fp])
  end

  test "verify rejects unknown fingerprints" do
    assert {:error, :certificate_not_allowed} = Certificate.verify(@cert_pem, ["bad-fingerprint"])
  end

  test "verify rejects malformed PEM" do
    assert {:error, :invalid_pem} = Certificate.verify("not a certificate", %{})
  end

  test "header/1 builds the client header" do
    assert [{"x-client-certificate", encoded}] = Certificate.header(@cert_pem)
    assert Base.decode64!(encoded) == @cert_pem
  end
end
