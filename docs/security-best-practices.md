# Security Best Practices

- **Auth**: use `auth:` on EnhancedPlug (basic and bearer token support
  via `with_auth`). For WS-Trust style flows, validate issued tokens in
  a `Lather.Plugin` `before_request` hook.
- **TLS**: terminate TLS at a gateway or configure Bandit with a
  certificate; never expose plain HTTP with auth enabled over a public
  network.
- **Input limits**: set `max_response_bytes` on transport calls and
  bound `iterations` in LoadTest to prevent memory abuse.
- **Schema validation**: validate parameters with `enum:`, `min:`,
  `max:`, `pattern:` in the DSL so malformed payloads fail before
  handler code runs.
- **Secrets**: load config via `config_file:` from a sealed file or
  environment; do not embed credentials in service modules.
- **Fault hygiene**: SOAP faults from handlers should expose only
  client-safe messages; internal details are logged separately under
  `debug: true`.
- **Supply chain**: `mix deps.get --check-locked` in CI pins dependency
  versions; review lockfile changes in pull requests.
