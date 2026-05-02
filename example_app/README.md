# Example App - GridCodec.Struct Usage Example

This is an example application that demonstrates real-world usage of `GridCodec.Struct`.

## Purpose

- **Real-world usage example** - Shows how GridCodec.Struct feels to use in practice
- **Benchmarks with consolidated code** - Uses the Mix compiler for optimized dispatch
- **Validation** - Ensures GridCodec works well in a real application context

## Structure

```
example_app/
├── lib/
│   └── example_app/
│       ├── events/           # Example event codecs
│       └── views/            # Typed-group and lookup examples
├── benchmarks/
│   ├── run_all.exs           # Run all benchmarks
│   ├── quick_bench.exs       # Quick dev benchmark
│   ├── parameterized_bench.exs  # Size-parameterized benchmarks
│   ├── encode_decode.exs     # Encode/decode performance
│   ├── data_structures.exs   # Test data definitions
│   └── config.exs            # Benchmark configuration
└── mix.exs
```

## Usage

### Setup

```bash
cd example_app
mix deps.get
mix compile
mix check
mix dialyzer
```

`mix check` mirrors the example app quality gate in CI: compile with warnings as
errors, run tests, format check, Credo, and Dialyzer.

### Run Benchmarks

```bash
# Run all benchmarks
mix bench

# Quick development benchmark (~1 second)
mix bench.quick

# Parameterized benchmarks (small/medium/large data)
mix bench.parameterized

# Validation pipeline benchmark
mix bench.validation

# Or run directly
mix run benchmarks/encode_decode.exs
MIX_ENV=prod mix run benchmarks/lookup_bench.exs
MIX_ENV=prod mix run benchmarks/validation_bench.exs
```

### Example Codecs

See `lib/example_app/events/` for example codecs:

```elixir
defmodule ExampleApp.Events.OrderCreated do
  use GridCodec.Struct, template_id: 1, schema_id: 100

  alias ExampleApp.Types.OrderSide

  defcodec do
    field :order_id, :uuid
    field :user_id, :u64
    field :symbol, :string16
    field :side, OrderSide
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
    field :flags, :u8
  end
end
```

Usage:

```elixir
# Create and encode
order = %ExampleApp.Events.OrderCreated{
  order_id: <<1::128>>,
  user_id: 12345,
  symbol: "BTCUSD",
  price: 15000,
  quantity: 100,
  side: :buy,
  timestamp: DateTime.utc_now(),
  flags: 0
}

{:ok, binary} = ExampleApp.Events.OrderCreated.encode(order)

# Decode
{:ok, decoded} = ExampleApp.Events.OrderCreated.decode(binary)

# Zero-copy field access (no full decode!)
require ExampleApp.Events.OrderCreated
price = ExampleApp.Events.OrderCreated.get(binary, :price)

# Dispatch (with consolidated registry)
{:ok, framed} = GridCodec.encode(order)
{:ok, decoded} = GridCodec.decode(framed)
```

### Typed Groups And Lookups

See `lib/example_app/views/` for a concrete aggregate-style example:

- `Reservation` — fixed-size typed group entry with `:datetime_us`
- `CurrencyAccount` — `group :reservations, of: Reservation` plus generated lookups
- `CommandEnvelope` — heterogeneous batch with per-type keyed lookups

You can also try the example at runtime:

```elixir
ExampleApp.lookup_usage()
```

The lookup examples in `views/` are also part of the example app's Dialyzer
coverage, so they double as integration tests for normal consumer usage.

### Lifecycle Hooks

`CurrencyAccount` also demonstrates struct lifecycle hooks for aggregate
snapshots. The `.grid` contract persists durable `reservations`, while runtime
code can keep virtual indexes such as `reservation_index` and
`active_reservation_ids`.

`before_encode/2` materializes the durable group from the runtime index when
needed. `after_decode/2` rebuilds the virtual indexes after loading the binary
snapshot and records the decoded schema version from header metadata.

## Benefits

1. **Struct-based API** - Natural Elixir struct syntax
2. **Optimal Performance** - Direct pattern matching, no intermediate maps
3. **Zero-copy Access** - Read fields without full decode
4. **Type Safety** - Struct fields with enforced keys
