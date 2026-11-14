# Troubleshooting Cookbook

## "Operation not found" but the operation exists

Unknown-operation faults now include a suggestion, e.g.
`Operation 'EchoAa' not found. Did you mean 'EchoA'?`. Operation lookup
is case-insensitive; check the `?docs` page for canonical names.

## 405 Method not allowed

The endpoint matched a GET-only route (`?wsdl`, `?policy`, `?docs`,
`?metrics`, `?dashboard`, `?history`). Make sure SOAP calls are POSTs
with a SOAP envelope. If the client's endpoint URL still contains
`?wsdl`, pass a plain endpoint or `endpoint_override:` to
`DynamicClient.new/2`.

## Client keeps hitting the wrong tenant

`?tenant=` is honored for both WSDL and SOAP POST requests. If you
derive the endpoint from a WSDL URL that carries a `tenant` query
param, the param is preserved; otherwise the default tenant (
`config.service`) is used.

## Slow responses

1. Enable `Application.put_env(:lather, :fast_xml_parse, true)`.
2. Warm a pool with `Transport.warm_connection/2` and pass
   `pool_name:`.
3. Check `?metrics` for server-side averages and error counts.

## Memory growth on large payloads

- Stream results with `{:stream, items}` handlers and
  `DynamicClient.stream_operation/4`.
- Reuse MTOM attachments with `mtom_cache:` instead of re-encoding
  base64 blobs per call.

## Transient network faults

Enable `reliable: true` (with optional `retries:`) so transport errors
are retried with backoff, and inspect `Lather.ReliableMessaging`
headers in the outgoing envelope.

## Debugging locally

Start the server with `debug: true` to log every parsed request, and
`trace: true` on a client with `trace_collector:` to capture span
timings.
