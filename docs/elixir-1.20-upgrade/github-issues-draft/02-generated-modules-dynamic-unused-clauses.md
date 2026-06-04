# Draft: “Clause never used” on multi-head helpers called from macro-generated modules

**Target:** [elixir-lang/elixir](https://github.com/elixir-lang/elixir)  
**Labels (suggested):** `types`, `gradual types`, `macros`, `diagnostics`  
**Status:** Draft — not filed

---

## Thank you

Thank you for the 1.20 type-inference milestone and for being upfront about expected false positives during rollout. Macro-heavy libraries are a core Elixir strength; better tooling for **generated modules** will help the whole ecosystem (Phoenix, Ash, Ecto-adjacent generators, Credo, etc.). This issue is about one false-positive pattern we see at scale.

## Context

We maintain a **private** compile-time codec generator (not open source yet). Each consumer `use MyGenerator` expands to a module with shared helpers, e.g. normalizing validation results:

```elixir
defp collect_errors(:ok), do: []
defp collect_errors({:ok, _value}), do: []
defp collect_errors({:error, %Errors{}} = err), do: flatten(err)
defp collect_errors({:error, reason}), do: [reason]
```

Call sites combine:

- `validate_binary/1` → `:ok | {:error, _}`
- `validate_struct/1` → `{:ok, _} | {:error, _}`

At runtime **all heads are used**. On 1.20 we get ~20× warnings per app that **`defp collect_errors({:ok, _})` is never used** (sometimes reported against the whole `defmodule` line).

**Similar open-source patterns:** Phoenix context stubs, Ash action validators, any generator that emits a uniform validation pipeline across dozens of modules.

## Reproduction

`mix new generated_unused_clause_repro && cd generated_unused_clause_repro`

**`lib/generator.ex`**

```elixir
defmodule GeneratedUnusedClauseRepro.Generator do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      def validate_all(data) do
        errors =
          collect_errors(validate_binary(data)) ++
            collect_errors(validate_struct(data))

        if errors == [], do: :ok, else: {:error, errors}
      end

      defp collect_errors(:ok), do: []

      defp collect_errors({:ok, _value}), do: []

      defp collect_errors({:error, reason}) when is_list(reason), do: reason
      defp collect_errors({:error, reason}), do: [reason]

      # Simulated generated validators with different result shapes
      defp validate_binary(_data), do: :ok

      defp validate_struct(_data), do: {:ok, %{}}
    end
  end
end
```

**`lib/consumer_codec.ex`**

```elixir
defmodule GeneratedUnusedClauseRepro.ConsumerCodec do
  @moduledoc false
  use GeneratedUnusedClauseRepro.Generator
end
```

Compile:

```bash
mix compile
```

**Expected:** No warning: `validate_struct/1` returns `{:ok, %{}`, which must match `collect_errors({:ok, _})`.

**Observed (reported on 1.20.0):** Warning that a clause of `collect_errors/1` is never used (often the `{:ok, _}` head), with location pointing at the generated `defmodule` line.

Try adding a second consumer module to mimic an umbrella—warnings multiplied per generated codec in our app.

## Hypothesis

- Cross-function inference stops at `dynamic()` boundaries inside `quote` / generated AST.
- Or union narrowing on `validate_binary` ⊕ `validate_struct` results does not reach the `collect_errors/1` heads.

## Impact

- **Signal-to-noise:** Real issues (we found unreachable `case` clauses—thank you!) drown in per-module false positives.
- **CI:** Teams using `--warnings-as-errors` on generated apps will need per-app suppressions.

## Suggested improvements

1. **Module generation attribute** (idea): `@gradual_type_boundary dynamic()` on macro-emitted modules to suppress “unused clause” unless a head is provably unreachable.
2. **Better inter-procedural inference** for simple pipelines: if `f/0` returns `:ok` and `g/0` returns `{:ok, term()}`, a function `h(:ok | {:ok, _} | {:error, _})` should not mark `{:ok, _}` unused when both are called in the same module.
3. **Diagnostic quality:** Attribute warning to the **macro call site** (`use Generator` in `consumer_codec.ex`) or the generator template line, not `defmodule` line 1.
4. **Severity:** “Unreachable clause” (provably dead) vs “not inferred as used” (uncertain) as different warning kinds.

## Workaround

Merge success heads:

```elixir
defp collect_errors(result) when result == :ok or (is_tuple(result) and elem(result, 0) == :ok),
  do: []
```

Less clear for readers; we prefer separate heads.

## Offer

Happy to test patches, provide more minimal reproducers, or compare behavior on `main` nightlies.

Thank you for the work on gradual types—we want this to succeed for codegen-heavy Elixir.
