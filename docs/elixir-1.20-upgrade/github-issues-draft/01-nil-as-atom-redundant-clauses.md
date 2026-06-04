# Draft: `nil` as subtype of `atom()` produces misleading “redundant clause” warnings

**Target:** [elixir-lang/elixir](https://github.com/elixir-lang/elixir)  
**Labels (suggested):** `types`, `gradual types`, `diagnostics`  
**Status:** **Withdrawn — do not publish.** Internal notes only. The checker is often right; we did not find a crisp upstream bug report after review.

---

## Thank you

First, thank you to everyone who worked on set-theoretic gradual types in 1.20. Inference without mandatory annotations is exactly what large existing codebases need. We upgraded a compile-time code generator (binary codecs) and got **real, actionable warnings** (bitstring pins, unreachable `case` clauses) with **no compile-time regression**. This report focuses on diagnostics around **`nil` ⊆ `atom()`** where the type algebra is correct but the message can mislead developers who write **reasonable, idiomatic** code.

## Environment

- Elixir 1.20.0, OTP 29.0.1 (verified 2026-06-04)

## Summary

In set-theoretic types, **`nil` is an atom** (`nil === :nil` is `true`). That produces **redundant-clause** warnings on code people write on purpose—either because they confuse `nil` with `:nil`, or because they pattern-match **Macro AST** tuples where the third field is the literal `nil` *value* meaning “no context”, not “the atom nil” as a domain concept.

We are **not** asking to change the algebra; we ask for clearer diagnostics when redundancy is only due to `nil <: atom()`, and when tuple positions carry meaning beyond their type.

---

## Background: `nil` and `:nil` are the same value

```elixir
iex> nil === :nil
true
```

Many developers (and JSON APIs) treat “null” and the string `"nil"` as different. In Elixir source, **`def f(nil)` and `def f(:nil)` match the same runtime value.** Separate function heads for both look intentional but are redundant—a good teaching moment for the type system, but the warning text should say that explicitly.

---

## Background: the AST “third element is `nil`” (variable context, not the atom nil)

Elixir represents **variables in quoted AST** as 3-tuples `{name, metadata, context}` (see [`Macro.var/2`](https://hexdocs.pm/elixir/Macro.html#var/2) and [`Macro.decompose_call/1`](https://hexdocs.pm/elixir/Macro.html#decompose_call/1)).

| Form | Typical AST shape | Meaning of 3rd element |
|------|-------------------|-------------------------|
| `Macro.var(:age, nil)` | `{:age, [], nil}` | **`nil` = no context** (local variable in macro sense) |
| `quote(do: age)` in a module | `{:age, [], Elixir}` | **atom** = expansion context module |
| `quote(do: Other.age)` | `{{:., ...}, [], []}` | call/tuple form, not this 3-tuple |

So when macro code does:

```elixir
{name, _meta, nil}   # matches Macro.var(:name, nil)
```

the **`nil` in the tuple is the value `nil`**, used as a **sentinel for “no context”** in Macro’s API. It is **not** “match any atom” and it is **not** the same thing as writing `def handle(:nil)` for the atom `:nil`—but the **type** of that position is still `nil`, which is an `atom()`, so the checker conflates it with `context` being any atom.

**Where this shows up:** DSLs and macros (Credo, Phoenix, our private codec generator’s `invariant/2` macro) that walk `quote`d expressions and normalize field references like `age > start_date` into validation calls.

---

## Reproduction 1 — idiomatic `nil` then `:nil` function heads (user-facing)

This is normal-looking code you might write when handling API/config values:

`mix new nil_nil_atom && cd nil_nil_atom`

**`lib/nil_nil_atom/label.ex`**

```elixir
defmodule NilNilAtom.Label do
  @moduledoc """
  Handle "missing", the atom :nil, and other atoms separately.
  Many developers do not realize nil and :nil are the same value in Elixir.
  """

  def describe(nil), do: "missing"
  def describe(:nil), do: "the atom :nil"
  def describe(atom) when is_atom(atom), do: "other atom: #{atom}"
  def describe(other), do: "not an atom: #{inspect(other)}"
end
```

```bash
mix compile
```

**Actual output (Elixir 1.20.0, OTP 29.0.1):**

```text
Compiling 1 file (.ex)
    warning: this clause cannot match because a previous clause at line 8 matches the same pattern as this clause
    │
  9 │   def describe(:nil), do: "the atom :nil"
    │       ~
    │
    └─ lib/nil_nil_atom/label.ex:9:7

    warning: the following clause is redundant:

        def describe(nil)

    it has type:

        nil

    previous clauses have already matched on the following types:

        nil

    │
  9 │   def describe(:nil), do: "the atom :nil"
    │       ~
    │
    └─ lib/nil_nil_atom/label.ex:9:7: NilNilAtom.Label.describe/1

Generated nil_nil_atom app
```

**Why this matters:** The code **looks** like good, explicit handling. The checker is **mathematically right** (second head is dead). The diagnostic should prominently say **`nil` and `:nil` are the same atom in Elixir** so developers learn something instead of thinking the compiler is broken.

**Idiomatic fix:** Keep a single `nil` clause (or one `describe(v) when v == nil or v == :nil`).

### Suggested improvement

When redundancy is because `nil` and `:nil` unify, emit something like:

> Both patterns match the same value: in Elixir, `nil` is the atom `:nil`. The clause on line N is unreachable.

---

## Reproduction 2 — macro AST normalization (clause order)

Macro authors often classify AST nodes with **multiple heads**. A **mistake** we made (and the type system caught) is testing **`is_atom(context)` before matching `nil` in the tuple**:

**`lib/ast_macro_repro.ex`**

```elixir
defmodule AstMacroRepro do
  @moduledoc """
  Simplified from macro code that normalizes field references in invariant expressions.
  See "Background" above for what the third tuple element means.
  """

  # WRONG ORDER for Macro AST: is_atom(context) matches when context is nil
  def ref_kind({name, _meta, context}) when is_atom(name) and is_atom(context) do
    {:with_context, name, context}
  end

  def ref_kind({name, _meta, nil}) when is_atom(name) do
    {:local_var, name}
  end

  def ref_kind(other), do: {:other, other}
end
```

Use a `case` with the same order (equivalent warning):

```elixir
def normalize_ref(ast) do
  case ast do
    {name, _meta, context} when is_atom(name) and is_atom(context) ->
      {:with_context, name, context}

    {name, _meta, nil} when is_atom(name) ->
      {:local_var, name}

    other ->
      {:other, other}
  end
end
```

```bash
mix compile
```

**Actual output (`case` form, same module logic):**

```text
    warning: the following clause is redundant:

        {name, _meta, nil} when is_atom(name) ->

    previous clauses have already matched on the following types:

        {atom(), term(), atom()}

    where "name" was given the types:

        # type: dynamic(atom())
        # from: lib/nil_atom_repro_1.ex:5:7
        {name, _meta, nil}

        # type: atom()
        # from: lib/nil_atom_repro_1.ex:5:31
        is_atom(name)

    type warning found at:
    │
  5 │       {name, _meta, nil} when is_atom(name) -> name
    │                                             ~
    │
    └─ lib/nil_atom_repro_1.ex:5:45: NilAtomRepro1.normalize_ref/1
```

**Runtime truth:** For `Macro.var(:x, nil)` → `{:x, [], nil}`, the **first** clause binds `context = nil`, `is_atom(nil)` is true, so the **second** clause never runs. The warning is **correct for control flow** but **misleading for meaning**: we wanted the second clause for “local variable with nil context”, not “any atom context including nil”.

**Good macro style (no warning on 1.20.0):** match `nil` in the tuple **first**, then other atoms:

```elixir
def ref_kind({name, _meta, nil}) when is_atom(name), do: {:local_var, name}

def ref_kind({name, _meta, context}) when is_atom(name) and is_atom(context),
  do: {:with_context, name, context}
```

Verified: this order compiles **without** warnings.

**What we did in production:** merged into one clause with `(is_atom(context) or context == nil)` in our private codec’s `invariant/2` macro—works, but two clauses with a note would be clearer for macro maintainers.

### Suggested improvements

1. When redundancy involves a tuple element pinned to `nil` vs `is_atom` on the same position, hint: *“Third element is the literal `nil` (e.g. `Macro.var/2`); `is_atom(nil)` is true, so an earlier clause may already match. Match `nil` in the tuple before `is_atom(context)`.”*
2. Link to Macro docs for `{name, meta, context}` variable representation.

---

## What we deliberately removed from this report

An earlier draft used a **`cond` with `value == nil` followed by `is_atom(value) and not is_nil(value)`**. That order is **not idiomatic** (good code uses `is_nil/1` first, then `is_atom/1` without `not is_nil/1`, which compiles cleanly on 1.20.0). We dropped it so this issue only cites patterns developers actually write.

Our codegen had that shape internally; we fixed it. We mention it only so reviewers do not ask us to resurrect it as a reproduction.

---

## Why this matters for codegen / macro ecosystems

- **Phoenix / Ash / Credo-style macros** walk AST and match `{_, _, nil}` regularly.
- Warnings that say “remove the nil clause” without Macro context will get “fixed” in generators and **hurt readability** for security reviewers and library maintainers.
- **`nil` / `:nil` function heads** confuse anyone coming from JSON/null semantics—the type system can teach that, if the message is explicit.

## Workarounds today

- Put **`{_, _, nil}` before `is_atom(context)`** in macro matchers.
- Do not define separate heads for `nil` and `:nil` unless documented as intentional.
- Merge clauses with `(is_atom(context) or context == nil)` only when you accept less clarity.

## Happy to help

We can provide minimal projects under `_repro_build/` in our internal docs, test on nightlies, or pair with the team on wording for macro-heavy false positives.

Thank you again for shipping gradual types in 1.20.
