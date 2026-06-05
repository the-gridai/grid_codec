---
name: testing-strategy
description: Write and maintain tests for GridCodec — unit tests, property-based tests with StreamData, roundtrip tests, and compile-time error tests. Use when writing tests, adding property tests, testing new types, or verifying codec correctness.
---

# Testing Strategy for GridCodec

## Elixir 1.20 gradual typing (warnings in tests)

Gradual typing surfaces issues at **compile time** for generated code and test
modules. Treat compiler warnings during `mix test` as failures.

### Compile paths

| Path | What it compiles |
|------|------------------|
| `mix compile` (`:dev`) | `lib/` only |
| `MIX_ENV=test mix compile` | `lib/` + `test/support/` |
| `mix test` | above + inline `defmodule` in `.exs` files |

Always run `mix test` and assert **zero** `warning:` lines after compiler changes.

### Patterns that avoid false positives and noise

**Bitstring `size(variable)`** — pin variables defined outside the match:

```elixir
header_size = 8
<<_::binary-size(^header_size), rest::binary>> = binary
```

**Intentionally invalid calls** (unsupported compare op, wrong types) — use
`apply/3` so the gradual checker does not reject the call before `assert_raise`:

```elixir
assert_raise ArgumentError, fn ->
  apply(GridCodec, :compare, [binary, field_spec, :in, 100])
end
```

**Generated `get(..., copy: true)`** — tests on integer fields should pass
through unchanged; UUID/char_array tests may use `:binary.referenced_byte_size/1`.

**Match macro** — `match(price: p)` returns raw sentinels, not `nil`; avoid
`refute result == nil` when `result` is typed as integer (use `refute is_nil/1`
only when the type allows nil, or assert on the sentinel value).

### Regression fixtures

- `test/support/required_decode_warning_fixture.ex` — required fields / map fallback
- `test/grid_codec/validation_pipeline_test.exs` — inline codecs with `validations do`
- `example_app/lib/.../reservation.ex` — consumer codec with validations

## Test Categories

### 1. Unit Tests (ExUnit)

Standard assertion-based tests for specific behavior. Located in `test/grid_codec/`.

**Generated codec doctests:** For `use GridCodec.Struct` modules, rely on compiler-emitted `iex>` docs (from `GridCodec.DocExampleValues` + `lib/grid_codec/struct/compiler.ex`) and run `doctest/1` over an explicit or discovered module list; add a guard that `Code.fetch_docs/1` contains `"iex>"` so doctest cannot silently run zero examples. Reference `test/grid_codec/codec_doctest_test.exs` and `example_app/test/example_app/codec_doctest_test.exs`. Use `doc_examples: false` when a codec cannot get safe deterministic examples. Global coverage percentage alone does not prove every codec has `iex>` lines.

**Roundtrip pattern** — the most common test for codecs:
```elixir
test "encode and decode roundtrip" do
  struct = %MyCodec{id: 42, name: "test"}
  {:ok, binary} = MyCodec.encode(struct)
  assert {:ok, decoded} = MyCodec.decode(binary)
  assert decoded.id == 42
  assert decoded.name == "test"
end
```

**Null handling:**
```elixir
test "nil fields encode as null sentinels and decode back to nil" do
  struct = %MyCodec{id: nil}
  {:ok, binary} = MyCodec.encode(struct)
  {:ok, decoded} = MyCodec.decode(binary)
  assert decoded.id == nil
end
```

**Compile-time error tests:**
```elixir
test "variable-length field in group raises CompileError" do
  assert_raise CompileError, ~r/variable-length fields/, fn ->
    defmodule BadCodec do
      use GridCodec.Struct, template_id: 999, schema_id: 99
      defcodec do
        group :items do
          field :name, :string  # variable-length, not allowed
        end
      end
    end
  end
end
```

### 2. Property-Based Tests (StreamData + ExUnitProperties)

For testing invariants across random inputs. Requires `use ExUnitProperties`.

**Roundtrip property** — the gold standard for codec correctness:
```elixir
property "any valid input roundtrips through encode/decode" do
  check all(
    id <- StreamData.integer(0..1_000_000),
    flag <- StreamData.boolean(),
    price <- StreamData.integer(0..100_000_000)
  ) do
    struct = %MyCodec{id: id, flag: flag, price: price}
    {:ok, binary} = MyCodec.encode(struct)
    assert {:ok, decoded} = MyCodec.decode(binary)
    assert decoded.id == id
    assert decoded.flag == flag
    assert decoded.price == price
  end
end
```

