# Elixir 1.20 warning registry

**Toolchain:** asdf `elixir 1.20.0-otp-29` / OTP 29.0.1  
**Full logs:**

| Log | Scope |
|-----|--------|
| `grid_codec_warnings_full.log` | `mix compile` in repo root (`lib/grid_codec` only) |
| `example_app_warnings_full.log` | `cd example_app && mix compile --force` (includes deps) |

**Legend:** **Legit** = real issue or worthwhile codegen cleanup. **False positive** = type checker over-approximation; runtime behavior is correct. **Upstream** = dependency, not GridCodec.

---

## A. `lib/grid_codec` (hand-written library)

After the pin-operator / dead-clause / `encode_literal_for_pattern` fixes, **`lib/grid_codec` compiles with zero warnings** on 1.20.

### A1. Bitstring `size()` without pin (37 sites) — **Legit** — **Fixed**

Unpinned variables in `binary-size(offset)` inside a match. Fixed with `^offset` (and similar) across types, batch, group, compiler.

### A2. `GridCodec.invariant/2` — `nil` vs `atom()` — **False positive** (keep explicit nil handling)

**Symptom:** Redundant clause on `{name, _, nil}` because `nil` ∈ `atom()` in set-theoretic types.

**Runtime truth:** Invariant AST uses `{:var, meta, nil}` for variables and `{:_, meta, atom}` for other refs. The distinction is real; merging into one clause with `context == nil` is fine.

**Recommendation:** Keep `is_nil/1` or `context == nil` in source for human readers even when the checker thinks it is redundant. Do **not** drop the nil branch solely to silence the checker.

### A3. `encode_literal_for_pattern/4` — disjoint `not is_nil` — **Legit** — **Fixed**

**Symptom:** After `is_nil(value)`, `is_atom(value) and not is_nil(value)` was flagged as disjoint.

**Fix:** `is_nil` first, then `is_atom(value)` without `not is_nil`. Comment documents why order matters (nil is an atom).

### A4. Dead `parameterized_domain/2` heads (Decimal) — **Legit** — **Fixed**

Unreachable because outer `case domain` already handles those modules.

### A5. Dead `generate_lookup_filter_ast(_, [])` — **Legit** — **Fixed**

Empty filters handled in `generate_lookup_step_ast`; never called with `[]`.

### A6. `__collect_binary_validation_errors__` redundant `true`/`false` clauses — **Legit** — **Fixed**

Emitted `when false` catch-all plus specialized clauses; fixed by conditional codegen.

---

## B. Generated codecs (`example_app`, tests)

These come from **`GridCodec.Struct.Compiler`** output, not hand-written app code.

### B1. `decode_versioned_payload` — `header_block_length` pin — **Legit** — **Fixed**

Template used `binary-size(header_block_length)`; fixed to `^header_block_length` in compiler.

### B2. `decode_map` / `decode_payload` — unreachable `_` clause — **Legit** — **Fixed**

**Symptom (example):** `RequiredInlineStringWrapperFixture` — var-data-only codec, no fixed block.

```elixir
case binary do
  <<rest::binary>> -> ...   # matches all binary()
  _ -> {:error, :invalid_binary}  # unreachable
end
```

**Fix:** `decoder_match_body_ast/2` — omit `case` + error clause when `fixed_patterns == []`.

### B3. `__errors_from_validation_result__/1` — “clause never used” — **False positive** (error heads)

**Symptom:** 21 warnings on codecs (e.g. `OrderCreated`); **not** on `ExampleApp.Views.Reservation` (has `validations do`).

**Runtime truth:** Error heads handle `validate_binary/2` failures (`{:error, :invalid_binary}`, header prep, etc.). Success heads handle `:ok` and `{:ok, struct}`.

**Cause (verified):** `generate_validation_helpers` is emitted on every codec. When `validation_active` is false, `validate_struct/1` is only `{:ok, struct}` and `__collect_binary_validation_errors__/2` is always `[]`, so the checker infers **only success shapes** at both normalizer call sites → **both `{:error, _}` heads** warn (not `{:ok, _}`). Not macro-specific.

**Investigation:** [`investigation-21-errors-warnings.md`](investigation-21-errors-warnings.md)  
**Upstream repro:** [`repro/unused_validation_error_clauses/`](repro/unused_validation_error_clauses/README.md)

**Action:** **Fixed** in compiler — validation helpers gated on `validation_active`; `encode_map/1` omitted when struct fast-path encoder is used (`new_binary` uses `encode_payload/1`).

### B4. `encode_map/1` — “never used” — **Legit** (codegen noise)

**Symptom:** ~10 warnings on codecs using struct fast-path `encode_payload/1` (no `encode_map/1` call).

**Action:** Future compiler tweak — only emit `encode_map/1` when fallback/map path is required. Not a wire bug.

### B5. `RequiredInlineStringWrapperFixture` — **Legit** — addressed by B2

Fixture exists to test required-field decode warnings; type warning on dead `_` was a real compiler bug, not intentional test behavior.

---

## C. Dependencies (seen when compiling `example_app`)

Not GridCodec issues; listed so we do not chase them in this repo.

| Package | Examples | Verdict |
|---------|----------|---------|
| **protobuf** | struct update on `dynamic()`, bitstring pin in decoder | Upstream |
| **ecto_sql** | bitstring pin in postgres adapter | Upstream |
| **ex_doc**, **credo**, **ecto** | redundant clauses, unused requires | Upstream |
| **statistex**, **msgpax**, **benchee** | unused require | Upstream |
| **mix** | `xref: [exclude: ...]` deprecated in example_app `mix.exs` | **Legit** housekeeping (our `mix.exs`) |

---

## D. Counts (example_app compile, after B1–B2 fixes)

Re-run:

```bash
export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
cd example_app && rm -rf _build && mix compile --force 2>&1 | tee ../docs/elixir-1.20-upgrade/example_app_warnings_full.log
```

| Bucket | Approx. count | GridCodec action |
|--------|---------------|------------------|
| `lib/example_app` generated (B3–B4) | ~33 | Optional codegen polish |
| `lib/grid_codec` (compiler source) | 0 | Done |
| Dependencies | ~100+ | Ignore / upgrade deps separately |

---

## E. `nil` is an atom — design note

Elixir’s set-theoretic types treat **`nil` as `atom()`**. That collides with everyday mental models and with AST shapes where `nil` in the third tuple position means “variable”, not the atom `nil`.

**Practices we follow:**

1. **`is_nil(x)` before `is_atom(x)`** when both nil and other atoms matter (`encode_literal_for_pattern/4`).
2. **`context == nil` in patterns** when distinguishing `{:name, _, nil}` from `{:name, _, ctx}` when `ctx` is an atom (`invariant/2`).
3. **Prefer explicit comments** over deleting nil checks to satisfy the checker.

The checker is useful when it finds **unreachable catch-alls** (B2) or **missing pins** (A1); it is misleading when it asks to remove nil checks that document intent.
