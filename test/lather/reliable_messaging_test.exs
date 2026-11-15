defmodule Lather.ReliableMessagingTest do
  use ExUnit.Case, async: true

  alias Lather.ReliableMessaging

  test "headers include WS-RM entries" do
    headers = ReliableMessaging.headers("msg-1", 2, 10)
    [header] = headers

    assert header["wsrm:MessageID"] == "msg-1"
    assert header["wsrm:Sequence"] == 2
    assert header["wsrm:Expires"]
    assert header["@xmlns:wsrm"]
  end

  test "deliver retries transport errors" do
    counter = :counters.new(1, [])

    fun = fn ->
      n = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)

      if n < 2 do
        {:error, {:transport_error, :timeout}}
      else
        {:ok, "delivered"}
      end
    end

    assert ReliableMessaging.deliver(fun, 3, 1) == {:ok, "delivered"}
  end

  test "deliver gives up after retries" do
    fun = fn -> {:error, {:transport_error, :unreachable}} end

    assert match?({:error, {:transport_error, _}}, ReliableMessaging.deliver(fun, 2, 1))
  end

  test "non-transport errors are not retried" do
    assert ReliableMessaging.deliver(fn -> {:error, :bad_input} end, 3, 1) == {:error, :bad_input}
  end

  test "retries are recorded in client metrics" do
    metrics = Lather.Http.Metrics.new()
    counter = :counters.new(1, [])

    fun = fn ->
      n = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)

      if n < 2 do
        {:error, {:transport_error, :timeout}}
      else
        {:ok, "delivered"}
      end
    end

    assert ReliableMessaging.deliver(fun, 3, 1, metrics) == {:ok, "delivered"}

    snapshot = Lather.Http.Metrics.snapshot(metrics)
    assert snapshot.retries == 2
  end

  test "transient Receiver faults are retried" do
    counter = :counters.new(1, [])

    fun = fn ->
      :counters.add(counter, 1, 1)
      n = :counters.get(counter, 1)

      if n < 3 do
        {:error, {:soap_fault, %{fault_code: "soap:Receiver", fault_string: "TemporaryFailure"}}}
      else
        {:ok, "delivered"}
      end
    end

    assert ReliableMessaging.deliver(fun, 3, 1) == {:ok, "delivered"}
  end

  test "client faults are not retried" do
    fault = %{fault_code: "soap:Client", fault_string: "BadRequest"}

    assert ReliableMessaging.deliver(fn -> {:error, {:soap_fault, fault}} end, 2, 1) ==
             {:error, {:soap_fault, fault}}
  end
end
