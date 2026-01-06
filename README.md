# GridCodec

[![CI](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml/badge.svg)](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml)

High-performance binary codec for BEAM/Elixir with zero-copy field access.

## Features

- **Zero-copy field access** – Read fields directly from binary without full decode (O(1))
- **Sub-binary sharing** – One encode, many readers with no memory copies
- **Compile-time code generation** – No runtime reflection overhead
- **Struct-based API** – Natural Elixir structs with binary serialization

## Installation

Add `grid_codec` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:grid_codec, git: "https://github.com/Spectral-Finance/grid_codec.git"}
  ]
end
```

## Quick Start

```elixir
defmodule MyApp.Events.UserCreated do
  use GridCodec.Struct, template_id: 1, schema_id: 100

  defcodec do
    field :user_id, :uuid
    field :score, :u64, presence: :required
    field :level, :u32
    field :active, :bool
    field :created_at, :timestamp_us
  end
end

# Create and encode
user = %MyApp.Events.UserCreated{
  user_id: :crypto.strong_rand_bytes(16),
  score: 1500,
  level: 42,
  active: true,
  created_at: System.system_time(:microsecond)
}

binary = MyApp.Events.UserCreated.encode(user)

# Zero-copy field access (no full decode!)
env = MyApp.Events.UserCreated.wrap(binary)
score = MyApp.Events.UserCreated.get(env, :score)
# => 1500

# Full decode when needed
{:ok, decoded} = MyApp.Events.UserCreated.decode(binary)

# Top-level dispatch (with framed binary)
framed = GridCodec.encode(user)
{:ok, decoded} = GridCodec.decode(framed)
```

## Field Types

### Fixed-Size Types

| Type | Size | Description |
|------|------|-------------|
| `:u8`, `:u16`, `:u32`, `:u64` | 1-8 | Unsigned integers |
| `:i8`, `:i16`, `:i32`, `:i64` | 1-8 | Signed integers |
| `:f32`, `:f64` | 4, 8 | IEEE 754 floats |
| `:uuid` | 16 | Binary UUID |
| `:bool` | 1 | Boolean |
| `:timestamp_us` | 8 | Microsecond timestamp |
| `:timestamp_ns` | 8 | Nanosecond timestamp |
| `:decimal` | 9 | Decimal (mantissa + exponent) |

### Variable-Size Types

| Type | Prefix | Description |
|------|--------|-------------|
| `:string8` | u8 | Short strings (max 255 bytes) |
| `:string` / `:string16` | u16 | UTF-8 string (default) |
| `:string32` | u32 | Large text |

## Documentation

Full documentation is available via ExDoc:

```bash
mix docs
open doc/index.html
```

Key modules:

- `GridCodec` – Top-level dispatch API
- `GridCodec.Struct` – DSL for defining struct codecs
- `GridCodec.Envelope` – Wrapper for zero-copy field access
- `GridCodec.Group` – Repeating groups (variable-length collections)
- `GridCodec.Dispatch` – Multi-message routing by template ID
- `GridCodec.Type` – Behaviour for custom types

## Example App

For real-world usage examples and benchmarks:

```bash
cd example_app
mix deps.get
mix compile
mix bench  # Run benchmarks
```

See `example_app/README.md` for details.

## License

MIT License – see [LICENSE](LICENSE) for details.
