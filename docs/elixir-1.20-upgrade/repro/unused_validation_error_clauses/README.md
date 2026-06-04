# Repro: unused clause on validation error normalizer (Elixir 1.20)

Minimal **hand-written** repro for upstream. Mirrors GridCodec’s generated pattern without macros.

## Expected

`mix compile` reports **two** warnings on the **`{:error, _}`** heads of `__errors_from_validation_result__/1` (see `lib/codec.ex` around lines 18 and 23), not on `:ok` or `{:ok, _}`.

You may also see warnings on `__validation_error_result__/1` error heads (collector is always `[]`); same inference pattern.

## Run

```bash
cd docs/elixir-1.20-upgrade/repro/unused_validation_error_clauses
mix compile
```

Requires Elixir 1.20+ (see repo `.tool-versions`).

## Why this matches GridCodec

- `validate_struct/1` → only `{:ok, struct}` (no `validations do` → `validation_active: false` in GridCodec).
- `__collect_binary_validation_errors__/2` → always `[]`.
- Checker infers call sites only pass success shapes into the shared normalizer; error heads warn.

At **runtime**, `validate_binary/2` can still return `{:error, :invalid_binary}` etc.; the warning is an inference false positive.

## Counterexample

Uncomment the `validations`-style `validate_struct/1` in `lib/codec.ex` (see file bottom). Recompile → warnings should disappear.
