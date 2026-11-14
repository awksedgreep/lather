# Migration Guide

## From Lather 1.0 to 1.2

- `Lather.Server.validate_param_types/2` now returns
  `{:ok, validated_params}` instead of `:ok`. Callers must extract the
  params from the tuple.
- SOAP 1.2 faults now carry `<soap:Subcode>` elements from
  `Lather.Soap.FaultCodes`; clients that string-match the fault text
  should also check `fault[:fault_code]`.
- `DynamicClient.call/4` accepts new optional keys (`addressing:`,
  `negotiate:`, `reliable:`, `prefetch:`, `pool_name:`,
  `max_response_bytes:`); all are backward compatible and off by
  default.
- Handlers returning `{:stream, items}` are a new option; existing
  `{:ok, map}` results are unchanged.
- Multi-tenant servers use the `tenants:` option; single-tenant configs
  are unaffected.

## Migrating a WSDL-first consumer to DynamicClient

1. Replace hand-written SOAP envelope builders with
   `DynamicClient.new(wsdl_url)` + `call/4`.
2. Move custom headers into a `Lather.Plugin` `before_request` hook.
3. Move retry logic to `reliable: true`; keep plugin-based retries only
   for domain-specific error classes.
4. Replace polling loops with WS-Eventing subscriptions
   (`enable_eventing: true`) where the service supports it.
