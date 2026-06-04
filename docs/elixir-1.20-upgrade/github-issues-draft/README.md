# Draft GitHub issues for Elixir 1.20 gradual types (do not publish)

Internal drafts from GridCodec’s Elixir 1.20 / OTP 29 upgrade. **Not submitted** to [elixir-lang/elixir](https://github.com/elixir-lang/elixir) or the forum.

## Context for reviewers

**GridCodec** is a private (not yet open source) library that generates high-performance binary codecs at compile time—similar in spirit to how **Phoenix** generators, **Ash** resources, **Ecto** schema macros, or **Credo** analysis emit modules users never hand-write. We compile ~70 library modules plus dozens of generated codec modules in an example app.

Full internal inventory: [`../warnings-registry.md`](../warnings-registry.md).

## Draft issues (candidates to file)

| File | Topic | Kind |
|------|--------|------|
| [02-generated-modules-dynamic-unused-clauses.md](02-generated-modules-dynamic-unused-clauses.md) | Unused `defp` clauses on helpers called only from generated code | Inference / `dynamic()` |
| [03-dead-function-warnings-emitted-api-surface.md](03-dead-function-warnings-emitted-api-surface.md) | “Function never used” on intentionally emitted helpers | Severity / categorization |
| [04-generated-code-diagnostic-locations.md](04-generated-code-diagnostic-locations.md) | Warnings anchored at `defmodule` line 1 | UX |
| [05-positive-unreachable-case-clauses.md](05-positive-unreachable-case-clauses.md) | Success story: unreachable `case` clauses | Feedback (not a bug) |

## Not filing (internal notes only)

| File | Reason |
|------|--------|
| [01-nil-as-atom-redundant-clauses.md](01-nil-as-atom-redundant-clauses.md) | **Withdrawn** — checker is often correct (`nil` === `:nil`, macro clause order); hard to frame as a clear upstream bug. Kept for our own nil/AST notes. |

## Before publishing

- [ ] Use **Elixir 1.20.x** (see repo `.tool-versions`). Warnings are from the compiler’s type pass; older Elixir will not reproduce them.
- [ ] Run each `mix new` reproduction; compare with [`../warnings-registry.md`](../warnings-registry.md) and `_repro_build/` logs where present.
- [ ] Confirm warning text matches current 1.20.0
- [ ] Remove or anonymize “GridCodec” if you prefer purely generic examples
- [ ] Search [elixir-lang/elixir issues](https://github.com/elixir-lang/elixir/issues) to avoid duplicates
- [ ] Choose GitHub issue vs. [Elixir Forum](https://elixirforum.com/c/elixir-news/28) per team preference (positive feedback in [05](05-positive-unreachable-case-clauses.md) may fit a release thread)

## Observed in our upgrade (internal)

| Issue draft | Confirmed in GridCodec compile logs |
|-------------|-------------------------------------|
| 01 nil/atom | Observed — not filing (see withdrawn draft) |
| 02 generated unused clause | Yes — 21 codecs; see [investigation-21-errors-warnings.md](../investigation-21-errors-warnings.md) |
| 03 dead defp API surface | Yes — ~10 `encode_map/1` warnings |
| 04 diagnostic locations | Yes — warnings at `defmodule` line 1 |
| 05 unreachable case | Yes — var-only decoder template (fixed) |
