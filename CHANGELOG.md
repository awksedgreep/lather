# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.1] - 2026-11-14

### Fixed
- Audit logging no longer reads and rewrites the whole log on every
  request; entries are appended with `File.write/3` in `:append` mode,
  so concurrent requests can no longer overwrite each other's entries.
- `Lather.Wsdl.Analyzer` honors the per-operation `style="rpc"` attribute
  instead of always reporting the binding-level default.
- `Lather.DynamicClient` keeps non-`wsdl` query parameters (e.g.
  `?tenant=acme`) when deriving the service endpoint from a WSDL URL, so
  multi-tenant clients no longer fall back to the default tenant.
- `Lather.ReliableMessaging.deliver/3` retries transient `Receiver` SOAP
  faults (e.g. `TemporaryFailure`) rather than only transport errors,
  making fault injection and transient service failures recoverable.

### Added
- `Lather.Http.Pool` is now used by `Lather.Http.Transport.warm_connection/2`
  to build and validate per-endpoint pool configuration.
- Property/fuzz tests for WS-Security signatures, JWT claims, MTOM
  threshold selection, attachment validation, and WS-Policy round-trips;
  RPC, nested-type/multi-port, and SOAP 1.2 WSDL fixtures; and a
  `scripts/coverage_gate.sh` (80% floor) in the quality CI workflow.

## [1.3.0] - 2026-11-14

### Added
- Multi-tenant services: `tenants: %{"name" => ServiceModule}` on the
  enhanced plug; `?tenant=name` selects the service for WSDL and SOAP
  requests.
- Fault injection for chaos testing: `fault_injection_rate:` on the
  enhanced plug emits transient SOAP faults (`TemporaryFailure`) so
  clients with `reliable: true` can be tested for retry/recovery.
  `Lather.ReliableMessaging.deliver/3` now also retries transient
  `Receiver` SOAP faults, not just transport errors.
- `debug: true` on the enhanced plug logs every parsed request for
  development-mode troubleshooting.
- Unknown-operation faults now suggest the closest operation name
  ("Did you mean 'EchoA'?") via a Levenshtein match.
- WS-I Basic Profile structural validation via
  `Lather.Soap.Profile.validate/1` (single envelope/body, namespace,
  header-before-body ordering, valid mustUnderstand values).
- `Lather.Wsdl.Schema` generates XSD schemas from service modules and
  validates operation parameters client-side.
- `Lather.I18n` translations (en/es/de) for the built-in dashboard,
  docs, and history pages (`?lang=es|de`).
- Accessibility improvements to built-in web pages: `lang` attributes,
  viewport meta, skip links, focus outlines, `prefers-contrast` support,
  responsive layouts.
- `Lather.DynamicClient` now preserves non-`wsdl` query parameters
  (e.g. `tenant`) when deriving the service endpoint from a WSDL URL.
- `Lather.Http.BasicClient`, a dependency-free `:gen_tcp` HTTP/1.1
  transport selectable with `client: :basic` (or globally via
  `Application.put_env(:lather, :http_client, :basic)`), as an
  alternative to Finch.
- Deployment and guide docs: `docs/adr/`, `docs/enterprise-deployment.md`,
  `docs/security-best-practices.md`, `docs/troubleshooting-cookbook.md`,
  `docs/performance-tuning.md`, `docs/migration-guide.md`,
  `docs/plugin-development.md`, `docs/editor-integration.md`,
  `docs/http2-websocket.md`, `docs/ecto-phoenix.md`,
  `docs/compatibility.md`, `docs/monitoring-templates.md`,
  `docs/examples.md`, `docs/docker-kubernetes.md`.
- `Dockerfile`, `docker-compose.yml`, `nginx.conf`, and
  `k8s/deployment.yaml` for containerized deployment.
- Property/fuzz tests for WS-Security signatures, JWT claims, MTOM
  threshold selection, attachment validation, and WS-Policy
  build/parse/validate round-trips (`test/property/property_hardening_test.exs`).
- Real-world WSDL fixtures for RPC style, nested/array complex types with
  faults and multiple ports, and SOAP 1.2 bindings
  (`test/fixtures/`), covered by `test/integration/real_world_compatibility_test.exs`.
- `scripts/coverage_gate.sh` fails CI when total coverage drops below 80%
  (`COVERAGE_MIN` to override).

