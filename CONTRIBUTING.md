# Contributing to Lather

Thanks for helping! This repo follows the conventions below.

## Getting started

```bash
mix deps.get
mix format
mix test
```

## Pull request checklist

- [ ] `mix format` passes cleanly.
- [ ] New behavior has at least one unit or integration test.
- [ ] Run the full suite: `mix format && mix test` (targeted tests for
  fast iteration, full suite before pushing).
- [ ] Update `TODO.md` (mark item complete), `CHANGELOG.md` (add an
  entry), and the README if the feature is user-facing.
- [ ] Public functions have `@doc` documentation and, where practical,
  doctests or `@spec`.

## Code conventions

- Modules are small and focused; place new features in a dedicated
  module (see `Lather.Eventing`, `Lather.Policy` as examples).
- GenServers expose a GenServer-style API and clean up linked processes
  with `Process.unlink`/`Process.exit` in tests.
- Optional dependencies (`Jason`) are guarded with rescue so the library
  still compiles without them.
- Keep the dependency footprint minimal; discuss new deps in the PR.

## Documentation

- ADRs go under `docs/adr/`.
- Guides go under `docs/`.
- Use the scripts in `scripts/` for quality checks (docs coverage,
  static analysis).

## Questions

Open an issue for design questions before building large features.
