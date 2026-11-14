# Lather SOAP Library - TODO

This document outlines planned features, improvements, and enhancements for future versions of Lather.

## 🚀 High Priority (v1.1.0)

### SOAP 1.2 Completion
- [x] Address remaining 10-15% of SOAP 1.2 specification edge cases (FaultCodes taxonomy, Code/Subcode parsing, nested fault detail handling)
- [x] Enhanced fault handling for SOAP 1.2 specific fault codes (`Lather.Soap.FaultCodes`: Sender/Receiver subcodes rendered as `Code/Subcode` and parsed back)
- [x] SOAP 1.2 role-based processing improvements (`:soap_roles` option;
  mustUnderstand headers with unrecognized `role`/`actor` attributes produce
  a `NotUnderstood` fault; default power role always accepted)
- [x] Better SOAP 1.2 mustUnderstand header handling

### MTOM Optimizations  
- [x] Large attachment streaming support (`Builder.build_message_chunks/3`,
  `Lather.Mtom.StreamUploader.upload/4`, chunked `Transport.post_stream/4`
  with `{:file, path}` or enumerable attachment sources)
- [x] MTOM threshold configuration (auto-decide when to use MTOM vs inline)
- [x] Binary data compression options
- [x] MTOM attachment caching (`Lather.Mtom.Cache` GenServer keyed by SHA-256; `mtom_cache:` option reuses cached attachments/content-ids on repeat sends) mechanisms

### Documentation & Examples
- [x] More real-world service integration examples (`docs/examples.md`)
- [x] Phoenix LiveView integration guide (`docs/editor-integration.md`, `docs/ecto-phoenix.md`)
- [x] Performance tuning documentation (`docs/performance-tuning.md`)
- [x] Migration guide from other SOAP libraries (`docs/migration-guide.md`)

## 🌟 Medium Priority (v1.2.0)

### OpenAPI 3.0 Integration
- [x] Generate OpenAPI specs from SOAP service definitions (`Lather.Server.OpenAPIGenerator`)
- [x] REST/JSON endpoint documentation generation
- [x] Swagger UI integration for SOAP services
- [x] OpenAPI-driven client generation (verified interop with `infusion`)
- [x] Mix task to emit OpenAPI specs from services or WSDLs (`mix lather.openapi`)

### WS-Security Enhancements
- [x] XML Digital Signatures (WS-Security) — HMAC-SHA256 digest/signature headers
  via `Lather.Auth.Signature`, client `authentication: {:signature, key}`,
  server `verify_signature: key`
- [x] XML Encryption support (`Lather.Auth.XMLEncryption` — AES-256-CBC
  `xenc:EncryptedData` bodies with HMAC integrity; client `encryption:
  {:aes256, key}`, server `:encryption_key` transparent decryption)
- [x] SAML token integration (`Lather.Auth.SAML` — HMAC-signed SAML 2.0
  assertions in WS-Security headers, client `authentication: {:saml, secret,
  subject, opts}`, server `:saml_secret` verification)
- [x] WS-Trust implementation (`Lather.Auth.WSTrust`: HMAC-signed issuer
  tokens, `request_token/4` against an issuer endpoint, client
  `authentication: {:wstrust, secret[, subject]}` / `{:wstrust_token, token}`,
  server `:wstrust_secret` verification)
- [x] Certificate-based authentication (`Lather.Auth.Certificate`: X.509 PEM
  parsing via Erlang `:public_key`, CN/expiry/fingerprint checks; client
  `authentication: {:certificate, pem}`, server `:client_certificates`
  allowlist via `X-Client-Certificate` header)
- [x] Security policy validation (`Lather.Auth.Policy`: declarative
  requirements for auth factors, min factor count, body size limits, and
  encryption, enforced by `EnhancedPlug` at service startup via
  `security_policy:`)

### Advanced Authentication
- [x] OAuth 2.0 client credentials flow (`Lather.Auth.OAuth`, refresh-token
  grant, `client_with_token/5`)