### Changed
- `Lather.Http.Pool` is now used by `Lather.Http.Transport.warm_connection/2`
  to build and validate per-endpoint pool configuration.
- `Lather.Wsdl.Analyzer` honors the per-operation `style="rpc"` attribute
  instead of always reporting the binding-level default.

### Fixed
- `Lather.DynamicClient` endpoint derivation keeps `?tenant=` and other
  non-`wsdl` query parameters when the endpoint is derived from a WSDL URL.

## [1.2.2] - 2026-10-23

### Added
- `Lather.Server.OpenAPIGenerator` generates OpenAPI 3.1 specifications from
  SOAP service definitions; the enhanced plug serves them at
  `GET /service?openapi` and `GET /service/openapi.json`. Interop with the
  `infusion` package is covered by a test that loads the live spec, generates
  an SDK from it, and exercises the generated client against a running server.
- Swagger UI explorer served by the enhanced plug at `GET /service?swagger`
  and `GET /service/swagger`; it can be disabled with `:enable_swagger: false`.
- `mix lather.openapi` task generating an OpenAPI 3.1 spec from a service
  module (`--service`) or a WSDL file/URL (`--wsdl`).
- `Lather.Client.Generator` and the `mix lather.client` task generate named,
  documented Elixir client functions (and structs) from a service's WSDL.
- `mix lather.analyze` task summarizing a WSDL (operations, endpoints, types,
  bindings) with an optional `--json` output.
- Services can declare `@api_version`, surfaced in the OpenAPI spec's
  `info.version`, a WSDL `<documentation>` element, and the service overview
  page.
- `Lather.Server.Router` provides a `soap_route "/path", MyService` macro for
  `Plug.Router`/Phoenix routers that mounts a service's full endpoint set
  (SOAP, WSDL, OpenAPI, Swagger UI, forms) at the given path.
- WSDL responses are cached (`WSDLGenerator.cached_generate/3` and
  `EnhancedWSDLGenerator.cached_generate/3`) with a 300-second TTL, used
  automatically by the enhanced plug's `?wsdl` endpoints.
- Opt-in operation result caching: `Lather.Server.EnhancedPlug` accepts
  `:cache_results` and `:cache_ttl` options, caching successful operation
  results per service, operation, and parameters (`Lather.Server.ResultCache`).
- Health check endpoint at `GET /service?health` (also `/service/health`)
  returning JSON status, service name, version, operation count, and uptime.
- `Lather.Mtom.Builder.build_message/3` automatically chooses between MTOM
  multipart messages and plain inline (base64) SOAP based on attachment size;
  the threshold is configurable per call (`:mtom_threshold`) or via
  `:lather, :mtom_threshold` application config.
- MTOM attachments can be gzip-compressed with the `compress: true` option
  (`{:attachment, data, type, [compress: true]}`); parts carry a
  `Content-Encoding: gzip` header and are transparently gunzipped when
  parsed. `Attachment.decompress/1` is also available.
- `mix lather.call` task for quick request/response debugging against any
  SOAP service: `--list` operations, `--operation`/`--param`/`--json` to
  invoke, with `--soap-version`, `--endpoint`, `--timeout`, `--raw`, and
  `--auth`/`--ws-auth` support.
- Every `Lather.Server.EnhancedPlug` request emits a `[:lather, :server,
  :request]` telemetry span (`:start`/`:stop`) with duration, status,
  service, method, and path metadata.
- Transparent gzip support in the enhanced plug: `Content-Encoding: gzip`
  request bodies are decompressed, and responses are gzipped when the
  client's `Accept-Encoding` includes gzip and the body exceeds 1 KB.
- Optional audit logging via the `:audit_log` option on
  `Lather.Server.EnhancedPlug.init/1`, writing one JSON line per request
  (timestamp, service, method, path, status).
- `Lather.TestClient` for exercising a service in tests without a live
  server: `call_json/3`, `call_soap/4` (SOAP 1.1/1.2), `wsdl/2`,
  `openapi/1`, `health/1`, plus `status/1`, `body/1`, and `json_body/1`
  response helpers.
- `mustUnderstand` header enforcement in the enhanced plug: with
  `understood_headers: [...]` configured, headers marked
  `mustUnderstand="1|true"` whose name or namespace is not understood
  produce a `NotUnderstood` SOAP fault.
