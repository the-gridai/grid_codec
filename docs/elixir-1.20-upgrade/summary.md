# Elixir 1.20 / OTP 29 upgrade summary

**Date:** 2026-06-04

## Toolchain change (`.tool-versions`)

| | Before | After |
|---|--------|-------|
| Erlang | 28.3 | **29.0.1** |
| Elixir | 1.19.4-otp-28 | **1.20.0-otp-29** |

Elixir 1.20 requires OTP 27+; OTP 29 is the newest supported release.

> **Note:** If `mise` is active in your shell, it may not resolve `elixir@1.20.0-otp-29` until Erlang 29 is installed in mise as well. asdf installs under `~/.asdf/installs/` work with:
>
> ```bash
> export PATH="$HOME/.asdf/installs/erlang/29.0.1/bin:$HOME/.asdf/installs/elixir/1.20.0-otp-29/bin:$PATH"
> ```

## Clean compile times (`mix compile --force` after `rm -rf _build`)

Measured with `./scripts/benchmark_clean_compile.sh` (see `compile_times.tsv`).

| Project | Before (1.19.4 / OTP 28) | After (1.20.0 / OTP 29) |
|---------|--------------------------|-------------------------|
| `grid_codec` | 17s | 17s |
| `example_app` | 27s | 26s |

No meaningful regression in wall-clock clean compile for this repo.

## Gradual type system (inferred types at compile time)

Types are checked during `mix compile`; there is no separate typeset task.

**Deep dive:** see [`type-analysis.md`](type-analysis.md) for categories, fixes, and annotation guidance.

Initial `lib/` findings (41 warnings) were addressed:

- **37** bitstring `size()` pin requirements (`^offset`, etc.) — real match semantics
- **4** gradual-type / dead-code items in `grid_codec.ex`, `struct/compiler.ex`, `doc_example_values.ex`

After fixes, `mix compile --force` on asdf 1.20 reports **no warnings in `lib/grid_codec`** or **`example_app`** generated codecs. Log: `compile_asdf_only_after_fixes.log`.

Dependency code (e.g. `protobuf`) may still warn; that is upstream.

Compiler fixes for dead validation/`encode_map` codegen are documented in [`investigation-21-errors-warnings.md`](investigation-21-errors-warnings.md).

## Tests

After relaxing two compile-warning count assertions in `virtual_field_test.exs` (1.20 emits more warnings during failed compiles):

```bash
MIX_ENV=test mix test
# 1506/1506 passed (with 1 excluded, 2 skipped as before)
```

## Suggested follow-ups (optional)

- CI uses Elixir 1.20 / OTP 29 (`.github/workflows/ci.yml`); Credo pinned to `~> 1.7.18` for 1.20 sigil tokens
- Tighten `mix.exs` `elixir: "~> 1.20"` if the project standardizes on 1.20
- Review `lib/grid_codec.ex` redundant `invariant/2` clause if the type warning is actionable
