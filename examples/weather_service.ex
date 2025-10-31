defmodule WeatherServiceExample do
  @moduledoc """
  Example of using Lather with a public weather SOAP service.

  This example demonstrates:
  - Connecting to a public SOAP service
  - Making basic SOAP calls
  - Handling responses and errors
  """

  @weather_service_wsdl "http://www.webservicex.net/globalweather.asmx?WSDL"

  def run do
    IO.puts("Weather Service Example")
    IO.puts("======================")

    case connect_to_service() do
      {:ok, client} ->
        demo_operations(client)
      {:error, error} ->
        IO.puts("Failed to connect: #{inspect(error)}")
    end
  end

  defp connect_to_service do
    IO.puts("Connecting to weather service...")

    case Lather.DynamicClient.new(@weather_service_wsdl, timeout: 30_000) do
      {:ok, client} ->
        IO.puts("✓ Connected successfully!")
        {:ok, client}

      {:error, error} ->
        IO.puts("✗ Connection failed: #{Lather.Error.format_error(error)}")
        {:error, error}
    end
  end

  defp demo_operations(client) do
    IO.puts("\nAvailable operations:")
    operations = Lather.DynamicClient.list_operations(client)
    Enum.each(operations, fn op -> IO.puts("  - #{op}") end)

    IO.puts("\nGetting weather for cities...")

    cities = [
      {"New York", "United States"},
      {"London", "United Kingdom"},
      {"Tokyo", "Japan"}
    ]

    Enum.each(cities, fn {city, country} ->
      get_weather(client, city, country)
    end)

    IO.puts("\nGetting list of cities...")
    get_cities(client, "United States")
  end

  defp get_weather(client, city, country) do
    IO.puts("\n🌤️  Getting weather for #{city}, #{country}...")

    params = %{
      "CityName" => city,
      "CountryName" => country
    }

    case Lather.DynamicClient.call(client, "GetWeather", params) do
      {:ok, response} ->
        IO.puts("✓ Weather data received:")
        display_weather_response(response)

      {:error, %{type: :soap_fault} = fault} ->
        IO.puts("✗ SOAP Fault: #{fault.fault_string}")

      {:error, error} ->
        IO.puts("✗ Error: #{Lather.Error.format_error(error)}")
    end
  end

  defp get_cities(client, country) do
    IO.puts("\n🏙️  Getting cities in #{country}...")

    params = %{"CountryName" => country}

    case Lather.DynamicClient.call(client, "GetCitiesByCountry", params) do
      {:ok, response} ->
        IO.puts("✓ Cities data received:")
        display_cities_response(response)

      {:error, %{type: :soap_fault} = fault} ->
        IO.puts("✗ SOAP Fault: #{fault.fault_string}")

      {:error, error} ->
        IO.puts("✗ Error: #{Lather.Error.format_error(error)}")
    end
  end

  defp display_weather_response(response) do
    case response do
      %{"GetWeatherResult" => weather_xml} when is_binary(weather_xml) ->
        if String.contains?(weather_xml, "Data Not Found") do
          IO.puts("   No weather data available for this location")
        else
          # Parse the weather XML for display
          IO.puts("   Weather XML: #{String.slice(weather_xml, 0, 200)}...")
        end

      data ->
        IO.puts("   #{inspect(data, pretty: true)}")
    end
  end

  defp display_cities_response(response) do
    case response do
      %{"GetCitiesByCountryResult" => cities_xml} when is_binary(cities_xml) ->
        if String.contains?(cities_xml, "Data Not Found") do
          IO.puts("   No cities data available")
        else
          # Parse the cities XML and show first few
          lines = String.split(cities_xml, "\n") |> Enum.take(5)
          IO.puts("   Cities (showing first few lines):")
          Enum.each(lines, fn line -> IO.puts("     #{line}") end)
        end

      data ->
        IO.puts("   #{inspect(data, pretty: true)}")
    end
  end

  # Helper to show operation details
  def show_operation_details(operation_name) do
    case Lather.DynamicClient.new(@weather_service_wsdl) do
      {:ok, client} ->
        case Lather.DynamicClient.get_operation_info(client, operation_name) do
          {:ok, info} ->
            IO.puts("Operation: #{operation_name}")
            IO.puts("Input parameters:")
            Enum.each(info.input_parts, fn part ->
              required = if part.required, do: " (required)", else: " (optional)"
              IO.puts("  - #{part.name}: #{part.type}#{required}")
            end)

            IO.puts("Output:")
            Enum.each(info.output_parts, fn part ->
              IO.puts("  - #{part.name}: #{part.type}")
            end)

          {:error, error} ->
            IO.puts("Error getting operation info: #{inspect(error)}")
        end

      {:error, error} ->
        IO.puts("Error connecting: #{inspect(error)}")
    end
  end

  # Async example - get weather for multiple cities concurrently
  def get_weather_async(cities) do
    {:ok, client} = Lather.DynamicClient.new(@weather_service_wsdl)

    tasks = Enum.map(cities, fn {city, country} ->
      Task.async(fn ->
        params = %{"CityName" => city, "CountryName" => country}
        {city, Lather.DynamicClient.call(client, "GetWeather", params)}
      end)
    end)

    results = Task.await_many(tasks, 30_000)

    IO.puts("Async weather results:")
    Enum.each(results, fn {city, result} ->
      case result do
        {:ok, _weather} ->
          IO.puts("✓ #{city}: Weather data received")
        {:error, _error} ->
          IO.puts("✗ #{city}: Failed to get weather")
      end
    end)
  end
end

# Run the example
if __name__ == :main do
  WeatherServiceExample.run()
end
