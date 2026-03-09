# GridCodec

[![CI](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml/badge.svg)](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml)

High-performance binary codec for BEAM/Elixir with zero-copy field access.

## Features

- **Zero-copy field access** – Read fields directly from binary without full decode (O(1))
- **Sub-binary sharing** – One encode, many readers with no memory copies; `copy: true` option to detach when needed
- **Compile-time code generation** – No runtime reflection overhead
- **Struct-based API** – Natural Elixir structs with binary serialization
- **Validation & coercion** – `validate: true` with typed error reporting; `new/1` for coercion from external input
- **Repeating groups** – Fixed-size entry collections with lazy decode, random access, and parallel materialization
- **Heterogeneous batches** – `GridCodec.Batch` for ordered, typed sequences (`:padded_union` for O(1) access, `:typed_frames` for compact wire size)
- **Binary matchspecs** – `GridCodec.Match` for filtering with native guards and cross-field comparisons, no decode
- **Codec transcoding** – `GridCodec.Transcoder` for codec-to-codec conversion without intermediate structs
- **Schema evolution** – `.grid` declarative schema files, breaking change detection (21 wire + 8 source rules), `--check` CI modes
- **SQL generation** – PostgreSQL decode functions from GridCodec binaries stored as `bytea`
- **Telemetry** – Optional `[:grid_codec, :encode]` and `[:grid_codec, :decode]` event emission with PromEx integration
- **Auto-generated typespecs** – `t()`, `layout()`, and `framed_layout()` emitted by default

## Performance

Full pipeline (construct + validate + serialize):

| Operation | Latency | Memory | Wire size |
|-----------|---------|--------|-----------|
| `MyCodec.new_binary/1` | **345 ns** | 0.8 KB | 63 B |
| Ecto changeset + Jason | 4,142 ns | 7.1 KB | 170 B |

**12x faster, 9x less memory, 2.7x smaller on the wire.**

Single field access from binary without decoding:

| Method | Latency |
|--------|---------|
| `GridCodec.get/2` | **31 ns** |
| JSON decode + map access | 1,239 ns |

See [Performance Guide](docs/performance.md) for full benchmarks including
Protobuf, ETF, and MessagePack comparisons.

## Installation

Add `grid_codec` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:grid_codec, git: "https://github.com/Spectral-Finance/grid_codec.git", tag: "v0.25.0"}
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
    field :level, :u32, default: 0
    field :active, :bool
    field :created_at, :timestamp_us
  end
end

# Validated constructor with coercion
{:ok, user} = MyApp.Events.UserCreated.new(%{
  user_id: "550e8400-e29b-41d4-a716-446655440000",
  score: 1500,
  active: true,
  created_at: System.system_time(:microsecond)
})

# Encode
{:ok, binary} = MyApp.Events.UserCreated.encode(user)

# Zero-copy field access (no full decode!)
require MyApp.Events.UserCreated
score = MyApp.Events.UserCreated.get(binary, :score)
# => 1500

# Detach sub-binary to release original from memory
uuid = MyApp.Events.UserCreated.get(binary, :user_id, copy: true)

# Full decode when needed
{:ok, decoded} = MyApp.Events.UserCreated.decode(binary)

# Construct + validate + encode in one call
{:ok, binary} = MyApp.Events.UserCreated.new_binary(%{score: 1500, active: true, ...})

# Top-level dispatch (with framed binary)
{:ok, framed} = GridCodec.encode(user)
{:ok, decoded} = GridCodec.decode(framed)
```

## Field Types

### Fixed-Size Types

| Type | Size | Description |
|------|------|-------------|
| `:u8`, `:u16`, `:u32`, `:u64` | 1–8 | Unsigned integers |
| `:i8`, `:i16`, `:i32`, `:i64` | 1–8 | Signed integers |
| `:f32`, `:f64` | 4, 8 | IEEE 754 floats |
| `:uuid` | 16 | Binary UUID |
| `:uuid_string` | 16 | UUID with string coercion (dashed format in `new/1` and JSON) |
| `:bool` | 1 | Boolean |
| `:timestamp_us` | 8 | Microsecond timestamp (integer domain) |
| `:timestamp_ns` | 8 | Nanosecond timestamp (integer domain) |
| `:datetime_us` | 8 | Microsecond timestamp (DateTime domain) |
| `:datetime_ns` | 8 | Nanosecond timestamp (DateTime domain) |
| `:decimal` | 9 | Decimal (mantissa + exponent) |
| `:positive_decimal` | 8 | Non-negative decimal (unsigned mantissa) |
| `{:decimal, scale: N}` | 9 | Parameterized decimal with fixed scale |
| `MyApp.Types.Side` | 1 | Custom enum (see below) |
| `MyApp.Types.Flags` | N | Custom bitset (see below) |
| `{:char_array, N}` | N | Fixed-size null-padded byte string |

### Variable-Size Types

| Type | Prefix | Description |
|------|--------|-------------|
| `:string8` | u8 | Short strings (max 255 bytes) |
| `:string` / `:string16` | u16 | UTF-8 string (default) |
| `:string32` | u32 | Large text |

### Custom Enums

```elixir
defmodule MyApp.Types.Side do
  use GridCodec.Types.Enum, encoding: :u8, values: [buy: 1, sell: 2]
