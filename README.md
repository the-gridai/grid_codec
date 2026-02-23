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
require MyApp.Events.UserCreated
score = MyApp.Events.UserCreated.get(binary, :score)
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

## Type-Aware Field Comparison

You can compare fixed-size fields directly from encoded binaries without full decode:

```elixir
require MyCodec

spec = MyCodec.field(:price)

# Binary field vs literal
GridCodec.compare(binary, spec, :>, 1000)

# Same field across two binaries
GridCodec.compare(binary_a, spec, :<=, binary_b, rhs: :binary)
# or
GridCodec.compare_binaries(binary_a, spec, :<=, binary_b)

# Compile-time specialized macro on codec module
MyCodec.compare(binary_a, :price, :>, binary_b, rhs: :binary)
```

Operators: `:<`, `:<=`, `:>`, `:>=`, `:==`, `:!=`.

For domain-specific types like `:decimal`, comparisons use type-aware semantics.

## Documentation

Full documentation is available via ExDoc:

```bash
mix docs
open doc/index.html
```

Key modules:

- `GridCodec` – Top-level dispatch API
- `GridCodec.Struct` – DSL for defining struct codecs
- `GridCodec.Group` – Repeating groups (variable-length collections)
- `GridCodec.Dispatch` – Multi-message routing by template ID
- `GridCodec.Type` – Behaviour for custom types

Guides:

- `docs/getting-started.md` - First codec, encode/decode, zero-copy access
- `docs/schemas.md` - `.grid` schema syntax and usage
- `docs/schema-evolution.md` - Versioning and rollout guidance
- `docs/performance.md` - Profiling and optimization practices
- `docs/troubleshooting.md` - Common errors and fixes

## Common Tasks

```bash
# Run all quality checks
mix check

# Run tests only
mix test

# Build ExDoc docs
mix docs

# Run profiler
./profile/run.sh
```

## Example App

For real-world usage examples and benchmarks:

```bash
cd example_app
mix deps.get
mix compile
mix bench  # Run benchmarks
```

See `example_app/README.md` for details.

## Contributing

### Requirements

- Elixir 1.17+ (1.19+ recommended for progressive type system warnings)
- Erlang/OTP 26+ (28+ recommended)

We use [asdf](https://asdf-vm.com/) for version management. After installing asdf:

```bash
asdf install  # Installs versions from .tool-versions
```

### Development

```bash
# Install dependencies
mix deps.get

# Run all checks (compile, format, credo, test, dialyzer)
mix check

# Or run checks individually:
mix compile --warnings-as-errors  # Compile with strict warnings
mix format --check-formatted      # Check code formatting
mix credo --strict                # Static analysis
mix test                          # Run test suite
mix dialyzer                      # Type checking
```

### Code Quality

All PRs must pass `mix check`, which runs:

1. **Compile** with `--warnings-as-errors` – catches type warnings from Elixir's progressive type system
2. **Format** – ensures consistent code style
3. **Credo** – static analysis for code consistency
4. **Tests** – full test suite with property-based tests
5. **Dialyzer** – static type analysis

### Profiling

For performance profiling, see `AGENTS.md` and `profile/README.md`:

```bash
./profile/run.sh              # Full encode/decode profile
./profile/run.sh --mode=encode  # Encode only
```

## License

MIT License – see [LICENSE](LICENSE) for details.
