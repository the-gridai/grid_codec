# Investigation: 21 `__errors_from_validation_result__/1` warnings

**Toolchain:** Elixir 1.20.0 / OTP 29 (see repo `.tool-versions`)  
**Verified:** 2026-06-04 via `example_app` compile + BEAM `abstract_code` + hand repro

## Summary

All **21** warnings were caused by **GridCodec emitting dead code**, not by a type-checker bug.

`__errors_from_validation_result__/1` is only called from `decode(validate: :both)`. On codecs **without** `validations do` / `validation_active`:

- `validate_struct/1` is always `{:ok, struct}`.
- Post-decode `validate_binary/2` on the same bytes that just decoded cannot fail (empty binary collector, header already validated).

So the error normalizer’s `{:error, _}` heads were **genuinely unreachable** on the only in-module call path. Elixir 1.20 was right to warn.

**Fix (in `GridCodec.Struct.Compiler`):**

1. Emit `__errors_from_validation_result__/1` only when `validation_active`; treat `decode(validate: :both)` like `:binary` when there are no struct validators.
2. Emit `__validation_error_result__/1` non-empty-list heads only when `validation_active`.
3. Skip `encode_map/1` when struct fast-path encoder is used; `new_binary/1` from maps uses `struct/2` + `encode_payload/1` instead.

`ExampleApp.Views.Reservation` (has `validations do`) keeps the full `:both` path and had no `__errors` warning.

## Affected modules (21)

From `mix compile --force` in `example_app`:

| Module | `validations do`? | `validate_struct` AST | `__errors` warning |
|--------|-------------------|----------------------|-------------------|
| All event/bench/view codecs except Reservation | No | Always `{:ok, struct}` | Yes |
| `ExampleApp.Views.Reservation` | **Yes** | `case __validate__(struct)` with error branch | **No** (only `encode_map/1`) |
| `ReleaseReservation`, `PlaceReservation` | No | Always `{:ok, struct}` | Yes |

Full list: run `grep '__errors_from_validation_result__' /tmp/gc_errors_warnings.log` after compile.

**22** codecs export `__errors_from_validation_result__/1` (registry count); **21** get this warning.

## Generated code pattern

From `GridCodec.Struct.Compiler.generate_validation_helpers/8`:

1. **Always emitted** (not gated on `validation_active`) for every `use GridCodec.Struct`.
2. **`validate_struct/1`** when `validation_active == false` (default: no `validations do`, `validate: false` app default):

   ```elixir
   def validate_struct(%Module{} = struct), do: {:ok, struct}
   ```

3. **`__collect_binary_validation_errors__/2`** when `binary_checks == []` (no binary-capable validators):

   ```elixir
   defp __collect_binary_validation_errors__(_binary, _header?), do: []
   ```

4. **`validate_binary/2`** then does `with … :ok <- __validation_error_result__([])` → success path is **always `:ok`** from the collector; errors still possible from `__prepare_validation_binary__/2` and the catch-all `validate_binary(_, _)`.

5. **Normalizer** (four heads):

   ```elixir
   defp __errors_from_validation_result__(:ok), do: []
   defp __errors_from_validation_result__({:ok, _value}), do: []
   defp __errors_from_validation_result__({:error, %GridCodec.ValidationErrors{errors: errors}}), do: errors
   defp __errors_from_validation_result__({:error, error}), do: [error]
   ```

6. **Call sites** (only when decode uses `validate: :both` and validation is active in decode path)—see `compiler.ex` ~4658:

   ```elixir
   __errors_from_validation_result__(validate_binary(binary, …))
   ++ __errors_from_validation_result__(validate_struct(struct))
   ```

## Root cause (verified)

| Call site | Inferred input to normalizer (21 codecs) | Heads used |
|-----------|------------------------------------------|------------|
| `validate_struct(struct)` | Only `{:ok, struct}` | `{:ok, _}` |
| `validate_binary(…)` | Inferred **`:ok` only** when collector is always `[]` | `:ok` |

Union across call sites still leaves **both error heads** with no matching inferred input → **“clause never used”** on the `{:error, _}` heads.

**Counterexample:** `Reservation` has `validations do` → `validation_active: true` → `validate_struct` includes `{:error, error}` → error heads reachable from struct site → **no** `__errors` warning.

**Hand repro (line-accurate):** see `repro/unused_validation_error_clauses/` — two warnings on lines 8–9 (error heads), zero on success heads.

## What is *not* the cause

| Hypothesis | Verdict |
|------------|---------|
| Unused `{:ok, _}` head | **False** — hand repro flags **error** lines 8–9 |
| Macro / `dynamic()` in `quote` | **Unproven** — identical hand-written module warns the same way |
| Per-module random false positive | **False** — 100% correlated with `validate_struct` = always ok + empty binary collector |

## Diagnostic quirk

In `example_app`, warnings point at **`defmodule` line 1** because generated clauses use `location: 0`. Hand-written repros show the real lines (error heads). Related: draft issue **04** (diagnostic locations).

## GridCodec mitigations (internal)

1. **Emit `generate_validation_helpers` only when `validation_active`** (or when decode can call the normalizer)—removes dead API surface on simple codecs.
2. **Or** accept noise until Elixir improves cross-function union for multi-call-site normalizers.
3. **Workaround** (noisy): merge error heads; not recommended for readability.

## Upstream repro

Standalone Mix project: [`repro/unused_validation_error_clauses/`](repro/unused_validation_error_clauses/README.md)

Suggested Elixir issue title: *Unused clause warning on error heads of shared normalizer when call sites only infer success shapes*

## Analysis tooling

```bash
cd example_app
mix compile --force 2>&1 | tee /tmp/gc_errors_warnings.log
mix run --no-compile ../docs/elixir-1.20-upgrade/scripts/analyze_validation_warnings.exs
```

`analyze_validation_warnings.exs` reads BEAM `abstract_code` for all `ExampleApp.*` codecs and prints `struct_always_ok`, `struct_err_branch`, etc.
