defmodule Lather.Integration.ConcurrentRequestsTest do
  @moduledoc """
  Integration tests for concurrent SOAP request handling.

  These tests verify that Lather correctly handles multiple simultaneous requests,
  ensuring response isolation, no data leakage, and proper behavior under load.
  """
  use ExUnit.Case, async: false

  # These tests require starting actual HTTP servers
  @moduletag :integration

  # Define a test service with simple operations for concurrency testing
  # Each operation includes a small built-in delay to better test concurrent execution
  defmodule ConcurrentTestService do
    use Lather.Server

    @namespace "http://test.example.com/concurrent"
    @service_name "ConcurrentTestService"

    soap_operation "Echo" do
      description "Echoes the input message"
      input do
        parameter "message", :string, required: true
      end
      output do
        parameter "echo", :string
        parameter "request_id", :string
      end
      soap_action "Echo"
    end

    soap_operation "GenerateId" do
      description "Generates a response containing the input ID"
      input do
        parameter "input_id", :string, required: true
      end
      output do
        parameter "output_id", :string
        parameter "processed_at", :string
      end
      soap_action "GenerateId"
    end

    soap_operation "Add" do
      description "Adds two numbers"
      input do
        parameter "a", :decimal, required: true
        parameter "b", :decimal, required: true
      end
      output do
        parameter "result", :decimal
        parameter "operation_id", :string
      end
      soap_action "Add"
    end

    soap_operation "Multiply" do
      description "Multiplies two numbers"
      input do
        parameter "a", :decimal, required: true
        parameter "b", :decimal, required: true
      end
      output do
        parameter "result", :decimal
        parameter "operation_id", :string
      end
      soap_action "Multiply"
    end

    soap_operation "SlowOperation" do
      description "An intentionally slow operation for testing concurrency"
      input do
        parameter "request_id", :string, required: true
        parameter "delay_ms", :integer, required: true
      end
      output do
        parameter "response_id", :string
        parameter "completed", :boolean
      end
      soap_action "SlowOperation"
    end

    def echo(params) do
      message = params["message"]

      # Small delay to better test concurrency
      Process.sleep(5)

      request_id = :crypto.strong_rand_bytes(8) |> Base.encode16()
      {:ok, %{"echo" => message, "request_id" => request_id}}
    end

    def generate_id(params) do
      input_id = params["input_id"]

      # Small delay to better test concurrency
      Process.sleep(5)

      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
      {:ok, %{"output_id" => input_id, "processed_at" => timestamp}}
    end

    def add(params) do
      a = parse_number(params["a"])
      b = parse_number(params["b"])

      # Small delay to better test concurrency
      Process.sleep(5)

      operation_id = "add-#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"
      {:ok, %{"result" => a + b, "operation_id" => operation_id}}
    end

    def multiply(params) do
      a = parse_number(params["a"])
      b = parse_number(params["b"])

      # Small delay to better test concurrency
      Process.sleep(5)

      operation_id = "mul-#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"
      {:ok, %{"result" => a * b, "operation_id" => operation_id}}
    end

    def slow_operation(params) do
      request_id = params["request_id"]
      delay_ms = parse_integer(params["delay_ms"], 100)

      Process.sleep(delay_ms)

      {:ok, %{"response_id" => request_id, "completed" => true}}
    end

    defp parse_number(val) when is_number(val), do: val

    defp parse_number(val) when is_binary(val) do
      case Float.parse(val) do
        {num, _} -> num
        :error -> String.to_integer(val)
      end
    end

    defp parse_integer(nil, default), do: default
    defp parse_integer(val, _default) when is_integer(val), do: val

    defp parse_integer(val, default) when is_binary(val) do
      case Integer.parse(val) do
        {num, _} -> num
        :error -> default
      end
    end
  end

  # Define the router at compile time
  defmodule ConcurrentTestRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    match "/soap" do
      Lather.Server.Plug.call(
        conn,
        Lather.Server.Plug.init(
          service: Lather.Integration.ConcurrentRequestsTest.ConcurrentTestService
        )
      )
    end
  end

  describe "multiple simultaneous requests to same operation" do
    setup :start_server

    test "handles multiple Echo requests concurrently", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 10_000)

      # Create 10 concurrent Echo requests with unique messages
      tasks =
        1..10
        |> Enum.map(fn i ->
          message = "concurrent-message-#{i}"

          Task.async(fn ->
            result = Lather.DynamicClient.call(client, "Echo", %{"message" => message})
            {i, message, result}
          end)
        end)

      results = Task.await_many(tasks, 15_000)

      # Verify all requests succeeded and returned correct responses
      for {i, original_message, result} <- results do
        assert {:ok, response} = result,
               "Request #{i} failed: #{inspect(result)}"

        assert response["echo"] == original_message,
               "Request #{i}: Expected echo '#{original_message}', got '#{response["echo"]}'"
      end
    end

    test "handles multiple Add requests concurrently with unique inputs", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 10_000)

      # Create requests with unique number pairs
      inputs =
        1..10
        |> Enum.map(fn i -> {i, i * 2} end)

      tasks =
        inputs
        |> Enum.map(fn {a, b} ->
          Task.async(fn ->
            result = Lather.DynamicClient.call(client, "Add", %{"a" => a, "b" => b})
            {a, b, result}
          end)
        end)

      results = Task.await_many(tasks, 15_000)

      # Verify each response matches its request
      for {a, b, result} <- results do
        assert {:ok, response} = result,
               "Add(#{a}, #{b}) failed: #{inspect(result)}"

        expected = a + b
        actual = parse_result(response["result"])

        assert actual == expected * 1.0,
               "Add(#{a}, #{b}): Expected #{expected}, got #{actual}"
      end
    end
  end

  describe "different operations called concurrently" do
    setup :start_server

    test "handles mixed operations concurrently", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 10_000)

      # Mix of different operations
      tasks = [
        Task.async(fn ->
          {:echo, Lather.DynamicClient.call(client, "Echo", %{"message" => "test1"})}
        end),
        Task.async(fn ->
          {:add, Lather.DynamicClient.call(client, "Add", %{"a" => 5, "b" => 3})}
        end),
        Task.async(fn ->
          {:multiply, Lather.DynamicClient.call(client, "Multiply", %{"a" => 4, "b" => 7})}
        end),
        Task.async(fn ->
          {:generate_id,
           Lather.DynamicClient.call(client, "GenerateId", %{"input_id" => "unique-123"})}
        end),
        Task.async(fn ->
          {:echo, Lather.DynamicClient.call(client, "Echo", %{"message" => "test2"})}
        end),
        Task.async(fn ->
          {:add, Lather.DynamicClient.call(client, "Add", %{"a" => 10, "b" => 20})}
        end)
      ]

      results = Task.await_many(tasks, 15_000)

      # Verify each operation type returned correct results
      for {op_type, result} <- results do
        assert {:ok, response} = result, "#{op_type} failed: #{inspect(result)}"

        case op_type do
          :echo ->
            assert Map.has_key?(response, "echo")

          :add ->
            assert Map.has_key?(response, "result")

          :multiply ->
            assert Map.has_key?(response, "result")

          :generate_id ->
            assert response["output_id"] == "unique-123"
        end
      end
    end

    test "interleaved Add and Multiply operations return correct results", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 10_000)

      # Interleave Add and Multiply operations
      operations = [
        {:add, 10, 5, 15},
        {:multiply, 10, 5, 50},
        {:add, 3, 7, 10},
        {:multiply, 3, 7, 21},
        {:add, 100, 200, 300},
        {:multiply, 100, 200, 20000}
      ]

      tasks =
        operations
        |> Enum.map(fn {op, a, b, expected} ->
          Task.async(fn ->
            op_name = if op == :add, do: "Add", else: "Multiply"
            result = Lather.DynamicClient.call(client, op_name, %{"a" => a, "b" => b})
            {op, a, b, expected, result}
          end)
        end)

      results = Task.await_many(tasks, 15_000)

      for {op, a, b, expected, result} <- results do
        assert {:ok, response} = result,
               "#{op}(#{a}, #{b}) failed: #{inspect(result)}"

        actual = parse_result(response["result"])

        assert actual == expected * 1.0,
               "#{op}(#{a}, #{b}): Expected #{expected}, got #{actual}"
      end
    end
  end

  describe "high volume concurrent requests" do
    setup :start_server

    test "handles 50 parallel Echo requests", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 30_000)

      # 50 concurrent requests
      request_count = 50

      tasks =
        1..request_count
        |> Enum.map(fn i ->
          message = "high-volume-message-#{i}-#{System.unique_integer([:positive])}"

          Task.async(fn ->
            result = Lather.DynamicClient.call(client, "Echo", %{"message" => message})
            {i, message, result}
          end)
        end)

      results = Task.await_many(tasks, 60_000)

      # Count successes
      successful =
        Enum.filter(results, fn {_, _, result} ->
          match?({:ok, _}, result)
        end)

      assert length(successful) == request_count,
             "Only #{length(successful)} of #{request_count} requests succeeded"

      # Verify all responses match their requests
      for {i, original_message, result} <- successful do
        {:ok, response} = result

        assert response["echo"] == original_message,
               "Request #{i}: Response mismatch"
      end
    end

    test "handles 100 parallel GenerateId requests with unique IDs", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 60_000)

      # 100 concurrent requests with unique IDs
      request_count = 100

      # Use Task.async_stream for better resource management
      results =
        1..request_count
        |> Task.async_stream(
          fn i ->
            unique_id = "req-#{i}-#{System.unique_integer([:positive])}"
            result = Lather.DynamicClient.call(client, "GenerateId", %{"input_id" => unique_id})
            {unique_id, result}
          end,
          max_concurrency: 100,
          timeout: 60_000
        )
        |> Enum.to_list()

      # Extract results from Task.async_stream format
      unwrapped_results =
        Enum.map(results, fn
          {:ok, {unique_id, result}} -> {unique_id, result}
          {:exit, reason} -> {:error, reason}
        end)

      # Verify all requests succeeded
      successful =
        Enum.filter(unwrapped_results, fn
          {_id, {:ok, _}} -> true
          _ -> false
        end)

      assert length(successful) == request_count,
             "Only #{length(successful)} of #{request_count} requests succeeded"

      # Verify response isolation - each response contains the correct ID
      for {original_id, {:ok, response}} <- successful do
        assert response["output_id"] == original_id,
               "ID mismatch: sent '#{original_id}', got '#{response["output_id"]}'"
      end
    end

    test "handles mixed high-volume requests across operations", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 60_000)

      # 75 total requests across different operations
      echo_requests = Enum.map(1..25, fn i -> {:echo, "msg-#{i}"} end)
      add_requests = Enum.map(1..25, fn i -> {:add, i, i * 2} end)
      multiply_requests = Enum.map(1..25, fn i -> {:multiply, i, 3} end)

      all_requests = echo_requests ++ add_requests ++ multiply_requests

      results =
        all_requests
        |> Task.async_stream(
          fn
            {:echo, msg} ->
              result = Lather.DynamicClient.call(client, "Echo", %{"message" => msg})
              {:echo, msg, result}

            {:add, a, b} ->
              result = Lather.DynamicClient.call(client, "Add", %{"a" => a, "b" => b})
              {:add, a, b, result}

            {:multiply, a, b} ->
              result = Lather.DynamicClient.call(client, "Multiply", %{"a" => a, "b" => b})
              {:multiply, a, b, result}
          end,
          max_concurrency: 75,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      # Verify results
      echo_results = Enum.filter(results, fn r -> elem(r, 0) == :echo end)
      add_results = Enum.filter(results, fn r -> elem(r, 0) == :add end)
      multiply_results = Enum.filter(results, fn r -> elem(r, 0) == :multiply end)

      # Verify Echo responses
      for {:echo, msg, result} <- echo_results do
        assert {:ok, response} = result
        assert response["echo"] == msg
      end

      # Verify Add responses
      for {:add, a, b, result} <- add_results do
        assert {:ok, response} = result
        assert parse_result(response["result"]) == (a + b) * 1.0
      end

      # Verify Multiply responses
      for {:multiply, a, b, result} <- multiply_results do
        assert {:ok, response} = result
        assert parse_result(response["result"]) == (a * b) * 1.0
      end
    end
  end

  describe "response isolation and data integrity" do
    setup :start_server

    test "each request receives its own unique response", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 10_000)

      # Create requests with clearly unique identifiers
      unique_ids =
        1..20
        |> Enum.map(fn i ->
          "isolation-test-#{i}-#{System.unique_integer([:positive])}-#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"
        end)

      tasks =
        unique_ids
        |> Enum.map(fn id ->
          Task.async(fn ->
            result = Lather.DynamicClient.call(client, "GenerateId", %{"input_id" => id})
            {id, result}
          end)
        end)

      results = Task.await_many(tasks, 20_000)

      # Verify each response contains exactly the ID that was sent
      received_ids =
        results
        |> Enum.map(fn {original_id, result} ->
          assert {:ok, response} = result
          response_id = response["output_id"]

          assert response_id == original_id,
                 "Data leakage detected: sent '#{original_id}', received '#{response_id}'"

          response_id
        end)

      # Verify all IDs are unique (no duplicate responses)
      assert length(Enum.uniq(received_ids)) == length(received_ids),
             "Duplicate responses detected - possible data leakage"
    end

    test "no data leakage between concurrent requests with similar content", %{
      base_url: base_url
    } do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 10_000)

      # Create similar-looking requests that could be confused
      similar_requests = [
        {"similar-A", 1, 2},
        {"similar-B", 1, 2},
        {"similar-A", 3, 4},
        {"similar-B", 3, 4},
        {"similar-A", 1, 2},
        {"similar-B", 1, 2}
      ]

      tasks =
        similar_requests
        |> Enum.with_index()
        |> Enum.map(fn {{prefix, a, b}, idx} ->
          unique_id = "#{prefix}-#{idx}-#{a}-#{b}"

          Task.async(fn ->
            # Make concurrent Echo calls with the unique ID
            result = Lather.DynamicClient.call(client, "Echo", %{"message" => unique_id})
            {unique_id, result}
          end)
        end)

      results = Task.await_many(tasks, 15_000)

      for {sent_id, result} <- results do
        assert {:ok, response} = result
        received = response["echo"]

        assert received == sent_id,
               "Data leakage: sent '#{sent_id}', received '#{received}'"
      end
    end
  end

  describe "concurrent requests with slow operations" do
    setup :start_server

    test "slow operations don't block fast operations", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 15_000)

      # Start a slow operation first
      slow_task =
        Task.async(fn ->
          start_time = System.monotonic_time(:millisecond)

          result =
            Lather.DynamicClient.call(client, "SlowOperation", %{
              "request_id" => "slow-request",
              "delay_ms" => 500
            })

          end_time = System.monotonic_time(:millisecond)
          {:slow, result, end_time - start_time}
        end)

      # Give the slow operation a head start
      Process.sleep(50)

      # Start multiple fast operations
      fast_tasks =
        1..5
        |> Enum.map(fn i ->
          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)
            result = Lather.DynamicClient.call(client, "Echo", %{"message" => "fast-#{i}"})
            end_time = System.monotonic_time(:millisecond)
            {:fast, i, result, end_time - start_time}
          end)
        end)

      # Await all tasks
      [slow_result | fast_results] = Task.await_many([slow_task | fast_tasks], 20_000)

      # Verify slow operation completed
      {:slow, result, slow_duration} = slow_result
      assert {:ok, response} = result
      assert response["response_id"] == "slow-request"
      assert slow_duration >= 500, "Slow operation completed too quickly"

      # Verify fast operations completed successfully
      for {:fast, i, result, _duration} <- fast_results do
        assert {:ok, response} = result
        assert response["echo"] == "fast-#{i}"
      end
    end

    test "multiple slow operations complete independently", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 15_000)

      # Create multiple slow operations with different delays
      delays = [100, 200, 150, 250, 180]

      tasks =
        delays
        |> Enum.with_index()
        |> Enum.map(fn {delay, idx} ->
          request_id = "slow-#{idx}-delay-#{delay}"

          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)

            result =
              Lather.DynamicClient.call(client, "SlowOperation", %{
                "request_id" => request_id,
                "delay_ms" => delay
              })

            end_time = System.monotonic_time(:millisecond)
            {request_id, delay, result, end_time - start_time}
          end)
        end)

      results = Task.await_many(tasks, 20_000)

      # Verify each operation completed and returned the correct ID
      for {expected_id, _delay, result, _duration} <- results do
        assert {:ok, response} = result
        assert response["response_id"] == expected_id
        assert response["completed"] == true or response["completed"] == "true"
      end
    end
  end

  describe "server stability under concurrent load" do
    setup :start_server

    test "server remains responsive after burst of requests", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 30_000)

      # Send initial burst of requests
      burst_results =
        1..30
        |> Task.async_stream(
          fn i ->
            Lather.DynamicClient.call(client, "Echo", %{"message" => "burst-#{i}"})
          end,
          max_concurrency: 30,
          timeout: 30_000
        )
        |> Enum.to_list()

      # Verify burst completed
      successful_burst =
        Enum.count(burst_results, fn
          {:ok, {:ok, _}} -> true
          _ -> false
        end)

      assert successful_burst == 30, "Only #{successful_burst}/30 burst requests succeeded"

      # Wait a moment
      Process.sleep(100)

      # Verify server is still responsive with a simple request
      assert {:ok, response} =
               Lather.DynamicClient.call(client, "Echo", %{"message" => "post-burst-test"})

      assert response["echo"] == "post-burst-test"
    end

    test "server handles repeated concurrent request cycles", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 30_000)

      # Run multiple cycles of concurrent requests
      cycle_results =
        for cycle <- 1..5 do
          results =
            1..10
            |> Task.async_stream(
              fn i ->
                Lather.DynamicClient.call(client, "Add", %{"a" => cycle, "b" => i})
              end,
              max_concurrency: 10,
              timeout: 15_000
            )
            |> Enum.to_list()

          # Brief pause between cycles
          Process.sleep(50)

          {cycle, results}
        end

      # Verify all cycles completed successfully
      for {cycle, results} <- cycle_results do
        successful =
          Enum.count(results, fn
            {:ok, {:ok, _}} -> true
            _ -> false
          end)

        assert successful == 10, "Cycle #{cycle}: Only #{successful}/10 requests succeeded"
      end
    end

    test "no errors with varying concurrent loads", %{base_url: base_url} do
      {:ok, client} = Lather.DynamicClient.new("#{base_url}/soap?wsdl", timeout: 60_000)

      # Test with varying concurrency levels
      concurrency_levels = [5, 10, 20, 10, 5]

      all_successful =
        concurrency_levels
        |> Enum.with_index()
        |> Enum.all?(fn {level, idx} ->
          results =
            1..level
            |> Task.async_stream(
              fn i ->
                Lather.DynamicClient.call(client, "Echo", %{"message" => "load-test-#{idx}-#{i}"})
              end,
              max_concurrency: level,
              timeout: 30_000
            )
            |> Enum.to_list()

          successful =
            Enum.count(results, fn
              {:ok, {:ok, _}} -> true
              _ -> false
            end)

          successful == level
        end)

      assert all_successful, "Server failed to handle varying concurrent loads"
    end
  end

  # Helper to start the test server
  defp start_server(_context) do
    # Start the Lather application (for Finch)
    {:ok, _} = Application.ensure_all_started(:lather)

    # Start the server on a random available port
    port = Enum.random(10000..60000)

    {:ok, server_pid} =
      Bandit.start_link(plug: ConcurrentTestRouter, port: port, scheme: :http)

    on_exit(fn ->
      # Cleanup server
      try do
        GenServer.stop(server_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    # Wait for server to be ready
    Process.sleep(100)

    {:ok, port: port, base_url: "http://localhost:#{port}"}
  end

  # Helper to parse numeric results
  defp parse_result(value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> num
      :error -> value
    end
  end

  defp parse_result(value) when is_number(value), do: value * 1.0
  defp parse_result(value), do: value
end
