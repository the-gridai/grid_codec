# Typed Groups and Lookups

Typed groups and lookups extend the core `defcodec` DSL with two related goals:

- reuse fixed-size entry structs inside repeating collections
- define named alternate access paths over `group` and `batch` fields

These features are **Elixir-side conveniences**. They do not change the wire
format, and lookups are not exported to `.grid`.

## Typed Groups

Use a typed group when repeated entries already have a reusable fixed-size
codec struct:

```elixir
defmodule MyApp.Reservation do
  use GridCodec.Struct, template_id: 10, schema_id: 100

  defcodec do
    field :reservation_id, :u64
    field :amount, :u64
    field :active, :bool
    field :expires_at, :datetime_us
  end
end

defmodule MyApp.CurrencyAccount do
  use GridCodec.Struct, template_id: 11, schema_id: 100

  defcodec do
    field :account_id, :u64
    group :reservations, of: MyApp.Reservation
  end
end
```

### What `of:` gives you

- `new/1` coerces group entries through `Reservation.new/1`
- decode materializes `%Reservation{}` values when the group is enumerated
- the entry schema is declared once, not duplicated inside each parent codec

### Constraints

- the entry module must be a `GridCodec.Struct`
- the entry module must be fixed-size
- nested groups, nested batches, and variable-length fields are rejected

## Lookups

Lookups are generated runtime accessors over a decoded `group` or `batch`
field. They are declared inside a `lookups do` block:

```elixir
defcodec do
  group :reservations, of: MyApp.Reservation

  lookups do
    lookup :reservations_by_id do
      from :reservations
      into :map
      key :reservation_id
    end

    lookup :active_reservations do
      from :reservations
      into :list
      where active: true
    end
  end
end
```

### Using a lookup

```elixir
{:ok, account} = MyApp.CurrencyAccount.decode(binary)

{:ok, reservations_by_id} = MyApp.CurrencyAccount.reservations_by_id(account)
{:ok, active_reservations} = MyApp.CurrencyAccount.active_reservations(account)
```

Lookups can also be built from the collection field directly:

```elixir
{:ok, reservations_by_id} =
  MyApp.CurrencyAccount.reservations_by_id(account.reservations)
```

### Generic access

All codecs with lookups also get:

```elixir
MyCodec.lookup(decoded, :lookup_name)
MyCodec.__lookups__()
MyCodec.__lookup__(:lookup_name)
```

Compatibility wrappers `view/2`, `__views__/0`, and `__view__/1` remain
available, but `lookup/2` and `lookups do` are the preferred naming.

## Batch Lookups

Batches are heterogeneous, so lookups can define per-type keys:

```elixir
defcodec do
  batch :commands, any_of: [PlaceReservation, ReleaseReservation]

  lookups do
    lookup :commands_by_reservation_id do
      from :commands
      into :map
      key PlaceReservation, :reservation_id
      key ReleaseReservation, :reservation_id
    end
  end
end
```

## Duplicate Keys

If duplicate keys appear in a keyed lookup, the last entry wins:

```elixir
lookup :reservations_by_id do
  from :reservations
  into :map
  key :reservation_id
end
```

This keeps the runtime behavior simple and matches common `Map.new/2`
expectations in Elixir code.

## Compile-Time Validation

The compiler validates that:

- the `from` source exists
- `into :map` has key declarations
- key fields exist on the referenced entry schema
- batch lookups cover all `any_of:` modules unless a shared key works for all
- filters reference known fields

This keeps lookup failures deterministic and surfaces mistakes before runtime.

## Performance Model

Lookups are not just syntax sugar over ad hoc `Enum` pipelines.

Current implementation benefits:

- codec-level declarations validate sources and keys at compile time
- group lookups can take a direct reducer path over decoded group payloads
- batch lookups compile against the known `any_of:` set and field selections
- codec modules get a stable, reusable access API instead of repeated anonymous
  `Enum` pipelines throughout the codebase

Benchmark script:

```bash
cd example_app
MIX_ENV=prod mix run benchmarks/lookup_bench.exs
```

That benchmark compares:

- generated group map lookups
- generated group filtered-list lookups
- generated batch keyed-map lookups
- equivalent manual `to_list |> Map.new` / `to_list |> Enum.filter` pipelines

On the Apple M3 Max reference run captured while implementing the feature:

- generated keyed **group** lookup was faster and leaner than the equivalent
  manual `GridCodec.Group.to_list(...) |> Map.new(...)` pipeline
  (`5.69 ms`, `6.94 MB` vs `6.21 ms`, `8.49 MB`)
- generated filtered **group** list lookups were also faster than the manual
  `to_list |> Enum.filter` pipeline (`3.47 ms` vs `4.67 ms`) and used less
  memory (`6.19 MB` vs `7.81 MB`)
- generated keyed **batch** lookups are currently about declarative correctness,
  compile-time validation, and reuse first; they are not yet faster than a
  hand-written `GridCodec.Batch.to_list(...) |> Map.new(...)` pipeline

Keyed lookups always use last-write-wins semantics today.

## `.grid` Boundary

Typed groups and lookups have different schema status:

- typed groups are currently Elixir-side compiler sugar over the existing group
  wire format
- lookups are purely runtime metadata and are not exported to `.grid`

This keeps the transport schema canonical and avoids introducing runtime-only
accessor semantics into the cross-language schema format.