end
```

### Custom Bitsets

```elixir
defmodule MyApp.Types.Flags do
  use GridCodec.Types.Bitset, encoding: :u8, flags: [:urgent, :hidden, :system]
end
```

## Field Options

| Option | Description |
|--------|-------------|
| `presence: :required` | `new/1` enforces non-nil |
| `presence: :constant` | Excluded from struct; fixed value on wire |
| `value: "NYSE"` | Constant field value (with `presence: :constant`) |
| `default: 0` | Default for `new/1` and encode |
| `since: 2` | Version-gated field (null before this version) |
| `wire_format: :i64` | Override binary encoding (e.g., decimal encoded as i64) |
| `validate: true` | Enable pre-encode type validation (struct-level option) |
| `telemetry: true` | Emit telemetry events on encode/decode (struct-level option) |

```elixir
defcodec do
  field :price, {:decimal, scale: 8}, wire_format: :i64, presence: :required
  field :exchange, :string8, presence: :constant, value: "NYSE"
  field :notes, :string16, since: 2
end
```

## Groups

Groups encode repeating fixed-size entries with lazy decode and O(1) random access:

```elixir
defcodec do
  field :symbol, :string8

  group :fills do
    field :price, :u64
    field :quantity, :u32
    field :side, MyApp.Types.Side
  end
end

# After decode:
count = GridCodec.Group.count(decoded.fills)
{:ok, entry} = GridCodec.Group.get_entry(decoded.fills, 0)
entries = GridCodec.Group.to_list(decoded.fills)

# Parallel materialization for large multi-group codecs (>256KB)
[fills, trades] = GridCodec.Group.to_lists_parallel([decoded.fills, decoded.trades])
```

## Schema Evolution

GridCodec includes a schema evolution system for tracking and validating schema changes.

### Export schemas

The export generates a directory per `schema_id`, each with a `schema.grid` master
file (containing the schema block and `import` directives) plus individual files for
each struct and enum:

```bash
# Generate .grid files from compiled defcodec modules
mix grid_codec.export

# Verify .grid files are up to date (CI / pre-push)
mix grid_codec.export --check
```

Output structure:

```
priv/schemas/
  events/
    schema.grid              # master — schema block + imports
    order_created.grid       # individual struct
    order_side.grid          # individual enum
```

Configure schema directory names in your application config:

```elixir
# config/config.exs
config :my_app, :grid_codec,
  schemas: %{100 => "events", 99 => "bench"}
```

Unconfigured schema_ids default to `schema_{id}`. File paths are derived from the
struct's `name:` option (e.g., `"Namespace.EventName"` becomes `namespace/event_name.grid`).

### Detect breaking changes

```bash
# Compare current schemas against git baseline
mix grid_codec.breaking

# Override baseline ref
mix grid_codec.breaking --against origin/main

# Wire-only checks
mix grid_codec.breaking --category wire
```

Configure with `.grid_codec.exs`:

```elixir
[
  breaking: [
    schema_files: ["priv/schemas/**/*.grid"],
    against: "origin/main",
    category: :source,
    except: [:SOURCE_FIELD_DEFAULT_CHANGED]
  ]
]
```

The breaking change tool resolves `import` directives automatically, so it works with
both the new directory structure and legacy flat files. Rules: 21 WIRE (binary
compatibility) + 8 SOURCE (API compatibility). See the [Schema evolution guide](docs/schema-evolution.md) for details.

### Compile from `.grid` files

Point `grid_file:` at a master `schema.grid` — imports are resolved automatically:

```elixir
defmodule MyApp.Events.OrderCreated do
  use GridCodec.Struct, grid_file: "priv/schemas/events/schema.grid", struct: "OrderCreated"
