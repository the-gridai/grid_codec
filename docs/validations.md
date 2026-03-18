# Validation Pipelines

GridCodec validation now has three layers:

- **Coercion / cast validation**: `new/1`, `update/2`, and `new_binary/1` coerce
  external input into the field's domain type.
- **Type validation**: `validate: true` runs per-type checks such as integer
  ranges, UUID formats, and refined custom-type checks before encode.
- **State validations**: `validations do` / `invariants do` define accumulating,
  non-raising checks over the struct as a whole.

This keeps field-local rules in the type system and reserves struct validations
for cross-field invariants.

Decoded validation is two-phase:

- type validation short-circuits on the first field/type failure
- struct/state validations accumulate only after the struct is type-safe

This means function validators can assume referenced fields are already in their
declared domain types instead of defensively guarding against malformed values
from manually-constructed structs.

Validation declarations are **runtime-only Elixir metadata**. They are not
exported to `.grid`, not parsed from `.grid`, and do not affect the wire
protocol.

## When To Use Which

- Use a **refined/custom type** when a rule is local to one field:
  `NonNegativeI64`, `PositiveQuantity`, `NonEmptyString`
- Use a **struct validation** when a rule relates multiple fields:
  `end_time >= start_time`, `x != y`
- Keep **workflow/command checks** outside GridCodec when the rule depends on
  action context or event-sourcing lifecycle

## Refined Types

`GridCodec.Type.Refined` wraps an existing base type and adds a `refine/1`
callback:

```elixir
defmodule MyApp.Types.NonNegativeI64 do
  use GridCodec.Type.Refined, base: :i64

  @impl true
  def refine(nil), do: :ok
  def refine(value) when value >= 0, do: :ok
  def refine(_value), do: {:error, "must be >= 0"}
end
```

Use the refined type directly in your codec:

```elixir
defcodec do
  field :balance, MyApp.Types.NonNegativeI64
end
```

## Struct Validation Pipeline

Use `validations do` for explicit pipelines:

```elixir
defmodule MyApp.Window do
  use GridCodec.Struct, template_id: 10, validate: true

  defcodec do
    field :start_ns, :timestamp_ns
    field :end_ns, :timestamp_ns
    field :status, :u8
  end

  validations do
    validate compare(:end_ns, :>=, :start_ns),
      name: :end_after_start,
      category: :invariant

    validate one_of(:status, [1, 2]),
      name: :known_status,
      category: :invariant

    validate &__MODULE__.custom_checks/1,
      name: :custom_checks,
      category: :invariant
  end

  def custom_checks(%__MODULE__{start_ns: s, end_ns: e})
      when is_integer(s) and is_integer(e) and s == e do
    [
      GridCodec.ValidationError.invariant_failed(
        __MODULE__,
        :endpoints_differ,
        "start_ns and end_ns must differ"
      )
    ]
  end

  def custom_checks(_), do: []
end
```

`invariants do` is optional sugar for simple expression-style checks:

```elixir
invariants do
  invariant :status_positive do
    where status > 0
  end
end
```

Function validators run after type validation succeeds, so they should focus on
cross-field business rules rather than re-checking field types.

## Error Contract

Public APIs return errors instead of raising:

- `{:error, %GridCodec.ValidationError{}}` for a single failure
- `{:error, %GridCodec.ValidationErrors{errors: [...]}}` when validations
  accumulate multiple failures

This applies to:

- `new/1`
- `update/2`
- `new_binary/1`
- `encode/1`
- `validate_struct/1`
- `validate_binary/1`
- `decode/2` when `validate:` is enabled

For decoded validation paths, type validation is fail-fast. If a field has an
invalid type/domain value, GridCodec returns that type error and does not run
decoded invariant callbacks for the same struct.

## Binary Validation

Some validators can also run on raw binaries.

Use:

```elixir
MyCodec.validate_binary(binary)
MyCodec.valid?(binary)
MyCodec.decode(binary, validate: :binary)
MyCodec.decode(binary, validate: :both)
```

Binary validation is intentionally a subset. It reuses fixed-field metadata and
zero-copy extraction, so it works best for fixed-size fields and simple
comparison/presence checks.

## Support Matrix

| Validator kind | Decoded | Binary | Notes |
|---|---|---|---|
| `compare/3` | Yes | Yes for fixed-size fields | Cross-field and field-vs-literal |
| `present/1` | Yes | Yes for fixed-size fields | Nil-sensitive |
| `one_of/2` | Yes | Yes for fixed-size fields | Uses decoded field values |
| `invariant ... where ...` | Yes | Only when it compiles to builtin compare sugar | Arbitrary expressions currently stay decoded-only |
| `validate &fun/1` | Yes | No | Best for rich Elixir logic |

Unsupported in binary validation:

- variable-length fields
- groups and batches
- arbitrary function validators
- rich domain semantics that require full struct context

## Benchmarking

Use the example app benchmark to compare generated validation against
hand-rolled and generic alternatives:

```bash
cd example_app
MIX_ENV=prod mix run benchmarks/validation_bench.exs
```

The benchmark covers:

- generated `validate_struct/1`
- generated `validate_binary/1`
- hand-rolled struct validation with direct guards
- hand-rolled binary pattern validation
- generic map validation pipelines built from anonymous functions

This benchmark is intended as a regression harness and optimization target for
future compiler work, especially on the happy-path allocation profile of
generated struct validation.

## Decode Validation Modes

`decode/2` accepts `validate:`:

- `:none` or `false` — no extra validation
- `:decoded` or `true` — run decoded validations on the decoded struct
- `:binary` — run only binary-capable validators on the source binary
- `:both` — run both backends and merge failures

`validate: :both` de-duplicates identical failures so the same invariant is not
reported twice.
