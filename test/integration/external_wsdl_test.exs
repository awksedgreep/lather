defmodule Lather.Integration.ExternalWsdlTest do
  @moduledoc """
  Integration tests that connect to real external SOAP services to verify
  the Lather client works with real-world WSDLs.

  These tests are excluded by default to avoid hitting public services on every test run.
  Run with: mix test test/integration/external_wsdl_test.exs --include external_api

  Purpose: Catch integration boundary issues that unit tests miss (e.g., the client
  passes all 575 unit tests but can't actually talk to real SOAP servers).
  """

  use ExUnit.Case, async: false

  alias Lather.DynamicClient

  @moduletag :external_api
  @moduletag timeout: 60_000

  # DNB Online Calculator - A popular, stable public SOAP test service
  # Operations: Add, Subtract, Multiply, Divide
  @calculator_wsdl_url "http://www.dneonline.com/calculator.asmx?wsdl"

  @timeout 20_000

  describe "DNB Calculator Service - Real SOAP Integration" do
    setup do
      case connect_to_service(@calculator_wsdl_url) do
        {:ok, client} ->
          {:ok, client: client}

        {:error, reason} ->
          {:skip, "Calculator service unavailable: #{inspect(reason)}"}
      end
    end

    test "connects to Calculator service and parses WSDL successfully", %{client: client} do
      service_info = DynamicClient.get_service_info(client)

      # Verify service metadata was parsed correctly
      assert service_info.service_name != nil
      assert is_binary(service_info.service_name)
      assert String.length(service_info.service_name) > 0

      # Should have 4 calculator operations
      assert length(service_info.operations) >= 4

      # Verify operations are present
      operation_names = Enum.map(service_info.operations, & &1.name)
      assert "Add" in operation_names, "Expected 'Add' operation in #{inspect(operation_names)}"
      assert "Subtract" in operation_names, "Expected 'Subtract' operation in #{inspect(operation_names)}"
      assert "Multiply" in operation_names, "Expected 'Multiply' operation in #{inspect(operation_names)}"
      assert "Divide" in operation_names, "Expected 'Divide' operation in #{inspect(operation_names)}"

      # Verify endpoint info
      assert length(service_info.endpoints) > 0
      first_endpoint = List.first(service_info.endpoints)
      assert is_map(first_endpoint)
      assert first_endpoint.address != nil
    end

    test "list_operations returns expected operations", %{client: client} do
      operations = DynamicClient.list_operations(client)

      assert is_list(operations)
      assert length(operations) >= 4

      # Each operation should have metadata
      Enum.each(operations, fn op ->
        assert is_map(op)
        assert Map.has_key?(op, :name) or Map.has_key?(op, "name")
      end)
    end

    test "performs Add operation with real calculation", %{client: client} do
      # Test: 10 + 25 = 35
      params = %{
        "parameters" => %{
          "intA" => "10",
          "intB" => "25"
        }
      }

      case DynamicClient.call(client, "Add", params) do
        {:ok, response} ->
          # Response structure may vary - try different access patterns
          result = extract_add_result(response)

          assert result != nil, "Could not extract result from response: #{inspect(response)}"
          assert result == "35" or result == 35,
            "Expected Add(10, 25) = 35, got: #{inspect(result)}"

        {:error, reason} ->
          flunk("Add operation failed: #{inspect(reason)}")
      end
    end

    test "performs Subtract operation with real calculation", %{client: client} do
      # Test: 100 - 37 = 63
      params = %{
        "parameters" => %{
          "intA" => "100",
          "intB" => "37"
        }
      }

      case DynamicClient.call(client, "Subtract", params) do
        {:ok, response} ->
          result = extract_subtract_result(response)

          assert result != nil, "Could not extract result from response: #{inspect(response)}"
          assert result == "63" or result == 63,
            "Expected Subtract(100, 37) = 63, got: #{inspect(result)}"

        {:error, reason} ->
          flunk("Subtract operation failed: #{inspect(reason)}")
      end
    end

    test "performs Multiply operation with real calculation", %{client: client} do
      # Test: 7 * 8 = 56
      params = %{
        "parameters" => %{
          "intA" => "7",
          "intB" => "8"
        }
      }

      case DynamicClient.call(client, "Multiply", params) do
        {:ok, response} ->
          result = extract_multiply_result(response)

          assert result != nil, "Could not extract result from response: #{inspect(response)}"
          assert result == "56" or result == 56,
            "Expected Multiply(7, 8) = 56, got: #{inspect(result)}"

        {:error, reason} ->
          flunk("Multiply operation failed: #{inspect(reason)}")
      end
    end

    test "performs Divide operation with real calculation", %{client: client} do
      # Test: 100 / 4 = 25
      params = %{
        "parameters" => %{
          "intA" => "100",
          "intB" => "4"
        }
      }

      case DynamicClient.call(client, "Divide", params) do
        {:ok, response} ->
          result = extract_divide_result(response)

          assert result != nil, "Could not extract result from response: #{inspect(response)}"
          assert result == "25" or result == 25,
            "Expected Divide(100, 4) = 25, got: #{inspect(result)}"

        {:error, reason} ->
          flunk("Divide operation failed: #{inspect(reason)}")
      end
    end

    test "handles multiple sequential operations correctly", %{client: client} do
      # Perform a series of calculations to ensure client state is maintained correctly
      operations = [
        {"Add", 5, 3, 8},
        {"Subtract", 20, 7, 13},
        {"Multiply", 6, 9, 54},
        {"Divide", 81, 9, 9}
      ]

      Enum.each(operations, fn {op_name, a, b, expected} ->
        params = %{
          "parameters" => %{
            "intA" => to_string(a),
            "intB" => to_string(b)
          }
        }

        case DynamicClient.call(client, op_name, params) do
          {:ok, response} ->
            result = extract_result(response, op_name)
            result_int = parse_result(result)

            assert result_int == expected,
              "#{op_name}(#{a}, #{b}) expected #{expected}, got #{inspect(result)}"

          {:error, reason} ->
            flunk("#{op_name}(#{a}, #{b}) failed: #{inspect(reason)}")
        end
      end)
    end

    test "verifies response structure matches expected SOAP patterns", %{client: client} do
      params = %{
        "parameters" => %{
          "intA" => "1",
          "intB" => "1"
        }
      }

      case DynamicClient.call(client, "Add", params) do
        {:ok, response} ->
          # Response should be a map
          assert is_map(response)

          # Should have some form of response wrapper
          response_keys = Map.keys(response)
          assert length(response_keys) > 0, "Response should not be empty"

          # Should contain the result key
          assert Map.has_key?(response, "AddResult"),
            "Expected 'AddResult' key in response: #{inspect(response)}"

        {:error, reason} ->
          flunk("Call failed: #{inspect(reason)}")
      end
    end
  end

  describe "Service Connectivity Health Check" do
    @tag timeout: 30_000
    test "verifies calculator service is reachable and responds" do
      case connect_to_service(@calculator_wsdl_url) do
        {:ok, client} ->
          # Just verify we can get service info - proves WSDL parsing works
          service_info = DynamicClient.get_service_info(client)
          assert service_info != nil
          assert service_info.operations != nil
          assert length(service_info.operations) > 0

          # Verify service was parsed successfully
          assert service_info.service_name == "Calculator"
          assert "Add" in Enum.map(service_info.operations, & &1.name)

        {:error, _reason} ->
          # Skip rather than fail - external service may be temporarily down
          flunk("External service unavailable - network may be down")
      end
    end
  end

  describe "Error Handling with External Service" do
    setup do
      case connect_to_service(@calculator_wsdl_url) do
        {:ok, client} ->
          {:ok, client: client}

        {:error, reason} ->
          {:skip, "Service unavailable: #{inspect(reason)}"}
      end
    end

    test "handles calling non-existent operation gracefully", %{client: client} do
      result = DynamicClient.call(client, "NonExistentOperation", %{})

      assert {:error, error} = result
      # Should be an operation not found error, not a crash
      assert error != nil
    end

    test "get_operation_info for non-existent operation returns error", %{client: client} do
      result = DynamicClient.get_operation_info(client, "FakeOperation")

      assert {:error, _} = result
    end

    test "get_operation_info for existing operation returns info", %{client: client} do
      result = DynamicClient.get_operation_info(client, "Add")

      case result do
        {:ok, info} ->
          assert is_map(info)
          # Should have name in the info
          assert info[:name] == "Add" or info["name"] == "Add" or
                 Map.get(info, :name, nil) != nil

        {:error, reason} ->
          flunk("get_operation_info failed for existing operation: #{inspect(reason)}")
      end
    end
  end

  describe "WSDL Analysis Quality" do
    setup do
      case connect_to_service(@calculator_wsdl_url) do
        {:ok, client} ->
          {:ok, client: client}

        {:error, reason} ->
          {:skip, "Service unavailable: #{inspect(reason)}"}
      end
    end

    test "generate_service_report produces readable output", %{client: client} do
      report = DynamicClient.generate_service_report(client)

      assert is_binary(report)
      assert String.length(report) > 100, "Report seems too short"

      # Report should mention the operations
      assert String.contains?(report, "Add") or String.contains?(String.downcase(report), "add")

      # Report should contain key sections
      assert String.contains?(report, "Calculator")
      assert String.contains?(report, "Endpoint") or String.contains?(report, "endpoint")
    end

    test "service has valid namespace", %{client: client} do
      service_info = DynamicClient.get_service_info(client)

      assert service_info.target_namespace != nil
      assert is_binary(service_info.target_namespace)
      assert String.length(service_info.target_namespace) > 0
    end

    test "operations have correct binding information", %{client: client} do
      service_info = DynamicClient.get_service_info(client)

      Enum.each(service_info.operations, fn operation ->
        # Each operation should have a name
        assert operation.name != nil
        assert is_binary(operation.name)

        # Operation should have input/output specifications
        assert operation.input != nil
        assert operation.output != nil
      end)
    end
  end

  # Helper Functions

  defp connect_to_service(wsdl_url) do
    try do
      DynamicClient.new(wsdl_url, timeout: @timeout)
    rescue
      e ->
        {:error, {:exception, Exception.message(e)}}
    catch
      :exit, reason ->
        {:error, {:exit, reason}}
    end
  end

  # Result extractors - handle various response structures
  defp extract_add_result(response) do
    extract_result(response, "Add")
  end

  defp extract_subtract_result(response) do
    extract_result(response, "Subtract")
  end

  defp extract_multiply_result(response) do
    extract_result(response, "Multiply")
  end

  defp extract_divide_result(response) do
    extract_result(response, "Divide")
  end

  defp extract_result(response, operation) do
    # Try various response structure patterns
    # Pattern 1: Standard SOAP with namespace prefixes
    get_in(response, ["m:#{operation}Response", "m:#{operation}Result"]) ||
    # Pattern 2: Without namespace prefix
    get_in(response, ["#{operation}Response", "#{operation}Result"]) ||
    # Pattern 3: soap prefix
    get_in(response, ["soap:#{operation}Response", "soap:#{operation}Result"]) ||
    # Pattern 4: tns prefix
    get_in(response, ["tns:#{operation}Response", "tns:#{operation}Result"]) ||
    # Pattern 5: Direct result key (less common)
    Map.get(response, "#{operation}Result") ||
    Map.get(response, "result") ||
    Map.get(response, "Result") ||
    # Pattern 6: Nested in body
    extract_from_nested_response(response, operation)
  end

  defp extract_from_nested_response(response, operation) when is_map(response) do
    # Search for the result in nested structures
    Enum.find_value(response, fn
      {key, value} when is_map(value) ->
        if String.contains?(key, "#{operation}Response") or String.contains?(key, "Response") do
          find_result_in_map(value, operation)
        else
          extract_from_nested_response(value, operation)
        end

      {key, value} when is_binary(value) ->
        if String.contains?(key, "Result") do
          value
        else
          nil
        end

      _ ->
        nil
    end)
  end

  defp extract_from_nested_response(_, _), do: nil

  defp find_result_in_map(map, operation) when is_map(map) do
    Enum.find_value(map, fn
      {key, value} when is_binary(value) ->
        if String.contains?(key, "Result") do
          value
        else
          nil
        end

      {_key, value} when is_map(value) ->
        find_result_in_map(value, operation)

      _ ->
        nil
    end)
  end

  defp find_result_in_map(_, _), do: nil

  defp parse_result(result) when is_binary(result) do
    case Integer.parse(result) do
      {int, _} -> int
      :error -> result
    end
  end

  defp parse_result(result) when is_integer(result), do: result
  defp parse_result(result), do: result
end
