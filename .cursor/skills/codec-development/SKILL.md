---
name: codec-development
description: Develop GridCodec types, group features, compiler changes, and schema evolution. Use when adding types, modifying the compiler, working with groups, implementing GridCodec.Type callbacks, or extending the .grid schema format.
---

# GridCodec Development

## Adding a New Built-in Type

1. Create `lib/grid_codec/types/your_type.ex` implementing `@behaviour GridCodec.Type`
2. Required callbacks: `size/0`, `alignment/0`, `null_value/0`, `encode_ast/4`, `decode_pattern_ast/2`, `getter_ast/3`
3. Optional: `decode_value_ast/1`, `validate_ast/3`, `generator/0`, `compare_values/2`
4. Register in `builtin_types()` in `lib/grid_codec/type.ex`
5. Add property tests if `generator/0` is implemented
6. Ensure the type name works in `.grid` schema files (the parser resolves type atoms)

### Performance Checklist for Types
- [ ] `encode_ast` generates INLINE code (no runtime function calls)
- [ ] `decode_pattern_ast` extracts integers directly (not `binary-size(N)`) when possible
- [ ] `decode_value_ast` avoids intermediate allocations (no tuples, no re-parsing)
- [ ] `validate_ast` implemented for pre-encode validation
- [ ] `coerce_ast` implemented for `new/1` string input handling
- [ ] `decode_as_ast` implemented if this type is a wire_format decode target (e.g., Decimal)
- [ ] No IIFE `(fn -> ... end).()` pattern

### Callback Checklist for Custom Types
Required: `size/0`, `alignment/0`, `null_value/0`, `encode_ast/4`, `decode_pattern_ast/2`, `getter_ast/3`
Optional:
- `decode_value_ast/1` — post-decode transformation
- `validate_ast/3` — pre-encode type validation
- `coerce_ast/1` — string/external input coercion for `new/1`
- `decode_as_ast/2` — decode-time wire→domain type coercion for `wire_format:` option
- `generator/0` — StreamData generator for property tests
- `compare_values/2` — custom comparison logic

## Compiler Architecture

`lib/grid_codec/struct/compiler.ex` — the `__before_compile__` macro generates everything.

Key generation functions:
- `generate_encode_api` / `generate_decode_api` — public API with telemetry
- `generate_struct_encoder_with_groups` — fast-path struct encoding
- `generate_inline_group_steps` — inline sequential group parsing
- `generate_auto_batch_encoder` / `generate_auto_batch_decoder` — JIT-friendly loops
- `generate_validate_fn` — type-level validation when `validate: true`

The `__schema__/0` map includes: `fields`, `groups`, `batches`, `group_fields`, `version`, `template_id`, `schema_id`, `endian`, `block_length`, `fixed_fields`, `var_fields`, `field_versions`, `type`. This metadata is used by `mix grid_codec.export` to generate `.grid` files.

## Groups

Three group styles exist, each with different compiler paths:

| Style | DSL | Compiler path | Decode result |
|-------|-----|--------------|---------------|
| Fixed (inline) | `group :g do ... end` | `process_groups` → auto entry codecs | Lazy `%Group{}` |
| Fixed (typed) | `group :g, of: Module` | `resolve_typed_group!` → module codecs | Lazy `%Group{}` |
| Framed (typed) | `group :g, of: Module, framing: :length_prefixed` | `resolve_typed_group_framed!` → framed codecs | Eager list |
| Scalar (fixed) | `group :g, of: :uuid` | `process_scalar_group` → scalar codecs | Eager list |
| Scalar (variable) | `group :g, of: :string16` | `process_scalar_group` → auto-framed | Eager list |

The compiler detects scalar vs module via `scalar_type?/1` which checks `GridCodec.Type.lookup/1`.

Custom types work in groups — aliases are expanded in the `group` macro via `Macro.prewalk` + `Macro.expand`.

## Field Options

Fields support several options that affect wire layout and API:

| Option | Effect | Wire-affecting |
|--------|--------|----------------|
| `wire_format: :i64` | Override binary encoding type | Yes |
| `since: 2` | Version-gated field (null before this version) | Yes |
| `presence: :constant` | Excluded from struct, fixed value on wire | Yes |
| `value: "NYSE"` | Constant field value (with `presence: :constant`) | Yes |
| `default: 0` | Default for `new/1` and encode | No (source only) |
| `presence: :required` | `new/1` enforces non-nil | No (source only) |

Parameterized types use tuple syntax: `{:decimal, scale: 8}`.

## .grid Schema Files

`.grid` files are a declarative schema format used for breaking change detection.

### Key Modules

