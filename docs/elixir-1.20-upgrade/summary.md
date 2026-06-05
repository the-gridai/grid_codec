# Elixir 1.20 / OTP 29 upgrade summary

**Date:** 2026-06-04

## Toolchain change (`.tool-versions`)

| | Before | After |
|---|--------|-------|
| Erlang | 28.3 | **29.0.1** |
| Elixir | 1.19.4-otp-28 | **1.20.0-otp-29** |

Elixir 1.20 requires OTP 27+; OTP 29 is the newest supported release.

## Clean compile times

Wall-clock `mix compile --force` after `rm -rf _build` showed no meaningful regression (roughly 17s for `grid_codec`, 26–27s for `example_app`).

## Gradual type system (inferred types at compile time)

Types are checked during `mix compile`; there is no separate typeset task.

Initial `lib/` findings (41 warnings) were addressed:

- **37** bitstring `size()` pin requirements (`^offset`, etc.) — real match semantics
- **4** gradual-type / dead-code items in `grid_codec.ex`, `struct/compiler.ex`, `doc_example_values.ex`

After fixes, `mix compile --force` on Elixir 1.20 reports **no warnings in `lib/grid_codec`** or **`example_app`** generated codecs. Dependency code (e.g. `protobuf`) may still warn; that is upstream.

Compiler changes gate validation error helpers and dead `decode(validate: :both)` paths on `validation_active`, skip `encode_map/1` for fast-path encoders, and only wrap `get(..., copy: true)` when the field type opts in via `getter_returns_binary?/0`.

## Tests

After relaxing two compile-warning count assertions in `virtual_field_test.exs` (1.20 emits more warnings during failed compiles):

```bash
MIX_ENV=test mix test
# 1506/1506 passed (with 1 excluded, 2 skipped as before)
```

## CI

`.github/workflows/ci.yml` uses Elixir 1.20 / OTP 29. Credo is pinned to `~> 1.7.18` for 1.20 sigil token support.