**Group roundtrip property with custom types:**
```elixir
property "enum values in groups survive roundtrip" do
  check all(
    n <- StreamData.integer(0..100),
    entries <- StreamData.list_of(
      StreamData.fixed_map(%{
        side: StreamData.member_of([:buy, :sell, nil]),
        price: StreamData.integer(0..1_000_000)
      }),
      length: n
    )
  ) do
    struct = %MyCodec{entries: entries}
    {:ok, binary} = MyCodec.encode(struct)
    {:ok, decoded} = MyCodec.decode(binary)
    decoded_entries = GridCodec.Group.to_list(decoded.entries)
    assert length(decoded_entries) == n

    Enum.zip(entries, decoded_entries)
    |> Enum.each(fn {input, output} ->
      assert output.side == input.side
      assert output.price == input.price
    end)
  end
end
```

**Decimal roundtrip with nil:**
```elixir
property "decimal fields with nil roundtrip" do
  check all(
    value <- StreamData.one_of([
      StreamData.constant(Decimal.new("100.50")),
      StreamData.constant(nil)
    ])
  ) do
    struct = %MyCodec{amount: value}
    {:ok, binary} = MyCodec.encode(struct)
    {:ok, decoded} = MyCodec.decode(binary)
    if value, do: assert(Decimal.equal?(decoded.amount, value)),
              else: assert(decoded.amount == nil)
  end
end
```

### 3. Validation Tests

When `validate: true` is enabled:
```elixir
test "out of range raises ValidationError" do
  error = assert_raise GridCodec.ValidationError, fn ->
    MyCodec.encode(%MyCodec{count: 5_000_000_000})
  end
  assert error.code == :out_of_range
  assert error.details.field == :count
  assert error.details.type == :u32
end

test "new/1 returns {:error, %ValidationError{}} for bad data" do
  assert {:error, %GridCodec.ValidationError{code: :type_mismatch}} =
    MyCodec.new(active: "not_a_bool")
end
```

### 4. Group-Specific Tests

**Empty groups:**
```elixir
test "empty group roundtrips" do
  struct = %MyCodec{items: []}
  {:ok, binary} = MyCodec.encode(struct)
  {:ok, decoded} = MyCodec.decode(binary)
  assert GridCodec.Group.count(decoded.items) == 0
end
```

**Random access:**
```elixir
test "get_entry at arbitrary index" do
  struct = %MyCodec{items: for(i <- 1..50, do: %{value: i})}
  {:ok, binary} = MyCodec.encode(struct)
  {:ok, decoded} = MyCodec.decode(binary)
  assert {:ok, %{value: 25}} = GridCodec.Group.get_entry(decoded.items, 24)
end
```

**Parallel decode:**
```elixir
test "to_lists_parallel matches sequential" do
  # ... encode with multiple groups
  [seq_a, seq_b] = [Group.to_list(d.group_a), Group.to_list(d.group_b)]
  [par_a, par_b] = Group.to_lists_parallel([d.group_a, d.group_b], threshold: 0)
  assert seq_a == par_a
  assert seq_b == par_b
end
```

### 5. Schema Evolution Tests

Tests for `.grid` parser, formatter, and breaking change detection.

**`@syntax` directive tests:**
```elixir
test "parses @syntax 1" do
  assert {:ok, schema} = Parser.parse("@syntax 1\nschema { id: 1 }")
  assert schema.syntax == 1
end

test "defaults syntax to current when absent" do
  assert {:ok, schema} = Parser.parse("schema { id: 1 }")
  assert schema.syntax == Parser.current_syntax()
end

test "rejects unsupported syntax version" do
  assert {:error, {:unsupported_syntax, 999, _}} = Parser.parse("@syntax 999\nschema { id: 1 }")
end
```

**Parser tests for field options and parameterized types:**
```elixir
test "parses parameterized type with field options" do
  schema = """
  @syntax 1
  schema T { id: 1 }
  struct Order (template_id: 1) {
    price: decimal(scale: 8), wire_format: i64, since: 2
  }
  """
  assert {:ok, parsed} = Parser.parse(schema)
  [field] = parsed.structs[:Order].fields
  assert field.type == :decimal
  assert field.type_params == [scale: 8]
  assert field.wire_format == :i64
  assert field.since == 2
end
```

**Formatter round-trip tests:**
```elixir
test "field options survive parse -> format -> parse" do
  # Parse original, format it, re-parse, compare field attributes
end
```