| Module | Purpose |
|--------|---------|
| `GridCodec.Schema.Parser` | Parse `.grid` content into `%Schema{}`, `@syntax` validation, `current_syntax/0` |
| `GridCodec.Schema.Formatter` | Export `__schema__/0` to `.grid` string; `format/5`, `format_master/5`, `format_struct_file/3`, `format_enum_file/2` accept `opts` (`:syntax`, `:imports`); `current_syntax/0`, `detect_all_enums/1`, `referenced_enums/2` |
| `GridCodec.Breaking.Checker` | Compare old/new schemas, apply rules, return issues |
| `GridCodec.Breaking.Rules.Wire` | 22 WIRE rules (binary compatibility, incl. `WIRE_SYNTAX_VERSION_CHANGED`) |
| `GridCodec.Breaking.Rules.Source` | 8 SOURCE rules (API compatibility) |
| `GridCodec.Breaking.Differ` | Structural diff between two parsed schemas |
| `GridCodec.Breaking.Config` | Load `.grid_codec.exs` configuration |
| `GridCodec.Registry` | Runtime codec dispatch; `lookup_enum_by_name/1` for `.grid` type auto-resolution |

### Mix Tasks

- `mix grid_codec.export` — generate `.grid` files from compiled codecs (`--syntax N` to target a version; config fallback: `config :app, :grid_codec, syntax: N`)
- `mix grid_codec.breaking` — detect breaking changes against a baseline

### .grid Syntax (syntax 1)

Every `.grid` file starts with `@syntax 1`. The formal spec is in `GridCodec.Schema.Parser`'s `@moduledoc`.

```
@syntax 1

schema Trading {
  id: 100
  version: 1
}

import "order_side.grid"

enum Side : u8 {
  buy = 1
  sell = 2
}

struct Order (template_id: 1001, version: 2) {
  id: uuid_string
  price: decimal(scale: 8), wire_format: i64
  quantity: u32, default: 0
  exchange: string8, presence: constant, value: "NYSE"
  notes: string16, since: 2

  # Inline field group (fixed-size entries)
  group fills {
    price: u64
    qty: u32
  }

  # Framed group (variable-length entries)
  group line_items {
    framing: length_prefixed
    description: string16
    amount: u64
  }

  # Scalar groups (homogeneous value lists)
  group tag_ids : uuid {}
  group labels : string16 {
    framing: length_prefixed
  }

  batch commands {
    any_of: [PlaceOrder, CancelOrder]
    strategy: padded_union
  }
}
```

### Compiling from .grid Files with Custom Types

When a `.grid` file references enum types, the compiler needs to resolve short names
(e.g., `OrderSide`) to Elixir modules. Two mechanisms:

1. **Explicit `types:` option** — `use GridCodec.Struct, grid_file: "...", types: %{OrderSide: MyApp.Types.OrderSide}`
2. **Auto-resolve** — `GridCodec.Registry.lookup_enum_by_name/1` searches loaded enum modules by last module segment

### Cross-Cutting Concerns Matrix

Every change touches multiple subsystems. Use the matrix below to identify ALL
systems that need updating based on what kind of change you're making.

#### Subsystem Reference

| ID | Subsystem | File(s) |
|----|-----------|---------|
| C-ENC | Compiler: encode AST | `struct/compiler.ex` — `generate_struct_encoder_with_groups` |
| C-DEC | Compiler: decode AST | `struct/compiler.ex` — `generate_inline_group_steps`, `generate_decoder` |
| C-NEW | Compiler: `new/1` coercion | `struct/compiler.ex` — `build_group_coercions`, `build_cast_body` |
| C-SCH | Compiler: `__schema__/0` metadata | `struct/compiler.ex` — schema map in `__before_compile__` |
| C-TYP | Compiler: typespec generation | `struct/compiler.ex` — `build_struct_type_ast` |
| C-STR | Compiler: struct fields | `struct/compiler.ex` — `compute_struct_fields` |
| C-LKP | Compiler: lookup builder | `struct/compiler.ex` — `generate_group_lookup_builder` |
| C-VAL | Compiler: validation | `struct/compiler.ex` — `generate_validate_fn` |
| GRP | Group runtime | `group.ex` — encode/decode/parse functions |
| P-TOK | Parser: tokenizer | `schema/parser.ex` — `tokenize` |
| P-GRM | Parser: grammar + structs | `schema/parser.ex` — `parse_struct_body`, struct defs |
| F-EMT | Formatter: emit | `schema/formatter.ex` — `format_struct_block` |
| L-GRD | .grid loader | `struct.ex` — `generate_from_struct_def` |
| B-WIR | Breaking: wire rules | `breaking/rules/wire.ex` |
| B-SRC | Breaking: source rules | `breaking/rules/source.ex` |
| MACRO | DSL macro | `grid_codec.ex` — `group/2`, `field/3`, `virtual/2`, etc. |
| DOC | Documentation | `AGENTS.md`, `CHANGELOG.md`, moduledocs |
| TEST | Tests | unit + property + `.grid` roundtrip |