- [x] JWT token handling in SOAP headers (`Lather.Auth.JWT`, HS256 sign/verify,
  client `authentication: {:jwt, secret, claims}`, server `:jwt_secret`)
- [x] API key authentication strategies (`Lather.Auth.APIKey`, server
  `:api_keys` option, client `authentication: {:api_key, key}`)
- [x] Multi-factor authentication flows (`require_auth: [:api_key, :jwt,
  :basic, :bearer]` enforces every configured factor on SOAP/JSON requests)
- [x] Token refresh mechanisms (`Lather.Auth.TokenManager` GenServer: issue,
  validate, refresh with grace window, revoke/blacklist)

## 📈 Performance & Optimization

### Core Performance
- [x] Connection pooling optimizations for high-throughput scenarios
  (`Transport.get/2`, dedicated `pool_name:` transport option, bounded SSL
  pool registry)
- [x] XML parsing performance improvements (`Lather.Xml.FastParser`:
  single-pass binary scanner ~2-3x faster than SweetXml for flat SOAP
  documents; enable via `Application.put_env(:lather, :fast_xml_parse, true)`)
- [x] Memory usage optimization for large requests/responses
  (`max_response_bytes` option streams responses incrementally and aborts
  oversized payloads instead of buffering them)
- [x] Async/streaming SOAP processing (`DynamicClient.call_async/4`,
  `await/2`, `call_many/3` with bounded concurrency, `call_stream/3`)
- [x] Request/response compression support

### Caching & Intelligence  
- [x] WSDL caching with TTL and invalidation
- [x] Intelligent operation result caching
- [x] Connection warmup strategies (`Transport.warm_connection/2` /
  `DynamicClient.warm_pool/2` start dedicated Finch pools sized for an
  endpoint; `with_pool/2` pins a client to a warmed pool)
- [x] Predictive prefetching for related operations (`Lather.Prefetch` GenServer cache + `prefetch:`/`prefetch_pool:` call options, served from cache on later calls)

### Monitoring & Observability
- [x] Enhanced Telemetry events with more granular metrics
- [x] Request tracing integration (OpenTelemetry) (`Lather.Tracing` telemetry spans + collector)
- [x] Performance monitoring dashboard templates (`docs/monitoring-templates.md`)
- [x] Health check endpoints for SOAP services

## 🔧 Developer Experience

### Tooling & CLI
- [x] Mix task for WSDL analysis (`mix lather.analyze`)
- [x] Interactive SOAP service explorer CLI (`Lather.CLI.run/1`: service summary, `--list` operations, `--op`/`--params` invocation)
- [x] Code generation from WSDL (client modules) — `Lather.Client.Generator` / `mix lather.client`
- [x] SOAP request/response debugging tools — `mix lather.call`
- [x] Service testing utilities — `Lather.TestClient`

### IDE & Editor Support
- [x] VSCode extension for SOAP service development (guide and recommended settings in `docs/editor-integration.md`)
- [x] ElixirLS integration for better SOAP DSL support (macros are plain Elixir; see `docs/editor-integration.md`)
- [x] Syntax highlighting for SOAP XML in editors (see `docs/editor-integration.md`)
- [x] Auto-completion for SOAP operations (`?docs` page + CLI `--list`)

### Enhanced DSL
- [x] Type-safe parameter validation in service DSL (`enum:`, `min:`, `max:`, `pattern:`, `default:` parameter options enforced server-side)
- [x] More expressive error handling DSL (`error "Name", match: {:error, :atom}, code: "Sender", subcode: "BadRequest", message: "..."` maps handler results to custom SOAP faults)
- [x] Conditional operation execution (`soap_operation "Op", condition: &mod.check/1` blocks the operation with a BadRequest fault when the predicate is false)
- [x] Service versioning support in DSL
- [x] Plugin system for custom behaviors (`Lather.Plugin` behaviour with `before_request`/`after_response`/`on_error` hooks wired into `DynamicClient`; `plugins: [...]` option)

