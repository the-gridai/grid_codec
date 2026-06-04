# Draft: Type warnings on generated modules often point at `defmodule` line 1

**Target:** [elixir-lang/elixir](https://github.com/elixir-lang/elixir)  
**Labels (suggested):** `types`, `gradual types`, `diagnostics`, `macros`  
**Status:** Draft — not filed

---

## Thank you

The 1.20 type warnings have already helped us fix real issues in compiler templates. This is a small **diagnostics UX** request that would multiply in value across Phoenix-, Ash-, and custom-generator ecosystems.

## Problem

When a warning applies to **generated** `defp` code, the location is often reported as:

```text
└─ lib/my_app/events/order_created.ex:1: MyApp.Events.OrderCreated.some_helper/1
```

Line **1** is `defmodule`—not where the author can act. The fix belongs in the **generator** (or macro), not in the generated file consumers are not supposed to edit.

We saw this on ~20+ generated codec modules in an internal example app.

## Reproduction

Use the project from [02-generated-modules-dynamic-unused-clauses.md](02-generated-modules-dynamic-unused-clauses.md) (`GeneratedUnusedClauseRepro.ConsumerCodec`).

Compile and inspect warning locations—they typically anchor on the `defmodule` line inside `lib/consumer_codec.ex`, not on `lib/generator.ex` template lines.

A second example: any `mix phx.gen.*` output where a future type warning might reference `lib/my_app_web/controllers/foo_controller.ex:1` instead of the generator template.

## Suggested improvements

1. **Macro expansion stack** in type warnings (similar to compile errors): show `use MyGenerator` call site + template function in generator module.
2. **`generated: true` in diagnostic metadata** (machine-readable) for tooling/CI filters.
3. **Optional** `Code.put_diagnostic_file/line` hook for macro authors when emitting `quote` blocks (if feasible).

## Workaround

Filter warnings by file path in CI; maintain internal registry (we use `warnings-registry.md`).

## Priority

Lower than semantic false positives ([02](02-generated-modules-dynamic-unused-clauses.md)), but cheap wins for developer experience.

Thank you for considering macro-first ecosystems in type rollout.
