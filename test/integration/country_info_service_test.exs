defmodule Lather.Integration.CountryInfoServiceTest do
  use ExUnit.Case, async: false
  alias Lather.DynamicClient

  @moduletag :external_api
  @moduletag timeout: 30_000

  @wsdl_url "http://webservices.oorsprong.org/websamples.countryinfo/CountryInfoService.wso?WSDL"
  @timeout 15_000

  describe "Country Info Service Integration" do
    setup do
      case DynamicClient.new(@wsdl_url, timeout: @timeout) do
        {:ok, client} ->
          {:ok, client: client}

        {:error, reason} ->
          # Skip tests if service is unavailable
          {:skip, "Service unavailable: #{inspect(reason)}"}
      end
    end

    test "connects to Country Info Service and parses WSDL", %{client: client} do
      service_info = DynamicClient.get_service_info(client)

      assert service_info.service_name == "CountryInfoService"
      assert length(service_info.operations) > 15
      assert length(service_info.endpoints) > 0

      # Verify key operations are present
      operation_names = Enum.map(service_info.operations, & &1.name)
      assert "ListOfCountryNamesByName" in operation_names
      assert "FullCountryInfo" in operation_names
      assert "ListOfCurrenciesByName" in operation_names
      assert "ListOfContinentsByName" in operation_names
    end

    test "lists all countries by name", %{client: client} do
      case DynamicClient.call(client, "ListOfCountryNamesByName", %{"parameters" => %{}}) do
        {:ok, response} ->
          countries =
            get_in(response, [
              "m:ListOfCountryNamesByNameResponse",
              "m:ListOfCountryNamesByNameResult",
              "m:tCountryCodeAndName"
            ])

          assert is_list(countries)
          # Should have many countries
          assert length(countries) > 200

          # Verify structure of country entries
          first_country = List.first(countries)
          assert is_map(first_country)
          assert Map.has_key?(first_country, "m:sISOCode")
          assert Map.has_key?(first_country, "m:sName")
          assert String.length(first_country["m:sISOCode"]) == 2

        {:error, reason} ->
          flunk("Failed to list countries: #{inspect(reason)}")
      end
    end

    test "gets full country information for specific country", %{client: client} do
      # Test with United States
      country_code = "US"

      case DynamicClient.call(client, "FullCountryInfo", %{
             "parameters" => %{"sCountryISOCode" => country_code}
           }) do
        {:ok, response} ->
          country_info =
            get_in(response, ["m:FullCountryInfoResponse", "m:FullCountryInfoResult"])

          assert is_map(country_info)
          assert country_info["m:sISOCode"] == "US"
          assert country_info["m:sName"] == "United States"
          assert country_info["m:sCapitalCity"] == "Washington"
          assert country_info["m:sPhoneCode"] == "1"
          assert country_info["m:sCurrencyISOCode"] == "USD"

          # Verify languages structure
          languages = country_info["m:Languages"]["m:tLanguage"]
          assert is_list(languages) or is_map(languages)

          if is_list(languages) do
            first_language = List.first(languages)
            assert Map.has_key?(first_language, "m:sISOCode")
            assert Map.has_key?(first_language, "m:sName")
          end

        {:error, reason} ->
          flunk("Failed to get country info: #{inspect(reason)}")
      end
    end

    test "lists currencies by name", %{client: client} do
      case DynamicClient.call(client, "ListOfCurrenciesByName", %{"parameters" => %{}}) do
        {:ok, response} ->
          currencies =
            get_in(response, [
              "m:ListOfCurrenciesByNameResponse",
              "m:ListOfCurrenciesByNameResult",
              "m:tCurrency"
            ])

          assert is_list(currencies)
          # Should have many currencies
          assert length(currencies) > 100

          # Verify structure
          first_currency = List.first(currencies)
          assert is_map(first_currency)
          assert Map.has_key?(first_currency, "m:sISOCode")
          assert Map.has_key?(first_currency, "m:sName")
          assert String.length(first_currency["m:sISOCode"]) == 3

        {:error, reason} ->
          flunk("Failed to list currencies: #{inspect(reason)}")
      end
    end

    test "finds countries using specific currency", %{client: client} do
      # Test with Euro
      currency_code = "EUR"

      case DynamicClient.call(client, "CountriesUsingCurrency", %{
             "parameters" => %{"sISOCurrencyCode" => currency_code}
           }) do
        {:ok, response} ->
          countries =
            get_in(response, [
              "m:CountriesUsingCurrencyResponse",
              "m:CountriesUsingCurrencyResult",
              "m:tCountryCodeAndName"
            ])

          # Handle both single country and multiple countries responses
          countries = if is_list(countries), do: countries, else: [countries]

          # Many countries use Euro
          assert length(countries) > 10

          # Verify structure
          first_country = List.first(countries)
          assert is_map(first_country)
          assert Map.has_key?(first_country, "m:sISOCode")
          assert Map.has_key?(first_country, "m:sName")

        {:error, reason} ->
          flunk("Failed to find countries using currency: #{inspect(reason)}")
      end
    end

    test "lists continents", %{client: client} do
      case DynamicClient.call(client, "ListOfContinentsByName", %{"parameters" => %{}}) do
        {:ok, response} ->
          continents =
            get_in(response, [
              "m:ListOfContinentsByNameResponse",
              "m:ListOfContinentsByNameResult",
              "m:tContinent"
            ])

          assert is_list(continents)
          # Should have major continents
          assert length(continents) >= 6

          # Verify structure
          first_continent = List.first(continents)
          assert is_map(first_continent)
          assert Map.has_key?(first_continent, "m:sCode")
          assert Map.has_key?(first_continent, "m:sName")

          # Verify some expected continents are present
          continent_names = Enum.map(continents, & &1["m:sName"])
          assert "Europe" in continent_names
          assert "Asia" in continent_names

        {:error, reason} ->
          flunk("Failed to list continents: #{inspect(reason)}")
      end
    end

    test "gets countries grouped by continent", %{client: client} do
      case DynamicClient.call(client, "ListOfCountryNamesGroupedByContinent", %{
             "parameters" => %{}
           }) do
        {:ok, response} ->
          continent_groups =
            get_in(response, [
              "m:ListOfCountryNamesGroupedByContinentResponse",
              "m:ListOfCountryNamesGroupedByContinentResult",
              "m:tCountryCodeAndNameGroupedByContinent"
            ])

          assert is_list(continent_groups)
          assert length(continent_groups) >= 6

          # Verify structure of first group
          first_group = List.first(continent_groups)
          assert is_map(first_group)
          assert Map.has_key?(first_group, "m:Continent")
          assert Map.has_key?(first_group, "m:CountryCodeAndNames")

          continent = first_group["m:Continent"]
          assert Map.has_key?(continent, "m:sCode")
          assert Map.has_key?(continent, "m:sName")

        {:error, reason} ->
          flunk("Failed to get countries by continent: #{inspect(reason)}")
      end
    end

    test "lists languages", %{client: client} do
      case DynamicClient.call(client, "ListOfLanguagesByName", %{"parameters" => %{}}) do
        {:ok, response} ->
          languages =
            get_in(response, [
              "m:ListOfLanguagesByNameResponse",
              "m:ListOfLanguagesByNameResult",
              "m:tLanguage"
            ])

          assert is_list(languages)
          # Should have many languages
          assert length(languages) > 100

          # Verify structure
          first_language = List.first(languages)
          assert is_map(first_language)
          assert Map.has_key?(first_language, "m:sISOCode")
          assert Map.has_key?(first_language, "m:sName")

        {:error, reason} ->
          flunk("Failed to list languages: #{inspect(reason)}")
      end
    end

    test "handles specific lookups correctly", %{client: client} do
      test_cases = [
        {"CountryName", %{"parameters" => %{"sCountryISOCode" => "DE"}}, "Germany"},
        {"CapitalCity", %{"parameters" => %{"sCountryISOCode" => "FR"}}, "Paris"},
        {"CountryIntPhoneCode", %{"parameters" => %{"sCountryISOCode" => "GB"}}, "44"},
        {"CurrencyName", %{"parameters" => %{"sCurrencyISOCode" => "JPY"}}, "Yen"}
      ]

      Enum.each(test_cases, fn {operation, params, expected_content} ->
        case DynamicClient.call(client, operation, params) do
          {:ok, response} ->
            response_key = "m:#{operation}Response"
            result_key = "m:#{operation}Result"
            result = get_in(response, [response_key, result_key])

            assert is_binary(result) and result != ""

            if expected_content do
              assert String.contains?(String.downcase(result), String.downcase(expected_content))
            end

          {:error, reason} ->
            flunk("Operation #{operation} failed: #{inspect(reason)}")
        end
      end)
    end

    test "handles invalid inputs gracefully", %{client: client} do
      invalid_test_cases = [
        {"CountryName", %{"parameters" => %{"sCountryISOCode" => "XX"}}},
        {"CurrencyName", %{"parameters" => %{"sCurrencyISOCode" => "INVALID"}}},
        {"LanguageName", %{"parameters" => %{"sISOCode" => "zz"}}}
      ]

      Enum.each(invalid_test_cases, fn {operation, params} ->
        case DynamicClient.call(client, operation, params) do
          {:ok, response} ->
            # Should return empty result for invalid inputs
            response_key = "m:#{operation}Response"
            result_key = "m:#{operation}Result"
            result = get_in(response, [response_key, result_key])

            # Empty string or meaningful error message is acceptable for invalid lookups
            assert result == "" or is_nil(result) or
                     String.contains?(String.downcase(result), "not found") or
                     String.contains?(String.downcase(result), "database") or
                     String.contains?(String.downcase(result), "invalid") or
                     String.contains?(String.downcase(result), "error")

          {:error, _reason} ->
            # Network/parsing errors are also acceptable
            assert true
        end
      end)
    end

    test "verifies SOAP service technical details", %{client: client} do
      service_info = DynamicClient.get_service_info(client)

      # Check that operations have expected SOAP style and use
      Enum.each(service_info.operations, fn operation ->
        assert operation.style == "document"
        assert operation.input.use == "literal"
        assert operation.output.use == "literal"
      end)

      # Check that endpoints are valid
      Enum.each(service_info.endpoints, fn endpoint ->
        assert endpoint.address.type == :soap
        assert String.starts_with?(endpoint.address.location, "http")
      end)
    end

    test "performs bulk operations efficiently", %{client: client} do
      start_time = System.monotonic_time(:millisecond)

      # Test multiple operations in sequence
      operations = [
        "ListOfCountryNamesByName",
        "ListOfCurrenciesByName",
        "ListOfContinentsByName",
        "ListOfLanguagesByName"
      ]

      results =
        Enum.map(operations, fn operation ->
          case DynamicClient.call(client, operation, %{"parameters" => %{}}) do
            {:ok, response} -> {:ok, operation, response}
            {:error, reason} -> {:error, operation, reason}
          end
        end)

      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time

      # All operations should succeed
      Enum.each(results, fn
        {:ok, operation, _response} ->
          assert true, "Operation #{operation} succeeded"

        {:error, operation, reason} ->
          flunk("Operation #{operation} failed: #{inspect(reason)}")
      end)

      # Should complete in reasonable time (adjust if needed based on network)
      assert total_time < 30_000, "Operations took too long: #{total_time}ms"
    end
  end
end