- Service usage analytics: `Lather.Server.Metrics` and a `GET /service?metrics`
  endpoint (enabled with `enable_metrics: true`) reporting request/error
  counts, average response time, status-code counts, and uptime.
- WS-Security XML digital signatures via `Lather.Auth.Signature`: clients
  using `authentication: {:signature, key}` attach a `wsse:Security` header
  containing an HMAC-SHA256 digest and signature over the canonicalized
  operation and parameters; servers configured with `verify_signature: key`
  reject missing or invalid signatures with a `Client` SOAP fault.
- `Lather.Auth.OAuth` implements the OAuth 2.0 client credentials and
  refresh-token grants (`client_credentials_token/4`, `refresh_token/4`,
  `bearer_headers/1`, `client_with_token/5`) for token-based SOAP clients.
- `Lather.Auth.JWT` signs and verifies HS256 JWTs (no external deps) and
  carries them in WS-Security SOAP headers: clients use
  `authentication: {:jwt, secret}` or `{:jwt, secret, claims}`; servers verify
  every request with the `:jwt_secret` option.
- `Lather.Auth.APIKey` adds API-key authentication: servers accept an
  `:api_keys` list or key/metadata map and reject requests missing a valid
  `X-API-Key` header with a 401; clients send it via
  `authentication: {:api_key, key}`.
- SOAP 1.2 role-based header processing: the enhanced plug accepts a
  `:soap_roles` list, and `mustUnderstand` headers whose `role` (or SOAP 1.1
  `actor`) attribute is not in the list produce a `NotUnderstood` fault.
  The default power role is always accepted.
- `Lather.Auth.SAML` builds, signs (HMAC-SHA256), and verifies SAML 2.0
  assertions carried in WS-Security SOAP headers: clients use
  `authentication: {:saml, secret}` (or `{:saml, secret, subject, opts}`);
  servers verify every request with the `:saml_secret` option.
- MTOM large-attachment streaming: `Lather.Mtom.Builder.build_message_chunks/3`
  builds multipart messages as lazy chunk streams (attachment sources can be
  binaries, `{:file, path}` tuples read in `:chunk_size` blocks, or any
  enumerable), `Lather.Http.Transport.post_stream/4` posts them with chunked
  request bodies, and `Lather.Mtom.StreamUploader.upload/4` combines both so
  multi-megabyte attachments never fully load into memory.
- Multi-factor authentication: the enhanced plug's `require_auth: [...]`
  option (`:api_key`, `:jwt`, `:basic`, `:bearer`) enforces that every listed
  authentication factor is present on SOAP and JSON requests.
-   `Lather.Auth.XMLEncryption` implements WS-Security-style XML Encryption:
  clients send operation bodies as AES-256-CBC-encrypted `xenc:EncryptedData`
  payloads via `encryption: {:aes256, key}`, and servers configured with
  `:encryption_key` decrypt them transparently (with HMAC integrity checks);
  plaintext requests still work.
- `Lather.Auth.TokenManager` is a GenServer that issues HS256 JWT access
  tokens with `exp`/`jti` claims, validates them, rotates them via a
  `refresh/2` call (with an optional expiry grace window) while revoking the
  previous token, and maintains a revocation blacklist.
- `Lather.Server.ServiceSupervisor` supervises a service as a GenServer:
  it calls operations in-process (`call/3`), starts/stops an HTTP server on
  demand (`start_http_server/2`, `stop_http_server/1`), and reports request,
  error, and uptime stats (`stats/1`).
- Async and streaming client calls: `Lather.DynamicClient.call_async/4`
  (returns an awaitable `Task`), `call_many/3` (concurrent invocations with
  `:concurrency`/`:timeout` options, results in invocation order), and
  `call_stream/3` (lazy stream of results for batch processing).
- `Lather.Auth.Policy` validates a service's configuration against a
  declarative security policy (`require_auth`, `min_factors`,
  `max_body_size`, `require_encryption`); `EnhancedPlug` accepts a
  `:security_policy` option and raises `ArgumentError` at startup when the
  configuration violates the policy.
- WS-Trust: `Lather.Auth.WSTrust` issues HMAC-signed issuer tokens
  (`issue_token/3`, `validate_token/2`), fetches tokens from issuer
  endpoints (`request_token/4`), and carries them in WS-Security headers.
  Clients use `authentication: {:wstrust, secret[, subject]}` or
  `{:wstrust_token, token}`; servers verify with `:wstrust_secret`.
