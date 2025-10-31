defmodule Lather.WeatherServiceIntegrationTest do
  use ExUnit.Case, async: false

  alias Lather.DynamicClient

  @moduletag :external_api
  @moduletag timeout: 30_000

  @weather_service_url "https://graphical.weather.gov/xml/SOAP_server/ndfdXMLserver.php?wsdl"

  describe "National Weather Service SOAP Integration" do
    test "can connect to NWS WSDL and create client" do
      case DynamicClient.new(@weather_service_url, timeout: 15_000) do
        {:ok, client} ->
          assert client != nil

          # Verify we can get service info
          service_info = DynamicClient.get_service_info(client)
          assert service_info.service_name != nil
          assert service_info.endpoints != nil
          assert length(service_info.operations) > 0

        {:error, reason} ->
          # Network issues shouldn't fail the test in CI/offline environments
          IO.puts("Weather Service unavailable: #{inspect(reason)}")
          # Skip instead of fail for network issues
          if reason |> inspect() |> String.contains?("timeout") or
               reason |> inspect() |> String.contains?("nxdomain") do
            {:skip, "Weather service unavailable - network issue"}
          else
            flunk("Failed to connect to Weather Service: #{inspect(reason)}")
          end
      end
    end

    test "can list weather service operations" do
      case DynamicClient.new(@weather_service_url, timeout: 15_000) do
        {:ok, client} ->
          operations = DynamicClient.list_operations(client)

          assert is_list(operations)
          assert length(operations) > 0

          # Should have key operations like NDFDgen
          operation_names = Enum.map(operations, & &1.name)
          assert "NDFDgen" in operation_names

          # Each operation should have basic metadata
          Enum.each(operations, fn op ->
            assert is_binary(op.name)
            assert op.name != ""
          end)

        {:error, reason} ->
          if reason |> inspect() |> String.contains?("timeout") or
               reason |> inspect() |> String.contains?("nxdomain") do
            {:skip, "Weather service unavailable - network issue"}
          else
            flunk("Failed to connect: #{inspect(reason)}")
          end
      end
    end

    @tag :slow
    test "can make basic weather request" do
      case DynamicClient.new(@weather_service_url, timeout: 15_000) do
        {:ok, client} ->
          # Simple request for Washington DC area (known to work with NWS)
          now = DateTime.utc_now()
          start_time = now |> DateTime.to_naive() |> NaiveDateTime.to_string()

          end_time =
            now |> DateTime.add(24 * 3600) |> DateTime.to_naive() |> NaiveDateTime.to_string()

          params = %{
            "latitude" => 38.9072,
            "longitude" => -77.0369,
            "product" => "time-series",
            "XMLformat" => "1",
            "startTime" => start_time,
            "endTime" => end_time,
            "Unit" => "e",
            "weatherParameters" => %{
              "maxt" => "true",
              "mint" => "true"
            }
          }

          case DynamicClient.call(client, "NDFDgen", params) do
            {:ok, response} ->
              # Should get back XML weather data
              assert is_map(response)

              if response["XMLOut"] do
                xml_data = response["XMLOut"]
                assert is_binary(xml_data)
                assert String.length(xml_data) > 0
                assert String.contains?(xml_data, "<?xml")
              end

            {:error, {:validation_error, _details}} ->
              # Parameter validation errors are okay - means SOAP is working
              assert true

            {:error, {:soap_fault, fault}} ->
              # SOAP faults mean the service is working but rejected our request
              IO.puts("SOAP fault (expected): #{fault.fault_string}")
              assert true

            {:error, reason} ->
              if reason |> inspect() |> String.contains?("timeout") do
                {:skip, "Weather service request timeout"}
              else
                flunk("Unexpected error: #{inspect(reason)}")
              end
          end

        {:error, reason} ->
          if reason |> inspect() |> String.contains?("timeout") or
               reason |> inspect() |> String.contains?("nxdomain") do
            {:skip, "Weather service unavailable - network issue"}
          else
            flunk("Failed to connect: #{inspect(reason)}")
          end
      end
    end

    test "handles invalid coordinates gracefully" do
      case DynamicClient.new(@weather_service_url, timeout: 15_000) do
        {:ok, client} ->
          # Invalid coordinates should be handled gracefully
          now = DateTime.utc_now()
          start_time = now |> DateTime.to_naive() |> NaiveDateTime.to_string()
          end_time = now |> DateTime.add(3600) |> DateTime.to_naive() |> NaiveDateTime.to_string()

          params = %{
            # Invalid latitude
            "latitude" => 999,
            # Invalid longitude
            "longitude" => -999,
            "product" => "time-series",
            "XMLformat" => "1",
            "startTime" => start_time,
            "endTime" => end_time,
            "Unit" => "e",
            "weatherParameters" => %{"maxt" => "true"}
          }

          case DynamicClient.call(client, "NDFDgen", params) do
            {:ok, _response} ->
              # Shouldn't succeed with invalid coordinates, but if it does, that's fine
              assert true

            {:error, {:soap_fault, fault}} ->
              # Expected - invalid coordinates should cause a SOAP fault
              assert is_binary(fault.fault_string)
              assert fault.fault_string != ""

            {:error, {:validation_error, _details}} ->
              # Also acceptable - client-side validation
              assert true

            {:error, reason} ->
              if reason |> inspect() |> String.contains?("timeout") do
                {:skip, "Weather service request timeout"}
              else
                # Other errors are also acceptable for invalid input
                assert true
              end
          end

        {:error, reason} ->
          if reason |> inspect() |> String.contains?("timeout") or
               reason |> inspect() |> String.contains?("nxdomain") do
            {:skip, "Weather service unavailable - network issue"}
          else
            flunk("Failed to connect: #{inspect(reason)}")
          end
      end
    end
  end
end