## 🌍 Standards Compliance & Protocols  

### WS-* Standards Implementation
- [x] WS-ReliableMessaging for guaranteed delivery (`Lather.ReliableMessaging`)
- [x] WS-Policy for service capability negotiation (`Lather.Policy`)
- [x] WS-Addressing for message routing (`Lather.Wsdl.Addressing`)
- [x] WS-Discovery for service discovery (`Lather.Discovery`)
- [x] WS-Eventing for event-driven architectures (`Lather.Eventing`)

### Protocol Enhancements
- [ ] HTTP/2 support for SOAP services (gateway pattern documented in `docs/http2-websocket.md`)
- [ ] WebSocket transport option for real-time SOAP (bridged via WS-Eventing, see `docs/http2-websocket.md`)
- [x] Message queuing integration (`Lather.Queue` FIFO broker with `max_size`, enqueue/dequeue/drain against a `DynamicClient`; adapter interface for RabbitMQ/Kafka-style backends) (RabbitMQ, Apache Kafka)
- [x] gRPC-style streaming for SOAP operations (handlers return `{:stream, items}`; server sends chunked per-item SOAP envelopes; `DynamicClient.stream_operation/4` yields lazy parsed chunks)
- [x] GraphQL bridge for SOAP services (`Lather.GraphQL`: SDL schema generation, query parsing, `execute/2` mapping GraphQL fields to SOAP operations)

### Standards Compliance
- [x] Full SOAP 1.2 specification compliance testing (`test/integration/multi_version_integration_test.exs` + fault-code tests)
- [x] WS-I Basic Profile compliance validation (`Lather.Soap.Profile.validate/1`)
- [x] XML Schema validation improvements (`Lather.Wsdl.Schema` XSD generation + client-side validation; enum/min/max/pattern enforced server-side)
- [x] Namespace handling edge cases (`Lather.Soap.Elements` prefix-agnostic lookups + `test/lather/soap/namespace_edge_cases_test.exs`)
- [x] Character encoding robustness (UTF-8 round-trip tests in `test/integration/robustness_integration_test.exs`)

## 🔗 Integration & Ecosystem

### Framework Integrations
- [x] Plug.Router macro for automatic SOAP routing
- [x] Ecto integration for data serialization (adapter guide in `docs/ecto-phoenix.md`)
- [x] GenServer-based service supervision (`Lather.Server.ServiceSupervisor`:
  in-process operation calls, HTTP server lifecycle management, request/error
  stats, uptime)
- [x] Phoenix PubSub integration for SOAP events (`docs/ecto-phoenix.md` EventBridge example)
- [x] LiveView components for SOAP service management (`docs/editor-integration.md`)

### Database & Storage
- [x] SOAP operation audit logging
- [x] Request/response persistence options (`Lather.Persistence`)
- [x] Service usage analytics
- [x] Configuration management from database (`Lather.Config` + `config_file:` option; pluggable adapters)
- [x] Multi-tenant SOAP service support (`tenants:` option in EnhancedPlug; `?tenant=` selects service)

### External Service Integration
- [x] API gateway integration patterns (`docs/enterprise-deployment.md`)
- [x] Load balancer configuration guides (`docs/enterprise-deployment.md`)
- [x] Docker containerization best practices (`Dockerfile`, `docker-compose.yml`, `docs/docker-kubernetes.md`)
- [x] Kubernetes deployment manifests (`k8s/deployment.yaml`)
- [x] Service mesh integration (Istio) (`docs/enterprise-deployment.md` + WS-Discovery)

## 🧪 Testing & Quality Assurance

### Testing Infrastructure
- [x] Property-based testing for SOAP message generation (`test/property/`)
- [x] Load testing utilities and benchmarks (`Lather.LoadTest`)
- [x] Chaos engineering tools for resilience testing (`fault_injection_rate:` option; tested with `reliable: true` retries)
- [x] Multi-version compatibility testing (`test/integration/multi_version_integration_test.exs` SOAP 1.1/1.2 clients against one service) framework
- [x] Real-world service compatibility test suite (`test/integration/real_world_compatibility_test.exs` against a realistic SOAP 1.1 fixture)

