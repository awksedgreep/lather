# Monitoring Dashboard Templates

Lather emits telemetry events and exposes `?metrics` JSON; use these
templates to pipe them into your stack.

## Metrics endpoint

```bash
curl 'http://localhost:4000/soap?metrics'
```

Returns requests, errors, average duration, and uptime — enough for a
simple Grafana "text panel" or Prometheus scraping via an exporter.

## Telemetry event names

```elixir
:telemetry.attach_many("lather-ops", [
  [:lather, :soap, :request, :start],
  [:lather, :soap, :request, :stop],
  [:lather, :soap, :error]
], fn event, metadata, value, config ->
  # forward to StatsD, Prometheus counters, etc.
end, %{})
```

## Grafana dashboard skeleton

```json
{
  "dashboard": {
    "title": "Lather SOAP Service",
    "panels": [
      {"title": "Requests/min", "type": "timeseries", "query": "lather_requests_total"},
      {"title": "Error rate", "type": "timeseries", "query": "lather_errors_total"},
      {"title": "Avg duration", "type": "singlestat", "query": "lather_avg_duration_ms"}
    ]
  }
}
```

## Phoenix LiveView dashboard

```elixir
defmodule SoapDashboardLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket), do: LiveView.schedule_tick(socket, 5000)
    {:ok, socket}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :metrics, fetch_metrics())}
  end
end
```

`fetch_metrics/0` can call `Lather.Tracing.Collector` or the `?metrics`
endpoint.