end
```

## SQL Generation

Generate PostgreSQL functions that decode GridCodec `bytea` columns:

```bash
# Generate SQL
mix gridcodec.sql

# Verify SQL is up to date (CI / pre-push)
mix gridcodec.sql --check
```

```sql
-- After running the generated SQL:
SELECT (gridcodec.decode_ordercreated(data)).* FROM events;
SELECT gridcodec.decode('OrderCreated', data)->>'price' FROM events;
```

## Type-Aware Field Comparison

Compare fixed-size fields directly from encoded binaries without full decode:

```elixir
require MyCodec
spec = MyCodec.field(:price)

GridCodec.compare(binary, spec, :>, 1000)
GridCodec.compare_binaries(binary_a, spec, :<=, binary_b)
```

## Next Steps

1. **First codec** — [Getting Started](docs/getting-started.md): define a codec, encode/decode, zero-copy access
2. **Schemas** — [Schemas](docs/schemas.md): `.grid` schema syntax and code generation
3. **Evolution** — [Schema evolution](docs/schema-evolution.md): versioning, breaking change detection, safe rollout
4. **Filtering & transcoding** — [Binary filtering](docs/binary-filtering.md): matchspecs, cross-field guards, codec-to-codec transcoding, ETS patterns
5. **Performance** — [Performance](docs/performance.md): profiling and optimization
6. **Consumer integration** — [Consumer integration](docs/consumer-integration.md): using GridCodec as a dependency
7. **Troubleshooting** — [Troubleshooting](docs/troubleshooting.md): common issues and fixes

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
- `GridCodec.Batch` – Heterogeneous batches with strategy selection
- `GridCodec.Match` – Compile-time matchspec-like binary filtering
- `GridCodec.Transcoder` – Codec-to-codec field transcoding
- `GridCodec.Dispatch` – Multi-message routing by template ID
- `GridCodec.Type` – Behaviour for custom types
- `GridCodec.Binary` – Sub-binary lifecycle utilities (`detach/1`, `copy_field/1`)
- `GridCodec.BinaryInspector` – Binary diagnostics (header/layout/value inspection)
- `GridCodec.Json` – JSON interchange adapters (`to_map/from_map/to_json/from_json`)
- `GridCodec.SQL` – PostgreSQL decode function generation
- `GridCodec.Schema.Parser` – `.grid` schema file parser (with `import` resolution)
- `GridCodec.Schema.Formatter` – `.grid` file generation (master, struct, and enum files)
- `GridCodec.Breaking.Checker` – Breaking change detection engine
- `GridCodec.Telemetry.Metrics` – Pre-built metric definitions (Telemetry.Metrics + PromEx)

## Common Tasks

```bash
# Run all quality checks
mix check

# Run tests
mix test

# Build ExDoc docs
mix docs

# Generate .grid schema files
mix grid_codec.export

# Detect breaking schema changes
mix grid_codec.breaking

# Generate PostgreSQL decode functions
mix gridcodec.sql

# Verify generated files are up to date (CI)
mix gridcodec.sql --check
mix grid_codec.export --check

# Run profiler
./profile/run.sh
```

## Example App

For real-world usage examples and benchmarks:

```bash
cd example_app
mix deps.get
mix compile
mix run benchmarks/quick_bench.exs
mix run benchmarks/group_bench.exs
```

See `example_app/README.md` for details.

## Contributing

### Requirements

- Elixir 1.18+ (1.19+ recommended for progressive type system warnings)
- Erlang/OTP 26+ (28+ recommended)

We use [asdf](https://asdf-vm.com/) for version management. After installing asdf:

```bash
asdf install  # Installs versions from .tool-versions
```

### Development

```bash
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix test
mix dialyzer
```

### Publishing a release

1. Bump `@version` in `mix.exs` and add a `## [X.Y.Z] - YYYY-MM-DD` entry to `CHANGELOG.md`.
2. Regenerate baselines: `cd example_app && mix grid_codec.export`.
3. Run `mix check` (compile, format, credo, test, dialyzer).
4. Commit, tag, push: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.

### Code Quality

All PRs must pass CI, which runs:

1. **Compile** with `--warnings-as-errors`
2. **Format** check
3. **Credo** strict
4. **Tests** with property-based tests
5. **Dialyzer** static type analysis
6. **Breaking change detection** on `.grid` schema files

## License

MIT License – see [LICENSE](LICENSE) for details.
