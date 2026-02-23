# Schema Files (`.grid`)

GridCodec supports schema-driven codec generation through `.grid` files.

## Basic Structure

```text
schema Trading {
  id: 100
  version: 1
}

struct Order (template_id: 1001) {
  id: uuid_string
  price: u64
  quantity: u32
}
```

## Supported Top-Level Blocks

- `schema` metadata (`id`, `version`, optional schema name)
- `struct` message declarations
- `type` composite types
- `enum` enum types

Legacy `message Name (1001) { ... }` syntax is also supported.

## Struct Attributes

```text
struct Trade (template_id: 1002, version: 2) {
  trade_id: uuid_string
  amount: u64
}
```

- `template_id` is required for dispatch
- `version` overrides schema-level version for that struct

## Optional Fields

Mark optional fields with `?`:

```text
struct User (template_id: 2001) {
  id: uuid_string
  nickname?: string16
}
```

## Groups

```text
struct OrderBook (template_id: 3001) {
  symbol: uuid_string

  group bids {
    price: u64
    qty: u32
  }
}
```

Each group entry is fixed-size and encoded as a repeating block.

## Using a `.grid` File

```elixir
defmodule MyApp.Order do
  use GridCodec.Struct,
    grid_file: "priv/schemas/trading.grid",
    message: :Order
end
```

## Validation and Limits

Parser safety options are available:

- `max_identifiers` (default: `2048`)
- `max_identifier_length` (default: `128`)

For custom parsing:

```elixir
GridCodec.Schema.Parser.parse(content, max_identifiers: 1000)
GridCodec.Schema.Parser.parse_file(path, max_identifier_length: 64)
```
