# Docker and Kubernetes Deployment

## Docker

```bash
docker build -t lather-soap-service .
docker run -p 4000:4000 lather-soap-service
```

Replace `MyService` in the `CMD` with your service module, or bake your
service code into the image under `lib/`.

Best practices:

- Set `MIX_ENV=prod` and compile before running.
- Pin the base image (`elixir:1.20-alpine`) for reproducible builds.
- Keep secrets out of the image; pass them via environment variables or
  mounted config files (`config_file:`).
- Health check the `?health` endpoint.

## Docker Compose with gateway

`docker-compose.yml` runs the service behind an nginx gateway
(`nginx.conf`). The gateway handles TLS, rate limiting, and HTTP/2
termination; Lather speaks HTTP/1.1.

## Kubernetes

`k8s/deployment.yaml` provides:

- 3 replicas with rolling updates (`maxUnavailable: 0`)
- readiness/liveness probes against `GET /soap?health`
- CPU/memory requests and limits
- a ClusterIP service

For Istio/service-mesh setups, annotate the pod with the mesh sidecar
and let the mesh handle mTLS; WS-Discovery (`GET /soap?discovery`)
lets clients adapt to pod churn automatically.
