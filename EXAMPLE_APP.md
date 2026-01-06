# Example App - Real-World Usage & Benchmarks

## Overview

The `example_app/` directory contains a separate Elixir application that demonstrates real-world usage of GridCodec and runs comprehensive benchmarks with consolidated compiled code.

## Benefits

### 1. **Lightweight Library**
The main `grid_codec` library now has minimal dependencies:
- **Runtime**: Only `decimal` (for Decimal type support)
- **Dev/Test**: Only code quality tools (ex_doc, dialyxir, credo, etc.)

All benchmark and comparison codec dependencies have been moved to `example_app/`.

### 2. **Real-World Usage Example**
The example app shows how GridCodec feels to use in practice:
- Event sourcing patterns (`OrderCreated`, `TradeExecuted`)
- Real-world data structures
- Actual usage patterns

### 3. **Consolidated Code Benchmarks**
The example app uses the `:grid_codec` Mix compiler, so benchmarks run with:
- Optimized pattern-match dispatch
- Consolidated registry
- Production-like code paths

### 4. **Dependency Separation**
- **Library**: Minimal, production-focused dependencies
- **Example App**: All benchmark/comparison/profiling tools

## Structure

```
example_app/
├── lib/
│   └── example_app/
│       └── events/
│           ├── order_created.ex    # Example event codec
│           └── trade_executed.ex   # Example event codec
├── benchmarks/
│   ├── run_all.exs                 # Run all benchmarks
│   ├── encode_decode.exs           # Encode/decode performance
│   ├── dispatch.exs                 # Dispatch performance
│   └── comparison.exs              # Comparison with other codecs
├── mix.exs                          # App configuration
└── README.md                        # Usage instructions
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

# Or run specific benchmarks
mix run benchmarks/encode_decode.exs
mix run benchmarks/dispatch.exs
mix run benchmarks/comparison.exs
```

## Example Codecs

### OrderCreated Event

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

### Usage Example

```elixir
# Create an event
order = %ExampleApp.Events.OrderCreated{
  order_id: :crypto.strong_rand_bytes(16),
  user_id: 12_345_678_901_234_567,
  symbol: "BTCUSD",
  side: 1,
  price: 15_000_000_000,
  quantity: 100_000,
  timestamp: DateTime.utc_now(),
  flags: 7
}

# Encode
binary = ExampleApp.Events.OrderCreated.encode(order)

# Decode
{:ok, decoded} = ExampleApp.Events.OrderCreated.decode(binary)

# Dispatch (with consolidated registry)
binary_framed = GridCodec.encode(order)
{:ok, decoded} = GridCodec.decode(binary_framed)
```

## Benchmarks

### 1. Encode/Decode Performance
Measures raw encode/decode performance for example codecs.

### 2. Dispatch Performance
Compares dispatch overhead (consolidated vs direct calls).

### 3. Codec Comparison
Compares GridCodec with:
- JSON (Jason)
- MessagePack (Msgpax)
- ETF (Erlang Term Format)

## Dependencies

### Main Library (`grid_codec`)
- `decimal` (runtime)
- `ex_doc`, `dialyxir`, `credo`, etc. (dev/test only)

### Example App (`example_app`)
- `grid_codec` (path dependency)
- `benchee`, `benchee_html` (benchmarking)
- `jason`, `msgpax`, `protobuf`, etc. (comparison codecs)
- `recon` (profiling)

## Next Steps

1. Add more example codecs (messages, custom types, etc.)
2. Add integration examples (Phoenix.PubSub, event stores, etc.)
3. Add profiling examples
4. Document real-world usage patterns

## Notes

- The `:grid_codec` compiler is currently commented out until Mix.Task registration is complete
- Benchmarks still work with the fallback registry
- Once the compiler is enabled, benchmarks will use optimized consolidated code

