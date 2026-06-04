# Draft: “defp never used” on helpers emitted for API uniformity in generated modules

**Target:** [elixir-lang/elixir](https://github.com/elixir-lang/elixir)  
**Labels (suggested):** `types`, `gradual types`, `diagnostics`  
**Status:** Draft — not filed

---

## Thank you

We are grateful for compile-time dead-code detection in 1.20—it found real unreachable clauses in our decoder templates. This report is a **UX / categorization** request about a class of warnings that is *technically correct* but noisy for **code generators** that emit a full API surface per module.

## Context

Our generator (private codec library, not yet OSS) emits both:

- `encode_payload/1` — fast struct-specific path (used)
- `encode_map/1` — map-based fallback (emitted for every codec, **not always called**)

Roughly **10 warnings per app** like: *“this clause of defp encode_map/1 is never used”* on modules that legitimately use only the fast path.

**Open-source analogues:**

- Phoenix generators emitting helper functions not every controller uses
- Test/support fixtures in large apps
- Optional callbacks implemented as `defp` for uniformity

The checker is **right** that `encode_map/1` is uncalled; the issue is whether that should be the **same severity** as a dead clause in hand-written library code.

## Reproduction

`mix new dead_defp_repro && cd dead_defp_repro`

```elixir
defmodule DeadDefpRepro.Codec do
  @moduledoc """
  Simulates a generated codec: fast path only, but fallback defp still emitted.
  """

  def encode(%{id: id} = struct) when is_integer(id) do
    encode_payload(struct)
  end

  # Emitted by generator for all codecs; only some call it (e.g. map-based encode path)
  defp encode_map(data) when is_map(data) do
    <<>>
  end

  defp encode_payload(%{id: id}) do
    <<id::64>>
  end
end
```

```bash
mix compile
```

**Observed:** Warning that `encode_map/1` (or a clause thereof) is never used.

**Runtime:** Correct—no bug. Uniform codegen template.

## What would help

1. **Warning category** e.g. `unused_function` with subkind:
   - `:reachable_module_unused` (dead code — current behavior, keep)
   - `:private_helper` — downgrade to note/hint when function is `defp` and never referenced **in-module** (optional opt-in strict mode)

2. **Generator attribute** (strawman):

   ```elixir
   @compile {:gradual_types, unused_defp: :ignore}
   ```

   for macro-generated files (similar spirit to `@compile {:no_warn_undefined, ...}`).

3. **Documentation** for library authors: recommended pattern to `unless function_exported?` / conditional emission vs accepting warnings.

## Not asking to remove the check

We **want** unused `defp` detection for hand-written `lib/`. We only ask for a way to reduce false churn when **intentionally** emitting parallel code paths from templates—common in Elixir metaprogramming.

## Our plan

Until then: conditionally omit `encode_map/1` from fast-path-only codecs in our generator (reduces noise, slightly divergent templates).

Thanks again for shipping inference in 1.20 with manageable compile times on a large codebase.