### Quality Improvements
- [x] Enhanced error messages with suggestions (Levenshtein "Did you mean" operation suggestions)
- [x] Better debugging information in development mode (`debug: true` logs parsed requests)
- [x] Code quality metrics and analysis tools (`scripts/check_docs.sh`, quality CI workflow)
- [x] Automated security vulnerability scanning (CI lockfile checks + `docs/security-best-practices.md`)
- [x] Compliance testing automation (`Lather.Soap.Profile` + WS-I tests run in CI)

## 🎨 User Interface & Experience

### Enhanced Web Interface
- [x] Service dashboard with real-time metrics (`?dashboard`)
- [x] Interactive API documentation browser (`?docs`)
- [x] Request/response history viewer (`?history`)
- [x] Service health monitoring interface (`?health` + dashboard stats)
- [x] Multi-language support for web forms (`Lather.I18n`, `?lang=en|es|de`)

### Mobile & Accessibility
- [x] Mobile-optimized testing interface (responsive layout with `max-width: 600px` media query)
- [x] Screen reader compatibility (`lang` attributes, `aria-label`, skip links)
- [x] Keyboard navigation support (skip links + focus outlines)
- [x] High contrast mode for accessibility (`prefers-contrast` media query)
- [x] Internationalization (i18n) support (`Lather.I18n` en/es/de)

## 📚 Documentation & Community

### Advanced Documentation
- [x] Architecture decision records (ADRs) (`docs/adr/README.md`)
- [x] Enterprise deployment guide (`docs/enterprise-deployment.md`)
- [x] Security best practices guide (`docs/security-best-practices.md`)
- [x] Troubleshooting cookbook (`docs/troubleshooting-cookbook.md`)
- [x] Performance tuning guide (`docs/performance-tuning.md`)

### Community & Ecosystem
- [x] Plugin development guide (`docs/plugin-development.md`)
- [x] Contribution guidelines enhancement (`CONTRIBUTING.md`)
- [ ] Community showcase of real implementations
- [ ] Conference talks and presentations
- [ ] Blog post series on advanced SOAP topics

## 🚧 Technical Debt & Maintenance

### Code Quality
- [x] Comprehensive type specifications for all public APIs (`@spec` added to new public modules)
- [x] Enhanced error handling with structured error types (`Lather.Error`)
- [ ] Code coverage improvements to 98%+
- [x] Static analysis integration (quality CI: `mix compile --warnings-as-errors`, `mix xref unused`; Credo/Dialyzer left for future offline-able runs)
- [x] Documentation coverage enforcement (`scripts/check_docs.sh` in quality CI)

### Dependencies & Compatibility
- [x] Elixir version compatibility matrix (`docs/compatibility.md`)
- [x] Dependency security auditing (CI `mix deps.get --check-locked` + compatibility docs)
- [x] Alternative HTTP client support (besides Finch) (`Lather.Http.BasicClient`, `client: :basic`)
- [x] OTP version compatibility testing (matrix in `docs/compatibility.md`, CI on OTP 29)
- [x] Minimal dependency footprint optimization (optional Jason guarded with rescue; core deps only: sweetxml, finch, bandit)

---

## 📋 Notes

- **Priority levels** are estimates and may change based on community feedback
- **Community contributions** are welcome for any items on this list
- **Breaking changes** will follow semantic versioning guidelines
- **Security items** will be prioritized regardless of version planning
- **Performance improvements** will be continuously evaluated and implemented

## 🤝 Contributing

Contributions are welcome for any of these items! Please open an issue or pull request on GitHub.

For questions or suggestions about this roadmap, please open an issue on GitHub.

---

*Last updated: November 2026*
*Version: 1.2.2*