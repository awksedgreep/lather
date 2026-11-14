# Performance Tuning Guide

## Enable the fast XML parser

```elixir
Application.put_env(:lather, :fast_xml_parse, true)
```

`Lather.Xml.Parser.parse/1` routes flat SOAP envelopes through
`Lather.Xml.FastParser`, a single-pass byte scanner. Benchmarks in
`test/lather/xml/fast_parser_test.exs` show ~2-3x faster parsing than
the SweetXml path.

## Warm connection pools

```elixir
Lather.Http.Transport.warm_connection("https://api.example.com/soap",
  [pool_size: 50, pool_timeout: 5_000])

Lather.DynamicClient.call(client, "GetUser", %{"id" => 1},
  pool_name: :api_pool)
```

Warm pools avoid per-call TCP setup. Inspect them with
`Transport.pool_status/2`.

## Bound response sizes

```elixir
Transport.post(url, envelope, max_response_bytes: 2_000_000)
```

Responses larger than the limit are streamed and aborted early rather
than buffered in memory.

## Use prefetching for related operations

```elixir
{:ok, cache} = Lather.Prefetch.start_link(name: :cache, ttl: 30)

Lather.DynamicClient.call(client, "GetUser", %{"id" => 1},
  prefetch: [{"GetOrders", %{"userId" => 1}}, {"GetProfile", %{"userId" => 1}}],
  prefetch_pool: cache)
```

Related calls are fetched asynchronously after the first response and
served from cache on subsequent calls.

## Measure with the built-in load test

```elixir
stats = Lather.LoadTest.run(client, "Ping", %{}, iterations: 200, concurrency: 10)
```

Check the service's `?metrics` endpoint for server-side request counts,
error counts, and average durations.

## HTTP/2 note

Lather's transport is Finch, which speaks HTTP/1.1. For services that
require HTTP/2, place an HTTP/2 gateway (nginx, Envoy) in front of the
Lather client or service.
