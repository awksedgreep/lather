# Transport Limitations and Alternatives

## HTTP/2

Lather's HTTP transport is Finch (HTTP/1.1). Options if HTTP/2 is
required:

1. Put an HTTP/2 gateway (nginx, Envoy, Cloudflare) in front of the
   Lather client; the gateway downgrades to HTTP/1.1 toward Lather.
2. Front-end services accept HTTP/2 and proxy to Lather's Bandit
   server, which is HTTP/1.1.

## WebSockets

SOAP-over-WebSockets is not implemented. To push messages over
WebSockets:

- Use WS-Eventing (`enable_eventing: true`) for pub/sub within HTTP,
  or
- Bridge a Phoenix Channel / websocket layer to `Lather.Eventing`
  subscriptions, translating events to SOAP calls on delivery.

## GraphQL

`Lather.GraphQL` exposes SOAP operations as GraphQL-style fields:

```elixir
{:ok, schema} = Lather.GraphQL.schema(service_module)
{:ok, result} = Lather.GraphQL.execute(schema, %{query: "EchoA(message: \"hi\")"})
```

This is a convenience bridge, not a full GraphQL server; use Phoenix
or Absinthe for real GraphQL endpoints backed by SOAP services.
