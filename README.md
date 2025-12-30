# GridCodec

[![CI](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml/badge.svg)](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml)

High-performance binary codec for BEAM/Elixir with direct field access.

## Features

- **Direct field access** – Read fields directly from binary without full decode (O(1))
- **Sub-binary sharing** – One encode, many readers with no memory copies
- **Compile-time code generation** – No runtime reflection overhead
- **Fixed-size optimization** – Known field offsets for O(1) access

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
  use GridCodec

  defcodec do
    field :user_id, :uuid
    field :score, :u64, presence: :required
    field :level, :u32
    field :active, :bool
    field :created_at, :timestamp_us
  end
end

# Encode
binary = MyApp.Events.UserCreated.encode(%{
  user_id: :crypto.strong_rand_bytes(16),
  score: 1500,
  level: 42,
  active: true,
  created_at: System.system_time(:microsecond)
})

# Direct field access (no full decode!)
env = MyApp.Events.UserCreated.wrap(binary)
score = MyApp.Events.UserCreated.get(env, :score)
# => 1500

# Full decode when needed
{:ok, decoded} = MyApp.Events.UserCreated.decode(binary)
```

## Documentation

Full documentation is available via ExDoc:

```bash
mix docs
open doc/index.html
```

Key modules:

- `GridCodec` – Main DSL for defining codecs
- `GridCodec.Envelope` – Wrapper for direct field access
- `GridCodec.Group` – Repeating groups (variable-length collections)
- `GridCodec.Dispatch` – Multi-message routing by template ID
- `GridCodec.Type` – Behaviour for custom types

## Benchmarks

See the interactive Livebooks in `livebooks/` for detailed performance comparisons:

```bash
# Install livebook if needed
mix escript.install hex livebook

# Start server
livebook server
```

Or run a quick benchmark:

```bash
mix run benchmarks/quick_bench.exs
```

## License

MIT License – see [LICENSE](LICENSE) for details.
