# Architecture Decision Records

## ADR-001: Single-pass fast XML parser as an opt-in fast path

- **Status**: Accepted
- **Context**: SweetXml-based parsing dominated SOAP response time in
  benchmarks (roughly 3x slower than a direct scanner for flat SOAP
  envelopes).
- **Decision**: `Lather.Xml.FastParser` scans the envelope bytes in a
  single pass and returns nested maps. It is used only when
  `Application.put_env(:lather, :fast_xml_parse, true)`; the full
  SweetXml parser remains the default for exotic XML.
- **Consequences**: ~2-3x faster parse for common responses; attribute
  handling and entity decoding are intentionally minimal, so services
  with complex XML stay on the full parser.

## ADR-002: Finch connection pools per endpoint

- **Status**: Accepted
- **Context**: Repeated calls to the same endpoint re-established TCP
  connections, adding latency and churn.
- **Decision**: `Lather.Http.Transport.warm_connection/2` creates a
  named Finch pool per endpoint; calls accept `pool_name:`.
- **Consequences**: Better throughput and explicit control; pool
  lifecycle must be managed by the caller (`close_connection/2`).

## ADR-003: Plugin hooks around DynamicClient calls

- **Status**: Accepted
- **Context**: Users needed a way to add headers, transform responses,
  or log errors without subclassing clients.
- **Decision**: `Lather.Plugin` behaviour with `before_request/2`,
  `after_response/2`, and `on_error/2`, applied in order around
  `DynamicClient.call/4`.
- **Consequences**: Custom behavior is declarative and composable; the
  hook contract returns the result unchanged unless transformed.

## ADR-004: Streaming via chunked SOAP envelopes

- **Status**: Accepted
- **Context**: gRPC-style streaming had no SOAP equivalent.
- **Decision**: Handlers return `{:stream, items}`; the server emits one
  chunked SOAP envelope per item and `DynamicClient.stream_operation/4`
  exposes a lazy stream.
- **Consequences**: Large result sets are delivered incrementally with
  bounded memory, at the cost of each chunk being a full envelope.
