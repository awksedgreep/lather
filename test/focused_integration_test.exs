defmodule Lather.FocusedIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "Focused integration tests" do

    @tag timeout: 10_000
    test "XML parsing works correctly" do
      # Test with a minimal valid XML document first
      simple_xml = "<?xml version=\"1.0\"?><root><test>value</test></root>"

      case Lather.Xml.Parser.parse(simple_xml) do
        {:ok, parsed} ->
          assert is_map(parsed)
          assert get_in(parsed, ["root", "test"]) == "value"

        {:error, reason} ->
          flunk("XML parser failed: #{inspect(reason)}")
      end
    end

    @tag timeout: 10_000
    test "SOAP envelope building works" do
      # Test that we can build SOAP envelopes

      # Build a simple SOAP request
      request_data = %{
        "message" => "Hello World"
      }

      case Lather.Soap.Envelope.build("Echo", request_data) do
        {:ok, soap_xml} ->
          assert String.contains?(soap_xml, "<?xml")
          assert String.contains?(soap_xml, "<soap:Envelope")
          assert String.contains?(soap_xml, "Hello World")

        {:error, error} ->
          flunk("Request building failed: #{inspect(error)}")
      end
    end

    @tag timeout: 10_000
    test "XML builder and parser round trip" do
      # Test the core XML functionality
      test_data = %{
        "soap:Envelope" => %{
          "@xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/",
          "soap:Body" => %{
            "TestOperation" => %{
              "param1" => "value1",
              "param2" => "value2"
            }
          }
        }
      }

      # Build XML
      case Lather.Xml.Builder.build_fragment(test_data) do
        {:ok, xml_string} ->
          assert String.contains?(xml_string, "<soap:Envelope")
          assert String.contains?(xml_string, "value1")
          assert String.contains?(xml_string, "value2")

          # Parse it back
          case Lather.Xml.Parser.parse(xml_string) do
            {:ok, parsed_data} ->
              # Basic validation that parsing worked
              assert is_map(parsed_data) || is_tuple(parsed_data)

            {:error, error} ->
              flunk("XML parsing failed: #{inspect(error)}")
          end

        {:error, error} ->
          flunk("XML building failed: #{inspect(error)}")
      end
    end

    @tag timeout: 5_000
    test "error handling works correctly" do
      # Test that our error handling system works
      error = Lather.Error.transport_error(:connection_refused, %{host: "localhost", port: 99999})

      assert error.type == :transport_error
      assert error.reason == :connection_refused
      assert error.details.host == "localhost"

      # Test error recovery detection
      assert Lather.Error.recoverable?(error) == true

      # Test non-recoverable error
      auth_error = Lather.Error.http_error(401, "Invalid credentials")
      assert Lather.Error.recoverable?(auth_error) == false
    end

    @tag timeout: 5_000
    test "HTTP transport validation works" do
      # Test that we can validate URLs and build headers
      assert :ok = Lather.Http.Transport.validate_url("http://example.com/soap")
      assert {:error, :invalid_url} = Lather.Http.Transport.validate_url(nil)

      # Test header building
      options = [
        headers: [{"user-agent", "Lather-Test/1.0"}],
        soap_action: "TestAction"
      ]

      headers = Lather.Http.Transport.build_headers(options)
      assert {"user-agent", "Lather-Test/1.0"} in headers
      # SOAPAction value MUST be quoted per SOAP 1.1 spec
      assert {"soapaction", "\"TestAction\""} in headers
    end
  end
end
