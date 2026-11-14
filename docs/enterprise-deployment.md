# Enterprise Deployment Guide

## Multi-tenant services

A single EnhancedPlug can host multiple tenant services:

```elixir
plug = {Lather.Server.EnhancedPlug, [
  service: BillingService,
  tenants: %{
    "acme" => BillingServiceAcme,
    "globex" => BillingServiceGlobex
  }
}]
```

Requests select the tenant with `?tenant=acme`; the default tenant is
`config.service`. Each tenant gets its own WSDL, docs, and metrics.

## Behind a gateway or load balancer

- Put nginx/Envoy in front for TLS termination, HTTP/2, rate limiting,
  and DDoS protection.
- Point the gateway at the Bandit listener; use sticky sessions only if
  WS-Eventing subscriptions must stay on one node.
- For service meshes (Istio, Consul), register the service via
  WS-Discovery: clients can probe `GET /soap?discovery` to find
  endpoints dynamically.

## Kubernetes

See `k8s/deployment.yaml` for a reference deployment with health checks
against `?health` and rolling updates. Scale horizontally per service;
enable `persist_store` only if history must be shared, otherwise keep
history per pod.

## Docker

```bash
docker build -t lather-service .
docker run -p 4000:4000 lather-service
```

`docker-compose.yml` wires a service alongside an nginx gateway.

## Observability in production

- `?dashboard` — live status page
- `?docs` — browsable operation docs
- `?history` — request/response history when `persist_store` is set
- Telemetry events (`[:lather, :soap, :request, ...]`) plug into
  `Lather.Tracing.Collector` or any OpenTelemetry-compatible pipeline.

## Fault injection in production-like environments

```elixir
{Lather.Server.EnhancedPlug, [service: MyService, fault_injection_rate: 0.05]}
```

Injects transient SOAP faults (code `TemporaryFailure`) to test client
retry logic. Pair with `reliable: true` on clients to verify recovery.
