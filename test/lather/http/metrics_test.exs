defmodule Lather.Http.MetricsTest do
  use ExUnit.Case, async: true

  alias Lather.Http.Metrics

  test "records requests, errors, and status codes" do
    metrics = Metrics.new()

    Metrics.record(metrics, 200, 1000)
    Metrics.record(metrics, 200, 3000)
    Metrics.record(metrics, 500, 2000)
    Metrics.record(metrics, 0, 5000)

    snapshot = Metrics.snapshot(metrics)

    assert snapshot.requests == 4
    assert snapshot.errors == 2
    assert snapshot.total_duration_us == 11_000
    assert snapshot.average_duration_ms == 2.75

    counts = Map.new(snapshot.status_counts)
    assert counts[200] == 2
    assert counts[500] == 1
    assert counts[0] == 1
  end

  test "tracks per-operation request counts" do
    metrics = Metrics.new()

    Metrics.record(metrics, 200, 1000, "Echo")
    Metrics.record(metrics, 200, 1000, "Echo")
    Metrics.record(metrics, 404, 1000, "Missing")
    Metrics.record(metrics, 200, 1000, nil)

    counts = Map.new(Metrics.snapshot(metrics).operation_counts)
    assert counts["Echo"] == 2
    assert counts["Missing"] == 1
    assert map_size(counts) == 2
  end

  test "a fresh handle snapshots as empty" do
    snapshot = Metrics.snapshot(Metrics.new())

    assert snapshot.requests == 0
    assert snapshot.errors == 0
    assert snapshot.retries == 0
    assert snapshot.average_duration_ms == 0.0
    assert snapshot.status_counts == []
    assert snapshot.operation_counts == []
  end

  test "record_retry increments the retry counter" do
    metrics = Metrics.new()
    Metrics.record_retry(metrics)
    Metrics.record_retry(metrics)

    assert Metrics.snapshot(metrics).retries == 2
  end
end
