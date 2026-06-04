# Draft (positive feedback): Unreachable `case` clause detection caught real decoder bugs

**Target:** [elixir-lang/elixir](https://github.com/elixir-lang/elixir)  
**Labels (suggested):** `types`, `gradual types`, `feedback`  
**Status:** Draft — optional “success story” comment on a release thread or blog post, not necessarily a standalone issue

---

## Thank you

We want to balance our other reports with explicit praise: **unreachable `case` clause** warnings in 1.20 were among the highest-value diagnostics we have ever gotten from the Elixir compiler—on par with the new bitstring pin requirements for `size/1` in patterns.

## Context

We maintain a **private** compile-time binary codec generator (GridCodec—not open source yet). It emits `decode/1` bodies via templates. One pattern for **var-data-only** codecs (no fixed binary header) looked like:

```elixir
case binary do
  <<rest::binary>> ->
  {:ok, decode_var_fields(rest)}

  _ ->
    {:error, :invalid_binary}
end
```

## What 1.20 reported

**Type warning:** the `_` clause cannot match because `<<rest::binary>>` already covers all `binary()`.

That is **correct**. The error branch was dead code—never observable at runtime.

## Impact

- Fixed in our **compiler template** (`decoder_match_body_ast/2`), fixing every consumer codec (dozens of modules) in one place.
- An **example-app fixture** (`RequiredInlineStringWrapperFixture`—var-length string fields only) was the canary.

**Comparable benefit:** Any library generating decoders (protocol parsers, TLV readers, similar to protobuf-style codegen) could ship the same bug to many modules unnoticed until 1.20.

## Reproduction (minimal)

`mix new unreachable_case_repro && cd unreachable_case_repro`

```elixir
defmodule UnreachableCaseRepro do
  def decode(binary) when is_binary(binary) do
    case binary do
      <<rest::binary>> ->
        {:ok, byte_size(rest)}

      _ ->
        {:error, :invalid_binary}
    end
  end
end
```

```bash
mix compile
```

We expect a type warning on the `_` clause (exact message may vary by 1.20 patch).

## Suggested fix pattern (for others reading)

When there is no fixed prefix to match, bind rest without a catch-all:

```elixir
<<rest::binary>> = binary
{:ok, decode_var_fields(rest)}
```

## Performance note (for the team)

Full clean compile of our library + example app was **unchanged** within measurement noise (~17s / ~26s) after upgrading to 1.20.0 / OTP 29. Thank you for prioritizing performance in the rollout blog post—that matched our experience.

## No action requested

This is encouragement to keep unreachable-clause detection as a first-class diagnostic. It found bugs our tests did not assert for explicitly.

With gratitude from a macro-heavy Elixir codebase.
