defmodule Lather.Http.TransportTest do
  use ExUnit.Case
  doctest Lather.Http.Transport

  alias Lather.Http.Transport

  describe "build_headers/1" do
    test "builds default headers" do
      headers = Transport.build_headers([])

      assert {"content-type", "text/xml; charset=utf-8"} in headers
      assert {"accept", "text/xml"} in headers
      assert {"soapaction", ""} in headers
    end

    test "includes custom SOAPAction" do
      headers = Transport.build_headers(soap_action: "http://example.com/action")

      assert {"soapaction", "http://example.com/action"} in headers
    end

    test "includes custom headers" do
      custom_headers = [{"authorization", "Bearer token123"}]
      headers = Transport.build_headers(headers: custom_headers)

      assert {"authorization", "Bearer token123"} in headers
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
