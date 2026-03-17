---
name: architecture-review
description: Review GridCodec architecture, evaluate design decisions, audit code generation quality, and assess the compile-time/runtime boundary. Use when reviewing the compiler, evaluating type system design, assessing API surface, or planning structural changes.
---

# Architecture Review for GridCodec

## System Overview

GridCodec is a compile-time code generation library. The key architectural boundary:

```
Compile time (macros)          Runtime (generated code)
─────────────────────          ──────────────────────
Type.encode_ast/4         →    inline binary construction
Type.decode_pattern_ast/2 →    binary pattern match
Type.validate_ast/3       →    case + raise
Compiler.__before_compile__→   encode/1, decode/1, new/1, get/2
```

Everything in `lib/grid_codec/struct/compiler.ex` runs at compile time and produces AST that becomes runtime code. Changes here affect every codec module.

## Review Dimensions

### 1. Compile-Time vs Runtime Boundary

**Ask:** Is this work happening at the right time?

| Should be compile-time | Should be runtime |
|------------------------|-------------------|
| Field offsets, block_length | Entry iteration |
| Binary segment specs | Map/struct construction |
| Type validation guards | Actual validation checks |
| Function clause generation | Function execution |
| Enum atom↔int case clauses | MapSet operations (bitset) |

**Red flags:**
- `Application.get_env` at runtime for something knowable at compile time
- Runtime `case` on a value that's constant per codec (use module attribute)
- `Code.ensure_compiled?` affecting module definition (fails across dep compilation)

### 2. Generated Code Quality

**Audit by inspecting generated code:**
```elixir
# See what the compiler generates:
MyCodec.__info__(:functions)
# Decompile a specific function:
:code.get_object_code(MyCodec) |> elem(2) |> :beam_disasm.file()
```

**Or simpler — macro expansion:**
```elixir
quote do
  use GridCodec.Struct, template_id: 1, schema_id: 1
  defcodec do
    field :id, :u64
  end
end
|> Macro.expand(__ENV__)
|> Macro.to_string()
|> IO.puts()
```

**Check for:**
- [ ] No intermediate allocations in the hot path (tuples, lists, binaries that are immediately consumed)
- [ ] No dynamic dispatch where static dispatch is possible
- [ ] No IIFE patterns `(fn -> ... end).()`
- [ ] Binary segments use direct integer specs, not `binary-size(N)` re-parse
- [ ] Group entry codecs are direct local function calls (JIT-inlineable)

### 3. API Surface Consistency

Every codec struct should have the same public API:

| Function | Purpose | Always present? |
|----------|---------|-----------------|
| `encode/1,2` | Struct → binary | Yes |
| `decode/1,2` | Binary → {:ok, struct} | Yes |
| `new/1` | Validated constructor | Yes |
| `get/2` (macro) | Zero-copy field access | Yes |
| `__schema__/0` | Introspection | Yes |
| `__type__/0` | Stable type name | Yes |
| `__fields__/0` | Field names | Yes |
| `block_length/0` | Fixed block size | Yes |

### 4. Type System Extensibility

Custom types must implement `GridCodec.Type` and work identically to built-ins:
- In top-level fields
- Inside `group do` blocks (alias expansion)
- With `validate: true` (if `validate_ast/3` is implemented)
- In property tests (if `generator/0` is implemented)
- With getter macro (if `getter_ast/3` is implemented)

**Test custom type parity by defining a test codec with the custom type in both top-level and group positions.**

### 5. Compiler Complexity

`__before_compile__` in `compiler.ex` is the most complex function. Track cyclomatic complexity — credo warns at 50. When it grows:
- Extract into named helper functions (like `generate_encode_api`, `generate_validate_fn`)
- Each helper should have a single responsibility
- Keep the `quote do ... end` block in `__before_compile__` as a thin assembly layer

### 6. Dependency Hygiene

GridCodec's runtime deps should be minimal:
- `:telemetry` — for instrumented encode/decode
- `:telemetry_metrics` — for `GridCodec.Telemetry.Metrics`
- `:decimal` — for Decimal type support

**Never add:**
- `:prom_ex` — consumer-side concern
- `:ecto` — consumer-side concern
- `:jason` — codec is binary, not JSON

Optional deps should use `Code.ensure_loaded?` at the RIGHT level (module body of the consuming app, not inside grid_codec's compilation).

### 7. Schema Evolution Layer

The `.grid` schema format and breaking change detection form a separate layer:

```
defcodec (Elixir macros)  →  __schema__/0 (runtime metadata)
                                    ↓
                           mix grid_codec.export (--syntax N)
                                    ↓
                           .grid files (@syntax 1, self-contained,
                                        cross-schema imports)
                                    ↓
                           mix grid_codec.breaking
                                    ↓
                           WIRE (22) + SOURCE (8) issues
```

**Key modules:**
- `lib/grid_codec/schema/parser.ex` — tokenizer + recursive descent parser for `.grid`; `@syntax N` validation; `current_syntax/0`; formal spec in `@moduledoc`
- `lib/grid_codec/schema/formatter.ex` — `__schema__/0` → `.grid` string; `format/5`, `format_master/5`, `format_struct_file/3`, `format_enum_file/2` accept `opts` (`:syntax`, `:imports`); `current_syntax/0`; `detect_all_enums/1`, `referenced_enums/2` for cross-schema enum tracking
- `lib/grid_codec/breaking/` — differ, checker, rules (Wire 22 rules + Source 8 rules), config
- `lib/grid_codec/struct.ex` — `generate_from_struct_def` loads `.grid` → compiler; `types:` option for explicit type name mapping; `Registry.lookup_enum_by_name/1` auto-resolve fallback
- `lib/grid_codec/registry.ex` — `lookup_enum_by_name/1` resolves short enum names to modules

**Check for feature parity:** Every field option, type parameter, and structural element that exists in `defcodec` must also be expressible in `.grid` files. The parser `Field` struct mirrors the compiler's field opts: `type_params`, `wire_format`, `since`, `default`, `presence`, `value`.

**Check for `.grid` format compliance:**
- Files start with `@syntax N` (currently 1)
- Individual struct files import their enum dependencies (self-contained)
- Cross-schema enum references use relative import paths
- Parser rejects `@syntax` versions higher than `current_syntax()`

## Review Trigger Questions

When evaluating a change, ask:
1. Does this add runtime overhead to codecs that don't use the feature?
2. Can a consumer opt out? (compile-time flag, not runtime check)
3. Does it work in groups the same way as in top-level fields?
4. Is the error message actionable? (field name, type, actual value, module)
5. Would this break existing codecs on version upgrade?
6. Is the feature represented in `.grid` parser, formatter, and breaking rules?
7. After adding a new field option, did you regenerate `.grid` baselines?
8. Does the feature comply with the `.grid` format spec and `@syntax` versioning?
