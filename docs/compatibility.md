# Compatibility Matrix

## Elixir / OTP

| Lather version | Elixir | OTP | Tested in CI |
|---|---|---|---|
| 1.3.x | 1.16 - 1.20 | 25 - 29 | 1.20 / OTP 29 (`mix test --cover`) |
| 1.2.x | 1.16 - 1.19 | 25 - 28 | historical |
| 1.1.x | 1.14 - 1.19 | 24 - 27 | historical |
| 1.0.x | 1.13+ | 23+ | historical |

`.tool-versions` pins the CI toolchain. Dependencies are locked in
`mix.lock` and CI runs `mix deps.get --check-locked` to catch drift.

## SOAP standards support

| Standard | Status | Module |
|---|---|---|
| SOAP 1.1 | Full | `Lather.Soap` |
| SOAP 1.2 (full envelope/fault codes/roles) | Full | `Lather.Soap.FaultCodes`, `Lather.Soap.Profile` |
| WS-I Basic Profile structural validation | Basic | `Lather.Soap.Profile` |
| WS-Security (signature, encryption, SAML) | Supported | `Lather.Auth.*` |
| WS-Addressing | Supported | `Lather.Wsdl.Addressing` |
| WS-Policy | Supported | `Lather.Policy` |
| WS-ReliableMessaging | Supported (retry/backoff) | `Lather.ReliableMessaging` |
| WS-Discovery | Supported | `Lather.Discovery` |
| WS-Eventing | Supported | `Lather.Eventing` |
| MTOM | Supported (+cache, streaming) | `Lather.Mtom.*` |
| HTTP/2 transport | Not native; use a gateway | see `docs/http2-websocket.md` |
| WebSocket transport | Not implemented | see `docs/http2-websocket.md` |

## SOAP version interop

`test/integration/multi_version_integration_test.exs` exercises SOAP
1.1 and 1.2 clients against a single service.
