defmodule Lather.Http.TransportTest do
  use ExUnit.Case
  doctest Lather.Http.Transport

  alias Lather.Http.Transport

  describe "build_headers/1" do
    test "builds default headers" do
      headers = Transport.build_headers([])

      assert {"content-type", "text/xml; charset=utf-8"} in headers
      assert {"accept", "text/xml"} in headers
      # SOAPAction value is quoted per SOAP 1.1 spec (empty string becomes "")
      assert {"soapaction", "\"\""} in headers
    end

    test "includes custom SOAPAction" do
      headers = Transport.build_headers(soap_action: "http://example.com/action")

      # SOAPAction value MUST be quoted per SOAP 1.1 spec
      assert {"soapaction", "\"http://example.com/action\""} in headers
    end

    test "includes custom headers" do
      custom_headers = [{"authorization", "Bearer token123"}]
      headers = Transport.build_headers(headers: custom_headers)

      assert {"authorization", "Bearer token123"} in headers
    end

    test "includes basic auth header when provided" do
      headers = Transport.build_headers(basic_auth: {"user", "pass"})

      auth_header =
        Enum.find(headers, fn {name, _} -> String.downcase(name) == "authorization" end)

      assert auth_header != nil
      {_, auth_value} = auth_header
      assert String.starts_with?(auth_value, "Basic ")
    end

    test "overrides default headers with custom headers" do
      custom_headers = [{"content-type", "custom/type"}, {"accept", "custom/accept"}]
      headers = Transport.build_headers(headers: custom_headers)

      assert {"content-type", "custom/type"} in headers
      assert {"accept", "custom/accept"} in headers
      refute {"content-type", "text/xml; charset=utf-8"} in headers
    end

    test "ignores map-style headers (SOAP headers should not reach transport)" do
      # SOAP headers like WS-Security are maps, not tuples.
      # They should be filtered out by DynamicClient before reaching Transport.
      # This test documents the expected HTTP header format.
      # If map-style headers accidentally reach build_headers, it will raise.
      # This is by design - DynamicClient.send_request must filter :headers.

      # Valid HTTP headers are tuples
      valid_headers = [{"authorization", "Bearer token"}, {"x-custom", "value"}]
      headers = Transport.build_headers(headers: valid_headers)

      assert {"authorization", "Bearer token"} in headers
      assert {"x-custom", "value"} in headers
    end
  end

  describe "build_headers/1 - SOAP 1.2 support" do
    test "builds SOAP 1.2 headers when version specified" do
      headers = Transport.build_headers(soap_version: :v1_2)

      assert {"content-type", "application/soap+xml; charset=utf-8"} in headers
      assert {"accept", "application/soap+xml, text/xml"} in headers
      # SOAP 1.2 should not include SOAPAction header
      refute Enum.any?(headers, fn {name, _} -> String.downcase(name) == "soapaction" end)
    end

    test "embeds action in Content-Type for SOAP 1.2" do
      headers =
        Transport.build_headers(soap_version: :v1_2, soap_action: "http://example.com/action")

      content_type_header = Enum.find(headers, fn {name, _} -> name == "content-type" end)
      assert content_type_header != nil
      {_, content_type} = content_type_header

      assert content_type ==
               "application/soap+xml; charset=utf-8; action=\"http://example.com/action\""
    end

    test "handles empty action in SOAP 1.2" do
      headers = Transport.build_headers(soap_version: :v1_2, soap_action: "")

      content_type_header = Enum.find(headers, fn {name, _} -> name == "content-type" end)
      assert content_type_header != nil
      {_, content_type} = content_type_header
      assert content_type == "application/soap+xml; charset=utf-8"
    end

    test "defaults to SOAP 1.1 when version not specified" do
      headers = Transport.build_headers([])

      assert {"content-type", "text/xml; charset=utf-8"} in headers
      assert {"accept", "text/xml"} in headers
      # SOAPAction value is quoted per SOAP 1.1 spec (empty string becomes "")
      assert {"soapaction", "\"\""} in headers
    end

    test "SOAP 1.1 still uses SOAPAction header" do
      headers =
        Transport.build_headers(soap_version: :v1_1, soap_action: "http://example.com/action")

      # SOAPAction value MUST be quoted per SOAP 1.1 spec
      assert {"soapaction", "\"http://example.com/action\""} in headers
      content_type_header = Enum.find(headers, fn {name, _} -> name == "content-type" end)
      {_, content_type} = content_type_header
      # Should not embed action in Content-Type for SOAP 1.1
      refute String.contains?(content_type, "action=")
    end

    test "custom headers override version-specific defaults" do
      custom_headers = [{"content-type", "custom/type"}]
      headers = Transport.build_headers(soap_version: :v1_2, headers: custom_headers)

      assert {"content-type", "custom/type"} in headers
      # Should not have the default SOAP 1.2 content-type
      refute {"content-type", "application/soap+xml; charset=utf-8"} in headers
    end

    test "preserves other headers when embedding action in SOAP 1.2" do
      headers =
        Transport.build_headers(
          soap_version: :v1_2,
          soap_action: "test-action",
          headers: [{"custom-header", "custom-value"}]
        )

      assert {"custom-header", "custom-value"} in headers
      assert {"accept", "application/soap+xml, text/xml"} in headers

      content_type_header = Enum.find(headers, fn {name, _} -> name == "content-type" end)
      {_, content_type} = content_type_header
      assert String.contains?(content_type, "action=\"test-action\"")
    end
  end

  describe "validate_url/1" do
    test "validates valid HTTP URLs" do
      assert Transport.validate_url("http://example.com/soap") == :ok
      assert Transport.validate_url("https://example.com/soap") == :ok
    end

    test "rejects invalid URLs" do
      assert Transport.validate_url("ftp://example.com") == {:error, :invalid_url}
      assert Transport.validate_url("invalid-url") == {:error, :invalid_url}
      assert Transport.validate_url(nil) == {:error, :invalid_url}
    end
  end

  describe "ssl_options/1" do
    test "returns default SSL options" do
      options = Transport.ssl_options()

      assert Keyword.get(options, :verify) == :verify_peer
      assert :"tlsv1.2" in Keyword.get(options, :versions)
      assert :"tlsv1.3" in Keyword.get(options, :versions)
    end

    test "merges custom SSL options" do
      custom_options = [verify: :verify_none, depth: 2]
      options = Transport.ssl_options(custom_options)

      assert Keyword.get(options, :verify) == :verify_none
      assert Keyword.get(options, :depth) == 2
    end
  end
end