**Breaking change rule tests:**
```elixir
test "detects wire_format change" do
  old = "schema T { id: 1 }\nstruct Order (template_id: 1) { price: decimal(scale: 8), wire_format: i64 }"
  new = "schema T { id: 1 }\nstruct Order (template_id: 1) { price: decimal(scale: 8), wire_format: i32 }"
  assert :WIRE_FIELD_WIRE_FORMAT_CHANGED in rules(wire_check(old, new))
end
```

**Export tests for cross-schema enums and self-contained files:**
```elixir
test "all generated files include @syntax" do
  # Export, then verify every .grid file starts with @syntax directive
end

test "struct files referencing enums include import directives" do
  # Export, find struct files with enum type refs, assert imports present
end
```

**Test files:**
- `test/grid_codec/schema/parser_test.exs` — `@syntax` directive tests, imports, standalone definitions
- `test/grid_codec/breaking/field_opts_test.exs` — parser, formatter, and breaking rules for field options
- `test/grid_codec/breaking/wire_rules_test.exs` — all 27 WIRE rules (incl. `WIRE_SYNTAX_VERSION_CHANGED` and severity policy expectations)
- `test/grid_codec/breaking/source_rules_test.exs` — all 9 SOURCE rules
- `test/grid_codec/breaking/parser_batch_test.exs` — batch parsing
- `test/mix/tasks/grid_codec_export_test.exs` — `@syntax` output, `--syntax` flag, self-contained files, cross-schema imports

## When to Add Tests

| Change | Required tests |
|--------|---------------|
| New type | Roundtrip unit test + property test if generator exists |
| New codec option | Unit test for enabled + disabled behavior |
| Group feature | Roundtrip + empty group + random access |
| Custom type in group | Property test with that type + nil handling |
| Validation | Positive case (valid data) + negative case per error code |
| Performance change | Existing tests must still pass (no behavioral change) |
| New field option | Parser test, formatter round-trip, breaking rule test |
| New .grid syntax | Parser `@syntax` test + formatter export test |
| New breaking rule | Positive (triggers) + negative (no false positive) test |
| Breaking rule severity/policy change | Rule-level severity test + `mix grid_codec.breaking` task test for blocking/non-blocking behavior + override/escalation test |
| Generated code warning/Dialyzer fix | `test/support` fixture compiled by `MIX_ENV=test mix compile --warnings-as-errors`; consumer-style fixture in `example_app/lib`; focused tests for runtime behavior; run `mix dialyzer` and `cd example_app && mix dialyzer --force-check` |
| `@syntax` change | Parser validation test, formatter emission test, `WIRE_SYNTAX_VERSION_CHANGED` test |
| Cross-schema enum | Export test verifying relative import paths + self-contained files |
| `types:` option | Compiler test with explicit mapping + auto-resolve fallback |

## Test File Conventions

| Test file | What it covers |
|-----------|---------------|
| `struct_test.exs` | Core encode/decode, field types, options |
| `struct_all_types_test.exs` | Every built-in type roundtrip (incl. PrefixedId) |
| `auto_group_test.exs` | Groups: roundtrip, custom types, parallel, properties |
| `group_test.exs` | `GridCodec.Group` module: parse, encode, access, iteration |
| `validation_test.exs` | ValidationError, new/1, per-type checks |
| `telemetry_test.exs` | Telemetry event emission, disabled mode |
| `struct_codec_test.exs` | Struct-specific codec edge cases |
| `breaking/field_opts_test.exs` | Parser, formatter round-trip, breaking rules for field opts |
| `breaking/wire_rules_test.exs` | All 27 WIRE breaking change rules (incl. `WIRE_SYNTAX_VERSION_CHANGED`) |
| `breaking/source_rules_test.exs` | All 9 SOURCE breaking change rules |
| `breaking/parser_batch_test.exs` | Batch/any_of .grid syntax |
| `breaking/config_test.exs` | Breaking change config loading |
| `schema/formatter_test.exs` | .grid file generation from schema metadata |

## StreamData Generators for Types

Types that implement `generator/0` can be used in property tests. Check with:
```elixir
function_exported?(GridCodec.Types.U64, :generator, 0)
```

Custom enum/bitset types get generators automatically from their `__before_compile__`.
PrefixedId types implement `generator/0` which produces valid prefixed UUID strings.
Test PrefixedId generators via the type module directly: `MyUserId.generator()`.