- Certificate-based authentication: `Lather.Auth.Certificate` parses X.509
  PEM certificates with Erlang's `:public_key` and verifies common name,
  validity window, and SHA-256 fingerprint. Clients send
  `authentication: {:certificate, pem}` (base64-encoded in an
  `X-Client-Certificate` header); servers enforce a `:client_certificates`
  allowlist.
- Connection pooling and warmup: `Lather.Http.Transport.warm_connection/2`
  starts a dedicated, sized Finch pool for an endpoint (surfaced as
  `DynamicClient.warm_pool/2` and `with_pool/2`), plus a new
  `Transport.get/2` and a `:pool_name` transport option.
- XML parsing performance: `Lather.Xml.FastParser` is a single-pass binary
  scanner for flat SOAP-shaped documents, roughly 2-3x faster than the
  SweetXml path; `Lather.Xml.Parser.parse/1` uses it when
  `:fast_xml_parse` is set in application config.
- Memory usage: `Transport.post/3` accepts `max_response_bytes`,
  streaming the response with `Finch.stream_while/4` and aborting early
  (with a `:response_too_large` transport error) instead of buffering
  oversized payloads.
- Predictive prefetching: `Lather.Prefetch` (GenServer TTL cache) plus the
  `prefetch:` and `prefetch_pool:` options on `DynamicClient.call/4`
  prefetch related operations asynchronously after each response and serve
  them from cache on later calls.
- gRPC-style streaming: operation handlers can return `{:stream, items}`;
  the server emits one chunked SOAP response envelope per item, and
  `DynamicClient.stream_operation/4` returns a lazy stream of parsed
  chunks.
- WS-Addressing: `DynamicClient.call/4` accepts `addressing: true` or
  `addressing: %{to:, from:, action:, message_id:}` to add wsa headers;
  `Lather.Wsdl.Addressing` provides message-id generation, header
  extraction, validation, and action-to-operation routing, and
  `require_addressing: true` enforces it server-side.
- WS-Policy negotiation: services publish a policy document at
  `GET <endpoint>?policy` (`policy:` option on EnhancedPlug), and
  `Lather.Policy.negotiate/1` plus the `negotiate: true` call option
  validate request options against the published policy.
- WS-Discovery: services with `enable_discovery: true` answer WS-Discovery
  Probe requests at `<endpoint>?discovery` with Matches documents, and
  `Lather.Discovery.probe/1` discovers services over HTTP.
- WS-Eventing: `Lather.Eventing` provides subscribe/publish/poll channels
  with WS-Eventing Notify envelopes; services with `enable_eventing: true`
  expose `?subscribe=`, `?publish=` and `?events&sub=` routes.

## [1.2.1] - 2026-10-13

### Added
- Request-level tests for the enhanced server's form pages, WSDL variants,
  SOAP versions, and JSON endpoints; raise the CI coverage floor to 75%.
- SOAP body tests for prefixed namespaces, optional parameters, required types,
  and Unicode character limits.
- Type mapper and generated-struct round-trip tests for booleans, repeated
  values, and nested complex values.

### Fixed
- Enhanced server responses no longer duplicate the UTF-8 charset in HTML,
  WSDL, and JSON content types.
- JSON requests follow lowercase operation paths advertised in enhanced WSDL,
  and invalid operations or parameters return JSON client errors.
- Enhanced WSDL omits the HTTP binding when JSON routes are disabled.
- `Lather.Soap.Body.create/3` declares the namespace used by a prefixed
  operation, and `validate_params/2` accepts absent optional values and counts
  characters rather than bytes for `:max_length`.
- Type mapping preserves `false` values and converts repeated primitive and
  namespace-prefixed complex values without recursion errors. Generated structs
  preserve repeated fields and accept the module list returned by
  `generate_structs/2`.

## [1.2.0] - 2026-10-13