#### Change → Subsystem Impact Map

**Adding a new group style** (e.g., scalar groups, framed groups):
- [ ] MACRO — pass new options through (or validate conflicts)
- [ ] C-ENC — generate batch encoder (or reuse existing)
- [ ] C-DEC — add branch in `generate_inline_group_steps`
- [ ] C-NEW — add coercion case in `build_group_coercions` + `build_cast_body`
- [ ] C-SCH — ensure processed opts flow into `__schema__/0` (strip internal keys)
- [ ] C-TYP — handle in `build_struct_type_ast` (don't reference non-existent structs)
- [ ] C-LKP — add dispatch in `generate_group_lookup_builder`
- [ ] GRP — add runtime encode/parse functions if needed
- [ ] P-GRM — add grammar rule + `Group` struct field
- [ ] P-TOK — verify tokenizer handles new syntax (e.g., adjacent braces)
- [ ] F-EMT — add emit branch in `group_lines` generation
- [ ] L-GRD — convert parsed group back to DSL opts in `generate_from_struct_def`
- [ ] DOC — update `group.ex` moduledoc, `AGENTS.md`, `CHANGELOG.md`
- [ ] TEST — roundtrip, `new/1`, schema introspection, `.grid` parse+format

**Adding a new field option** (e.g., `since:`, `presence:`, `wire_format:`):
- [ ] MACRO — pass through (field options are opaque)
- [ ] C-ENC — handle in `field_encode_ast` or `generate_wire_format_encode_ast`
- [ ] C-DEC — handle in decoder pattern generation
- [ ] C-SCH — include in field metadata tuple
- [ ] P-GRM — add to field extras parsing (`parse_field_with_extras`)
- [ ] F-EMT — emit in `format_field_line`
- [ ] L-GRD — pass through in `grid_field_to_def`
- [ ] B-WIR — add wire rule if it affects binary layout
- [ ] B-SRC — add source rule if it affects API
- [ ] TEST — roundtrip, breaking detection, `.grid` roundtrip

**Adding a new built-in type**:
- [ ] Type module — implement `@behaviour GridCodec.Type` callbacks
- [ ] Register in `builtin_types()` in `lib/grid_codec/type.ex`
- [ ] P-GRM — parser resolves type atoms automatically (no change if simple)
- [ ] TEST — roundtrip in `struct_all_types_test.exs`, property test if `generator/0`

**Adding a new struct-level feature** (e.g., virtual fields):
- [ ] MACRO — new macro or option in `defcodec`
- [ ] C-STR — include in `defstruct` field list
- [ ] C-NEW — include/exclude from `new/1` based on options
- [ ] C-SCH — add metadata to `__schema__/0`
- [ ] F-EMT — decide: emit or skip in `.grid` export
- [ ] DOC — AGENTS.md, CHANGELOG, moduledoc
- [ ] TEST — struct definition, encode/decode behavior, `new/1`

#### Verification: .grid Roundtrip Test

Every feature representable in `.grid` MUST survive this roundtrip:

    define in Elixir → export via formatter → parse → load via grid_file: → same behavior

If a feature is NOT representable in `.grid` (e.g., virtual fields), it must be
explicitly skipped by the formatter and documented as such.

## Adding a Macro-Based Composite Type (e.g., PrefixedId)

For types that need per-instance configuration (prefix, tag, etc.), use the `__using__/1` macro pattern:

```elixir
defmodule GridCodec.Types.PrefixedId do
  defmacro __using__(opts) do
    prefix = Keyword.fetch!(opts, :prefix)
    tag = Keyword.fetch!(opts, :tag)
    quote do
      @behaviour GridCodec.Type
      # implement all callbacks using unquote(prefix), unquote(tag)
    end
  end
end
```

Usage: `use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01`

Key differences from built-in types:
- Not registered in `builtin_types()` — referenced as module (e.g., `MyApp.Types.UserId`)
- Each using module implements its own `GridCodec.Type` callbacks
- Exposes helper functions: `generate/0`, `from_uuid/1`, `to_uuid/1`, `valid?/1`, `prefix/0`, `tag/0`
- Wire format: fixed 17 bytes (u8 tag + 16-byte UUID)
- SQL: `gridcodec.read_prefixed_id(data, pos)` and `read_prefixed_id_tag(data, pos)` helpers
- `.grid` schema: NOT YET SUPPORTED — formatter emits raw module name, needs grammar extension

## Release Workflow

```
mix format
mix credo --strict
mix test                    # all tests must pass
cd example_app && mix grid_codec.export  # regenerate .grid baselines
# Update CHANGELOG.md
# Bump version in mix.exs
git add -A && git commit && git push
# Verify CI passes
```
