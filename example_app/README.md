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
│       └── events/           # Example event codecs
│           ├── order_created.ex
│           └── trade_executed.ex
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
```

### Run Benchmarks

```bash
# Run all benchmarks
mix bench

# Quick development benchmark (~1 second)
mix bench.quick

# Parameterized benchmarks (small/medium/large data)
mix bench.parameterized

# Or run directly
mix run benchmarks/encode_decode.exs
```

### Example Codecs

See `lib/example_app/events/` for example codecs:

```elixir
defmodule ExampleApp.Events.OrderCreated do
  use GridCodec.Struct, template_id: 1, schema_id: 100

  defcodec do
    field :order_id, :uuid
    field :user_id, :u64
    field :symbol, :string16
    field :side, :u8
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
  side: 1,
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

## Benefits

1. **Struct-based API** - Natural Elixir struct syntax
2. **Optimal Performance** - Direct pattern matching, no intermediate maps
3. **Zero-copy Access** - Read fields without full decode
4. **Type Safety** - Struct fields with enforced keys