### Added
- `Lather.Xml.Parser.element_document/2` extracts a namespaced XML subtree
  with its inherited namespace declarations, so SOAP RPC elements can be parsed
  independently of the envelope (#23).
- Local request and XML round-trip regression tests, plus CI that runs the full
  test suite with a coverage floor on pushes and pull requests.

### Changed
- Development toolchain pins to Elixir 1.20.4 on Erlang/OTP 29.1.1.
- Require xml_builder 2.4.1 or newer so text escaping is handled consistently
  by the renderer.

### Fixed
- `Lather.Soap.Body.create/3` and WSDL-generated requests preserve raw text
  containing ampersands, angle brackets, and literal XML entity-looking text
  when rendered with xml_builder 2.4.1 (#24).
- `Lather.Client.call/4` uses the selected SOAP version for both the HTTP
  content type and envelope, forwards operation namespaces, and keeps SOAP
  headers separate from HTTP headers (#25).
- Integration test servers use OS-assigned ports to avoid intermittent address
  collisions in CI.

## [1.1.0] - 2026-09-05

### Added
- `Lather.Soap.Elements`: prefix-agnostic lookups (`get/2`, `get_in/2`,
  `local_name/1`, `soap_version/1`) over parsed SOAP documents.

### Changed
- `Lather.Xml.Builder`: a bare list value under a key now renders as repeated
  sibling elements (`%{"Item" => ["1", "2"]}` → `<Item>1</Item><Item>2</Item>`),
  mirroring how `Lather.Xml.Parser` represents repeated elements. Previously a
  list rendered as a single element whose content was the joined items. A list
  of `{key, value}` pairs keeps its ordered-children meaning (#9).

### Fixed
- SOAP envelopes with any namespace prefix (`soapenv:`, `SOAP-ENV:`, `s:`,
  `env:`, none, ...) are now accepted by `Lather.Soap.Envelope.parse_response/1`,
  `Lather.Server.RequestParser`, `Lather.DynamicClient` fault detection,
  `Lather.Error.parse_soap_fault/2` and `Lather.Operation.Builder`; the SOAP
  version is detected from the namespace bound to whichever prefix is used. A
  document without an Envelope is reported as `{:error, :invalid_soap_response}`
  instead of `{:error, {:soap_fault, :invalid_soap_response}}` (#10).
- `Lather.Soap.Envelope.parse_response/1` returns `{:ok, %{}}` for an empty
  `<Body/>` instead of raising (#11).
- `Lather.Server.Handler`: malformed XML now yields a 400 Client fault instead
  of raising (#12); successful responses are no longer double-wrapped in
  `<Response><OpResponse>` and match `Lather.Server.Plug` byte for byte (#13);
  every `POST` is a SOAP call and every `GET` serves the WSDL, so paths that
  happen to contain "wsdl" no longer get a 405 (#14). Transport-level faults
  are built with `ResponseBuilder.build_fault/1` so fault strings are escaped.
- `Lather.Operation.Builder` (used by `Lather.DynamicClient.call/4`) serialises
  parameters with `Lather.Soap.Body.serialize_params/1`: nested maps no longer
  raise, lists render as repeated elements instead of being concatenated, and
  dates/booleans are rendered as XML literals. Array-typed parts wrap list values
  in the array's item element (from WSDL `:types` when available, else `item`)
  (#17).
- `Lather.Operation.Builder.validate_parameters/2` no longer requires parts the
  WSDL marks `minOccurs="0"`, matching `get_operation_metadata/1` (#18).
- `Lather.DynamicClient` `:authentication` option: `{:basic, u, p}` raised a
  `KeyError` (the client struct has no `headers` field) and
  `{:wssecurity, u, p}` was silently ignored. Basic auth is now sent as the
  `Authorization` header and WS-Security as a `UsernameToken` SOAP header;
  `{:wssecurity, u, p, opts}` passes options such as `password_type: :digest`
  (#19).
- `Lather.Auth.Basic.decode/1` accepts the `Basic` scheme case-insensitively and
  tolerates extra whitespace, per RFC 7235 (#21).
- SOAP 1.2 requests now get SOAP 1.2 responses from `Lather.Server.Plug`,
  `Handler` and `EnhancedPlug`: the envelope namespace, `Code/Value` +
  `Reason/Text` fault structure and `application/soap+xml` content type follow
  the version of the request envelope (`RequestParser` now reports
  `:soap_version`). `ResponseBuilder.build_response/3` and `build_fault/2` take
  a `:soap_version` option (#22).
- `Lather.Auth.WSSecurity.username_token/3` with `password_type: :digest` always
  produces a digest (nonce and created are optional inputs to it) instead of
  silently falling back to `PasswordText`; an unknown `password_type` raises (#20).
- `Lather.Server.validate_param_types/2` validates the lexical form of simple
  XSD types (`int`, `decimal`, `boolean`, `dateTime`, `date`, `time`, ...),
  accepts DSL atom types and `xsd:` prefixes, and returns a Client fault instead
  of raising when structured content is sent for a simple type (#16).
- `Lather.Server.RequestParser`: empty elements are `""` (was `%{}`), list items
  get the same namespace/attribute cleaning as single elements, and an element
  carrying only attributes and text collapses to its text (#15).
- `Lather.Xml.Builder`: a `parse/1` → `build_fragment/1` round-trip no longer
  collapses repeated elements into one element with joined text (#9).
- `Lather.Xml.Builder`: an element can now carry attributes and repeated child
  siblings, e.g. `%{"@xsi:type" => "...", "string" => ["A", "B"]}`; `#content`
  with `{tag, value}` pairs remains available for ordered children (#8).
- `Lather.Xml.Builder`: mixed content (`#text` alongside child elements) emits a
  text node instead of a literal `<#text>` element.
- `Lather.Soap.Body.serialize_params/1` and
  `Lather.Server.ResponseBuilder`: `DateTime`/`Date`/`Time` (and boolean)
  clauses are ordered ahead of the generic map/atom clauses so date/time values
  serialize to ISO 8601 instead of raising; regression tests added (#7).

## [1.0.49] - 2026-06-08

### Changed
- Updated development toolchain metadata to Elixir 1.20.0 on Erlang/OTP 29.
- Updated HTTP and documentation dependencies, including Bandit, Finch, Plug, ExDoc, Jason, and Telemetry.
- Adjusted Finch pool configuration for current Finch versions.

### Fixed
- Removed compiler warnings surfaced by Elixir 1.20 in project code and tests.
- Hardened an integration test server setup against random port collisions.

## [1.0.5] - 2025-12-25

### Added
- **4 new livebooks** for comprehensive feature coverage:
  - `soap12_client.livemd` - SOAP 1.2 protocol differences and client usage
  - `mtom_attachments.livemd` - Binary data transmission with MTOM/XOP
  - `production_monitoring.livemd` - Telemetry, metrics, health checks, and dashboards
  - `testing_strategies.livemd` - Unit testing, mocking, integration and contract testing
- **5 new example files** demonstrating advanced features:
  - `mtom_client.ex` - MTOM attachment handling
  - `calculator_service.ex` - Multi-type operations with error handling
  - `enhanced_plug_example.ex` - Multi-protocol server endpoints
  - `phoenix_integration.ex` - Complete Phoenix setup patterns
  - `ws_security_service.ex` - WS-Security authentication and validation
- **API.md expanded** from 13 to 30 modules (100% coverage)
- **Enhanced livebooks** with ~1,400 lines of new content:
  - `soap_server_development.livemd` - EnhancedPlug demos and multi-protocol examples
  - `enterprise_integration.livemd` - Circuit breakers, retry strategies, resilience patterns

### Fixed
- Corrected `WsdlGenerator` → `WSDLGenerator` module name references across all documentation
- Fixed non-existent `security_header/2` API references in enterprise examples and livebooks
- Fixed invalid Elixir `return` statements in debugging livebook
- Fixed `IP.puts` typo in debugging livebook
- Updated `TESTING.md` to use correct `--include external_api` flag (removed incorrect `ENABLE_LIVE_API_TESTS` references)
- Corrected `username_token/3` documentation to show keyword options instead of atom argument

### Changed
- Updated examples READMEs to accurately reflect existing files (removed 9 non-existent file references)
- All 11 livebooks now listed in README.md and USAGE.md
- Version references updated to 1.0.5 throughout documentation

## [1.0.4] - 2025-12-02

### Added
- Enhanced multi-protocol support documentation in soap_server_development livebook
- Examples of EnhancedPlug and EnhancedWSDLGenerator usage
- Phoenix router patterns for multi-protocol endpoints

### Changed
- Updated livebook documentation to highlight v1.0+ enhanced features
- Improved deployment patterns section with basic and enhanced examples

## [1.0.3] - 2025-12-02

### Fixed
- Removed references to non-existent CONTRIBUTING.md file from all documentation
- Updated GitHub repository references from markcotner to awksedgreep across all files

## [1.0.1] - 2025-01-15

### Changed
- Updated documentation to reflect current v1.0.0 status rather than treating it as "next release"
- Enhanced README with comprehensive livebooks section and detailed descriptions of all 7 interactive tutorials
- Updated USAGE.md with current API examples, multi-protocol capabilities, and production-ready patterns
- Updated all livebooks to reference correct version numbers and include hex package installation options
- Improved overall documentation consistency and confidence about current capabilities
- Updated roadmap to focus on v1.1.0, v1.2.0, and future releases

## [1.0.0] - 2025-01-15

### 🚀 **Production Release - Enhanced Multi-Protocol SOAP Library**

This is the first stable release of Lather, featuring comprehensive SOAP 1.1 and SOAP 1.2 support with modern web interfaces and multi-protocol capabilities.

### Added

- 🌟 **Enhanced WSDL Generation** (434 lines)
  - Multi-protocol WSDL documents with SOAP 1.1, SOAP 1.2, and HTTP/REST bindings
  - Layered API approach: SOAP 1.1 (compatibility) → SOAP 1.2 (enhanced) → REST/JSON (modern)
  - Protocol negotiation and automatic version detection
  - Enhanced inline documentation and service metadata
  - Backward compatibility with existing WSDL generators

- 📝 **Interactive Web Forms** (832 lines)
  - Professional HTML5 interface similar to .NET Web Services
  - Interactive operation testing with real-time form validation
  - Multi-protocol examples (SOAP 1.1, SOAP 1.2, JSON/REST)
  - Responsive CSS design with mobile support
  - **Dark mode support** - Automatically respects browser dark mode preference
  - JavaScript-powered form interaction and submission
  - Parameter validation and type-aware input controls

- 🔌 **Enhanced Plug Integration** (562 lines)
  - Multi-endpoint routing for different protocols
  - Content negotiation and automatic protocol detection
  - Interactive web interface hosting
  - Multiple WSDL variants per service (standard and enhanced)
  - RESTful JSON endpoints alongside SOAP

- 🌐 **Complete SOAP 1.2 Support** (85-90% implementation)
  - Full SOAP 1.2 envelope handling with correct namespaces
  - Version-aware HTTP transport with proper Content-Type headers
  - Enhanced error handling and fault processing
  - 17/17 integration tests passing (100% success rate)
  - Real-world service validation completed

- 🏗️ **Three-Layer Protocol Architecture**
  ```
  ┌─ SOAP 1.1 (Top - Maximum Compatibility)    │ Legacy systems, .NET Framework
  ├─ SOAP 1.2 (Middle - Enhanced Features)     │ Modern SOAP with better error handling  
  └─ REST/JSON (Bottom - Modern Applications)  │ Web apps, mobile, JavaScript
  ```

### Enhanced

- **WSDL Generation**: Now supports multiple protocol bindings in single document
- **Service Discovery**: Enhanced metadata and operation documentation
- **User Experience**: Dark mode support for better accessibility and modern UX
- **Error Handling**: Improved fault processing for SOAP 1.2
- **Performance**: Sub-millisecond processing overhead, optimized for production
- **Testing**: Comprehensive test suite with 549/556 tests passing (98.7%)

### URL Structure

- `GET  /service` → Service overview with interactive forms
- `GET  /service?wsdl` → Standard WSDL (SOAP 1.1 only)  
- `GET  /service?wsdl&enhanced=true` → Multi-protocol WSDL
- `GET  /service?op=OperationName` → Interactive operation testing form
- `POST /service` → SOAP 1.1 endpoint (maximum compatibility)
- `POST /service/v1.2` → SOAP 1.2 endpoint (enhanced features)
- `POST /service/api` → JSON/REST endpoint (modern applications)

### Dependencies

- Added `{:jason, "~> 1.4", optional: true}` for JSON support in enhanced features
- Made Plug integration more robust with graceful degradation

### Fixed

- Resolved unused variable warnings in enhanced modules
- Improved error handling for missing optional dependencies
- Enhanced list length checking for better performance
- Better JSON encoding/decoding with fallback handling

### Performance

- **Small requests (<10KB)**: 1-3ms processing overhead
- **Large requests (>100KB)**: Network-bound, processing negligible
- **WSDL generation**: 10-50ms one-time cost
- **Memory usage**: Optimized with native Elixir data structures

### Compatibility

- ✅ **Full backward compatibility** maintained
- ✅ **Existing 0.9.x services** work unchanged
- ✅ **Standard WSDL** generation unchanged
- ✅ **All existing APIs** preserved

### Migration from 0.9.x

No breaking changes. Enhanced features are additive:

```elixir
# Existing code continues to work
service_info = MyService.__service_info__()
wsdl = Lather.Server.WSDLGenerator.generate(service_info, base_url)

# Enhanced features available optionally
enhanced_wsdl = Lather.Server.EnhancedWSDLGenerator.generate(service_info, base_url)
forms = Lather.Server.FormGenerator.generate_service_overview(service_info, base_url)
```

### Known Limitations

- **MTOM Attachment Support**: Currently incomplete with 7 failing tests related to binary attachment handling. This does not affect core SOAP 1.1/1.2 functionality or any enhanced features. MTOM is an advanced feature for optimizing large binary transfers.
- **JSON Endpoint Integration**: Requires optional `jason` dependency for full functionality. Gracefully degrades when not available.

### What's Next (v1.1.0+)

- **MTOM Support Completion**: Complete binary attachment handling (7 failing tests to resolve)
- **OpenAPI 3.0 Integration**: Generate OpenAPI specs from SOAP services  
- **WS-Security Enhancements**: XML Signature and Encryption support
- **Advanced Authentication**: OAuth 2.0 and JWT token support

---

## [0.9.0] - 2025-10-30

### Added
- 🚀 **Complete SOAP Client Framework**
  - Generic SOAP client with dynamic operation discovery
  - WSDL parsing and analysis with comprehensive type extraction
  - Dynamic client generation from any WSDL
  - Support for complex types, arrays, and nested structures
  - Automatic type mapping and struct generation

- 🛡️ **Authentication & Security**
  - WS-Security UsernameToken support (PasswordText & PasswordDigest)
  - HTTP Basic Authentication
  - Custom authentication headers
  - Timestamp and nonce generation
  - Pluggable authentication system

- 🖥️ **SOAP Server Framework**
  - Complete server-side SOAP implementation
  - Macro-based DSL for defining SOAP services
  - Automatic WSDL generation from service definitions
  - Phoenix integration via Plug
  - Generic HTTP handler for standalone deployment
  - Operation dispatch and request/response handling

- 🏗️ **Core Infrastructure**
  - Robust XML parsing and generation
  - SOAP envelope construction and parsing
  - HTTP transport with Finch (connection pooling, SSL/TLS)
  - Comprehensive error handling with structured error types
  - Telemetry integration for observability
  - Support for SOAP 1.1 standard

- 📚 **Documentation & Examples**
  - 5 comprehensive Livebook tutorials
  - Interactive client examples with real SOAP services
  - Server implementation guides
  - Type system and debugging tutorials
  - Enterprise integration patterns
  - Complete API documentation

### Features
- **Universal WSDL Support**: Works with any SOAP service without hardcoded implementations
- **Type Safety**: Automatic type validation and conversion
- **Phoenix Integration**: Seamless integration with Phoenix applications
- **Production Ready**: Comprehensive error handling, logging, and monitoring
- **Extensible**: Pluggable architecture for custom authentication and transport

### Technical Details
- Built on Elixir 1.14+ and OTP 25+
- Uses Finch for HTTP transport with connection pooling
- SweetXml for robust XML parsing
- Custom XML builder for reliable SOAP envelope generation
- Telemetry for metrics and observability
- Optional Plug dependency for Phoenix integration

### Compatibility
- SOAP 1.1 (SOAP 1.2 planned for v1.0)
- WSDL 1.1 with XSD schema support
- HTTP and HTTPS transport
- Works with any SOAP service (tested with multiple public APIs)

## [1.1.0] - 2026-09-05

### Planned for v1.0.0
- SOAP 1.2 support
- Enhanced WS-Security features
- Performance optimizations
- Additional server examples
- Binary attachment support (MTOM)
- Advanced WS-* standards support

---

**Note**: This library went from concept to full-featured SOAP ecosystem in record time, 
delivering both client and server capabilities that were originally planned across multiple phases.
