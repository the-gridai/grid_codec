# Elixir 1.20 gradual type analysis — GridCodec

**Verified toolchain (asdf-only compile):** `elixir 1.20.0-otp-29` / OTP 29.0.1 via `/usr/local/bin/elixir`  
**Logs:** `compile_asdf_only.log`, `example_app_warnings_full.log`  
**Registry:** [`warnings-registry.md`](warnings-registry.md) — every warning class, legit vs false positive

## Can we add type annotations today?

Elixir **1.20 infers types at compile time**; there is no new `@type` syntax for set-theoretic types yet. User-written **set-theoretic signatures** are planned for a later release (blog: typed structs ~1.21, function signatures ~1.22).

What exists today:

| Mechanism | Role on 1.20 |
|-----------|----------------|
| **Inferred gradual types** | Active during `mix compile`; emits `type warning` / disjoint-comparison / redundant-clause diagnostics |
| **`@spec` / `@type` (Erlang typespecs)** | Still supported for docs and Dialyzer; **not** what drives the new checker |
| **Dialyzer** | Separate success-typing analysis; keep running in CI |

**Recommendation:** Rely on compile-time gradual warnings for new signal; keep `@spec` for public API docs until set-theoretic annotations land. Do not expect adding `@spec` to silence 1.20 `type warning` lines.

## Warning categories (37 bitstring + 4 gradual in initial scan)

### 1. Bitstring `size()` must pin external variables (37 warnings) — **actionable**

**What the checker caught:** Patterns like:

```elixir
offset = elem(batch.frame_offsets, index)
<<_::binary-size(offset), ...>> = batch.binary
```

use a variable in `size/1` that was bound **outside** the match. Elixir 1.20 requires `^offset` so the match pins the value at match time (same rule as other match contexts).

**Risk if ignored:** Today a warning; future releases may treat this as an error. Semantically, unpinned sizes in matches are a common source of subtle bugs when the variable is rebound.

**Fix applied:** `binary-size(^offset)` (and `^frame_offset`, `^bl`, `^total_data`, `^prefix_len`, `^size`) across `lib/grid_codec/types/*`, batch modules, `group.ex`, and `struct/compiler.ex`.

**Follow-up:** Consider a small internal helper `GridCodec.Binary.skip/2` if we want one place to document the pin rule for runtime slicing.

### 2. Redundant `invariant/2` macro clause — **real hygiene + type-system false positive**

**Location:** `lib/grid_codec.ex` — `normalize_ref` in `invariant/2`.

**What happened:** Two clauses distinguished `{:name, _, nil}` (variable AST) vs `{:name, _, context}` when `context` is an atom. The gradual checker claimed the `nil` third-element clause was redundant because it merged `nil` into `atom()` (since `nil` is an atom in Elixir).

**Fix applied:** Single clause: `when is_atom(name) and (is_atom(context) or context == nil)`.

**Lesson:** Set-theoretic types treat `nil` as `atom()`; explicit `is_nil/1` or `context == nil` is still required in **runtime** guards even when the type algebra lumps them together.

### 3. Disjoint comparison in `encode_literal_for_pattern/4` — **actionable**

**Location:** `lib/grid_codec/struct/compiler.ex`.

**What happened:** After `value == nil`, `is_integer`, and boolean guards, the checker narrowed `value` so `is_atom(value) and not is_nil(value)` was redundant (`nil` is an atom; earlier branches already removed nil).

**Fix applied:**

- `is_nil(value)` instead of `value == nil`
- `value === true/false` for booleans
- `is_atom(value)` without `not is_nil(value)` (nil branch runs first)

**Lesson:** Compiler macro code that handles **AST literal shapes** should use guard-friendly tests (`is_nil`, `===`) so human and gradual-type narrowing align.

### 4. Dead `parameterized_domain/2` clauses — **real dead code**

**Location:** `lib/grid_codec/doc_example_values.ex`.

**What happened:** `Decimal` and `PositiveDecimal` are handled in the outer `case domain` **before** the `_` branch calls `parameterized_domain/2`. The two specific function heads were unreachable.

**Fix applied:** Removed duplicate heads; outer `case` remains the single source of truth.

### 5. Dead `generate_lookup_filter_ast(_entry_ast, [])` — **real dead code**

**Location:** `lib/grid_codec/struct/compiler.ex`.

**What happened:** Lookups with `filters: []` are compiled by `generate_lookup_step_ast/3` clauses that **never** call `generate_lookup_filter_ast/2`. The empty-list head was unreachable.

**Fix applied:** Removed the unused clause.

## What we are *not* changing yet

- **Dependency warnings** (e.g. `protobuf` struct updates with `dynamic()`): upstream; not GridCodec wire format.
- **Generated codec warnings in tests** (`header_block_length` pin in compiled test modules): emitted from the same compiler rules; can be addressed when we regenerate or adjust the compiler’s decode AST (separate pass).
- **Broad `@spec` additions**: low value until set-theoretic signatures exist; Dialyzer already covers much of the public API.

## Re-verify after fixes

```bash
export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
mix compile --force 2>&1 | tee docs/elixir-1.20-upgrade/compile_asdf_only_after_fixes.log
mix test
```

Expect **zero** `lib/grid_codec` gradual-type warnings and **zero** bitstring pin warnings in `lib/` (test-generated codecs may still warn until compiler templates are updated).

## mise vs asdf

Earlier benchmarks may have run while **mise shims** were first on `PATH`, before mise finished installing OTP 29. The authoritative recompile uses **asdf shims only**.

This repo adds `mise.toml` with `idiomatic_version_file_enable_tools = []` so mise does not consume `.tool-versions` for BEAM tools in this directory. Prefer:

```bash
export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
```

—or disable mise’s Elixir/Erllang in your global config if you standardize on asdf everywhere.
