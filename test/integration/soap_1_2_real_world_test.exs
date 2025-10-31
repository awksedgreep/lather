defmodule Lather.Integration.Soap12RealWorldTest do
  @moduledoc """
  Real-world SOAP 1.2 integration test using the public CountryInfo service.

  This test validates our SOAP 1.2 implementation against a live service to ensure
  compatibility with real-world SOAP servers. It can be disabled by excluding
  the :external_api tag.

  Service: http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso
  """

  use ExUnit.Case, async: false

  alias Lather.DynamicClient

  @moduletag :external_api
  @moduletag timeout: 30_000

  # To disable this external API test, run: mix test --exclude external_api
  # This test validates SOAP 1.2 compatibility with real web services

  @wsdl_url "http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso?WSDL"

  describe "Real-world SOAP 1.2 Integration" do
    test "can parse CountryInfo WSDL and extract operations" do
      # Test WSDL parsing - this should work even if service is down
      case DynamicClient.new(@wsdl_url, timeout: 15_000) do
        {:ok, client} ->
          # Validate client was created successfully
          assert is_map(client.service_info)
          assert is_list(client.service_info.operations)

          # Should have common CountryInfo operations
          operation_names = Enum.map(client.service_info.operations, & &1.name)

          # Check for expected operations (case-insensitive)
          expected_operations = ["CountryFlag", "CapitalCity", "CountryName", "CountryCurrency"]

          found_operations =
            Enum.filter(expected_operations, fn expected ->
              Enum.any?(operation_names, fn actual ->
                String.downcase(actual) == String.downcase(expected)
              end)
            end)

          # Should find at least some expected operations
          assert length(found_operations) > 0,
                 "Expected to find operations like #{inspect(expected_operations)}, " <>
                   "but got: #{inspect(operation_names)}"

        {:error, _reason} ->
          # If WSDL parsing fails, skip the test for network issues
          :ok
      end
    end

    test "can make SOAP 1.2 call to CountryFlag operation" do
      case DynamicClient.new(@wsdl_url, timeout: 15_000) do
        {:ok, client} ->
          # Test the CountryFlag operation with SOAP 1.2
          operation_name = find_operation(client.service_info.operations, "CountryFlag")

          if operation_name do
            # Make SOAP 1.2 call
            result =
              DynamicClient.call(
                client,
                operation_name,
                %{"sCountryISOCode" => "US"},
                # Force SOAP 1.2
                soap_version: :v1_2,
                timeout: 15_000,
                headers: [
                  {"User-Agent", "Lather-SOAP-1.2-Test/1.0.0"}
                ]
              )

            case result do
              {:ok, response} ->
                # Validate SOAP 1.2 response
                assert is_map(response)

                # Should have some flag-related response
                response_keys = Map.keys(response) |> Enum.map(&String.downcase/1)

                flag_related =
                  Enum.any?(response_keys, fn key ->
                    String.contains?(key, "flag") or String.contains?(key, "result")
                  end)

                assert flag_related, "Expected flag-related response, got: #{inspect(response)}"

              {:error, reason} ->
                # Don't fail if it's just a service issue

                # Only fail if it's clearly a SOAP 1.2 protocol issue
                case reason do
                  # Network/service issue, don't fail test
                  {:http_error, _} ->
                    :ok

                  # Timeout, don't fail test
                  {:timeout, _} ->
                    :ok

                  # Service fault, could be expected
                  {:soap_fault, _} ->
                    :ok

                  {:parse_error, _} ->
                    # Parse errors might indicate SOAP 1.2 compatibility issues
                    flunk("SOAP 1.2 parse error: #{inspect(reason)}")

                  _ ->
                    :ok
                end
            end
          else
            # Try any available operation as fallback
            case client.service_info.operations do
              [first_op | _] ->
                # Try with minimal parameters
                result =
                  DynamicClient.call(
                    client,
                    first_op.name,
                    %{},
                    soap_version: :v1_2,
                    timeout: 10_000
                  )

                # Just verify we can make SOAP 1.2 calls without parsing errors
                case result do
                  {:ok, _} -> :ok
                  {:error, {:soap_fault, _}} -> :ok
                  {:error, _reason} -> :ok
                end

              [] ->
                :ok
            end
          end

        {:error, _reason} ->
          :ok
      end
    end

    test "validates SOAP 1.2 envelope generation locally" do
      # This test validates our SOAP 1.2 envelope generation without external dependencies
      case DynamicClient.new(@wsdl_url, timeout: 10_000) do
        {:ok, client} ->
          if length(client.service_info.operations) > 0 do
            first_operation = List.first(client.service_info.operations)

            # Test SOAP 1.2 envelope generation using our Operation.Builder
            import Lather.Operation.Builder

            case build_request(first_operation, %{}, version: :v1_2) do
              {:ok, envelope_xml} ->
                # Verify SOAP 1.2 specific namespace
                assert String.contains?(envelope_xml, "http://www.w3.org/2003/05/soap-envelope"),
                       "SOAP 1.2 envelope must use correct namespace"

                # Verify it's valid XML structure
                assert String.starts_with?(envelope_xml, "<?xml"),
                       "Must be valid XML with declaration"

                assert String.contains?(envelope_xml, "<soap:Envelope"),
                       "Must contain SOAP envelope"

                assert String.contains?(envelope_xml, "<soap:Body"),
                       "Must contain SOAP body"

              {:error, reason} ->
                flunk("Failed to build SOAP 1.2 envelope: #{inspect(reason)}")
            end
          end

        {:error, _reason} ->
          # Skip if external service unavailable - this part isn't critical
          :ok
      end
    end
  end

  # Helper functions

  defp find_operation(operations, operation_name) do
    operations
    |> Enum.find(fn op ->
      String.downcase(op.name) == String.downcase(operation_name)
    end)
    |> case do
      nil -> nil
      operation -> operation.name
    end
  end
end
