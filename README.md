# GridCodec

[![CI](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml/badge.svg)](https://github.com/Spectral-Finance/grid_codec/actions/workflows/ci.yml)

High-performance binary codec for BEAM/Elixir with zero-copy field access.

## Features

- **Zero-copy field access** - Read fields directly from binary without full decode
- **Sub-binary sharing** - One encode, many readers with no memory copies  
- **Compile-time code generation** - No runtime reflection overhead
- **Fixed-size optimization** - Known field offsets for O(1) access
- **Repeating groups** - Variable-length collections with lazy iteration
- **Multiple string types** - string8 (u8), string16 (u16), string32 (u32) prefixes
- **Composite types** - Decimal, timestamps (microseconds/nanoseconds)
- **Field optionality** - Required, optional, and constant fields
- **Enum and Bitset** - Named variants and multiple-value flags
- **Pattern matching** - Elixir record-style matching on binary data
- **Modular type system** - Extensible via custom type modules

## Benchmark Results

GridCodec vs JSON (Jason) vs MessagePack (Msgpax) for a typical event message:

| Metric | GridCodec | JSON | MessagePack |
|--------|-----------|------|-------------|
| **Binary size** | 46 bytes | 153 bytes (3.3x) | 113 bytes (2.5x) |
| **Encode** | 118 ns | 916 ns (7.8x slower) | 825 ns (7x slower) |
| **Decode** | 28 ns | 1015 ns (36x slower) | 390 ns (14x slower) |
| **Field access** | 11 ns | 963 ns (90x slower) | 413 ns (39x slower) |
| **Memory (encode)** | 152 B | 1.5 KB (10x) | 1.2 KB (8x) |

Run benchmarks: `MIX_ENV=test mix run benchmarks/encode_decode_benchmark.exs`

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
event = %{
  user_id: :crypto.strong_rand_bytes(16),
  score: 1500,
  level: 42,
  active: true,
  created_at: System.system_time(:microsecond)
}
binary = MyApp.Events.UserCreated.encode(event)
# => <<...37 bytes...>>

# Zero-copy field access (no full decode!)
env = MyApp.Events.UserCreated.wrap(binary)
score = MyApp.Events.UserCreated.get(env, :score)
# => 1500

# Full decode when needed
{:ok, decoded} = MyApp.Events.UserCreated.decode(binary)
# => {:ok, %{user_id: <<...>>, score: 1500, ...}}
```

## Pattern Matching

GridCodec generates Elixir record-style pattern matching macros:

```elixir
defmodule MyApp.Events.Message do
  use GridCodec

  defcodec do
    field :id, :u64
    field :type, :u8
    field :payload, :u64
  end
end

# Use in case/function heads
require MyApp.Events.Message, as: Message

case binary do
  Message.match(type: 1, payload: p) when p > 100 ->
    IO.puts("High-priority message: #{p}")
    
  Message.match(type: 2) ->
    IO.puts("Status update")
    
  _ ->
    IO.puts("Unknown message")
end

# Or in function clauses
def handle(Message.match(type: 1, id: id)), do: {:command, id}
def handle(Message.match(type: 2, id: id)), do: {:query, id}
```

## Wire Format

GridCodec messages are laid out in three sections:

```
┌─────────────────────────────────────────────────────────┐
│ Fixed Block                                             │
│   All fixed-size fields in declaration order            │
├─────────────────────────────────────────────────────────┤
│ Groups Section                                          │
│   Header (4 bytes) + Entries for each group             │
├─────────────────────────────────────────────────────────┤
│ Var-Data Section                                        │
│   Length-prefixed strings/bytes                         │
└─────────────────────────────────────────────────────────┘
```

## Field Types

### Fixed-Size Types

| Type | Size | Null Sentinel | Description |
|------|------|---------------|-------------|
| `:u8` | 1 | 255 | Unsigned 8-bit |
| `:u16` | 2 | 65535 | Unsigned 16-bit |
| `:u32` | 4 | 4294967295 | Unsigned 32-bit |
| `:u64` | 8 | 2^64-1 | Unsigned 64-bit |
| `:i8` | 1 | -128 | Signed 8-bit |
| `:i16` | 2 | -32768 | Signed 16-bit |
| `:i32` | 4 | -2^31 | Signed 32-bit |
| `:i64` | 8 | -2^63 | Signed 64-bit |
| `:f32` | 4 | NaN | IEEE 754 single |
| `:f64` | 8 | NaN | IEEE 754 double |
| `:uuid` | 16 | zeros | Binary UUID |
| `:bool` | 1 | 255 | Boolean (0=false, 1+=true, 255=nil) |

### Composite Types

| Type | Size | Description |
|------|------|-------------|
| `:decimal` | 9 | High-precision decimal (i64 mantissa + i8 exponent) |
| `:timestamp_us` | 8 | Microseconds since epoch (i64) |
| `:timestamp_ns` | 8 | Nanoseconds since epoch (i64) |

### Variable-Size Types

| Type | Prefix | Max Size | Description |
|------|--------|----------|-------------|
| `:string` / `:string16` | u16 | 65535 | UTF-8 string (default) |
| `:string8` | u8 | 255 | Short string |
| `:string32` | u32 | ~4GB | Large text |

## Field Optionality

```elixir
defcodec do
  # Optional (default) - can be nil, uses null sentinel
  field :name, :string

  # Required - raises ArgumentError if nil
  field :score, :u64, presence: :required

  # Constant - always encoded/decoded as this value
  field :version, :u8, presence: :constant, value: 1

  # Optional with default - uses default when nil during encode
  field :flags, :u8, default: 0
end
```

## Enum Type

```elixir
defmodule MyApp.Types.Status do
  use GridCodec.Types.Enum, type: :u8

  defenum do
    value :pending, 0
    value :active, 1
    value :completed, 2
  end
end

defmodule MyCodec do
  use GridCodec, types: [status: MyApp.Types.Status]

  defcodec do
    field :task_status, :status
  end
end
```

## Bitset Type (Multiple Values)

```elixir
defmodule MyApp.Types.Permissions do
  use GridCodec.Types.Bitset, size: :u8

  flag :read, 0
  flag :write, 1
  flag :execute, 2
  flag :admin, 3
end

defmodule MyCodec do
  use GridCodec, types: [perms: MyApp.Types.Permissions]

  defcodec do
    field :user_perms, :perms
  end
end

# Encode/decode as MapSet
data = %{user_perms: MapSet.new([:read, :write])}
```

## Repeating Groups

Groups enable encoding variable-length collections of fixed-size entries:

```elixir
defmodule EventBatch do
  use GridCodec

  defp encode_item(%{id: id, value: v}), do: <<id::little-64, v::little-32>>
  defp decode_item(<<id::little-64, v::little-32>>), do: {:ok, %{id: id, value: v}}

  defcodec do
    field :batch_id, :uuid
    field :timestamp, :timestamp_us

    group :items, entry_encoder: &encode_item/1, entry_decoder: &decode_item/1 do
      field :id, :u64
      field :value, :u32
    end
  end
end

# Decode and iterate lazily
{:ok, batch} = EventBatch.decode(binary)

batch.items
|> GridCodec.Group.stream()
|> Stream.filter(&(&1.value > 100))
|> Enum.take(10)
```

Group wire format:
```
┌────────────────────────┬────────────────────────┐
│  blockLength (u16 LE)  │  numInGroup (u16 LE)   │
└────────────────────────┴────────────────────────┘
│  Entry[0] ... Entry[N-1]                        │
└─────────────────────────────────────────────────┘
```

## Message Framing and Dispatch

For systems with multiple message types, use framing and dispatch:

```elixir
# Define codecs with template_id
defmodule MyApp.Events.Created do
  use GridCodec, template_id: 1, schema_id: 100, version: 1

  defcodec do
    field :id, :uuid
    field :name, :string16
  end
end

defmodule MyApp.Events.Updated do
  use GridCodec, template_id: 2, schema_id: 100, version: 1

  defcodec do
    field :id, :uuid
    field :value, :u64
  end
end

# Define dispatch table (validates at compile time)
defmodule MyApp.Events.Dispatch do
  use GridCodec.Dispatch

  codecs [
    MyApp.Events.Created,
    MyApp.Events.Updated
  ]
end

# Encode with header (includes template_id)
binary = MyApp.Events.Created.encode!(%{id: uuid, name: "test"})

# Dispatch automatically routes to correct decoder
{:ok, data, MyApp.Events.Created} = MyApp.Events.Dispatch.decode(binary)
```

## Configuration

```elixir
defmodule MyCodec do
  use GridCodec, 
    version: 1,       # Schema version for evolution
    endian: :little,  # :little or :big byte order
    align: true       # Enable field alignment for performance
  
  defcodec do
    field :id, :u64
    field :name, :string
  end
end
```

## Zero-Copy Fan-Out

Ideal for Phoenix.PubSub broadcasts:

```elixir
# Publisher encodes once
binary = MyEvent.encode(data)
env = MyEvent.wrap(binary)

# Broadcast the envelope (binary reference, not copy)
Phoenix.PubSub.broadcast(MyApp.PubSub, "events", {:event, env})

# N subscribers receive the same binary reference
def handle_info({:event, env}, state) do
  # O(1) field access without full decode
  if MyEvent.get(env, :user_id) == state.user_id do
    {:ok, event} = GridCodec.Envelope.decode(env)
    # Process event...
  else
    # Skip without decoding - zero cost!
  end
  {:noreply, state}
end
```

## Custom Types

Implement the `GridCodec.Type` behaviour for custom types:

```elixir
defmodule MyApp.Types.Counter do
  @behaviour GridCodec.Type

  @impl true
  def size, do: 8

  @impl true
  def alignment, do: 8

  @impl true
  def null_value, do: -9_223_372_036_854_775_808

  @impl true
  def encode_ast(field_name, default, endian, data_var) do
    quote do
      value = Map.get(unquote(data_var), unquote(field_name), unquote(default))
      <<value::little-signed-64>>
    end
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var)::little-signed-64
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    quote do
      <<_::binary-size(unquote(offset)), value::little-signed-64, _::binary>> =
        unquote(payload_var)
      value
    end
  end
end

# Use in codec
defmodule MyCodec do
  use GridCodec, types: [counter: MyApp.Types.Counter]

  defcodec do
    field :hits, :counter
  end
end
```

## API Reference

### Codec Module (generated)

| Function | Description |
|----------|-------------|
| `encode(map)` | Encode map to binary |
| `decode(binary)` | Decode binary to `{:ok, map}` |
| `encode!(map)` | Encode with header (for dispatch) |
| `decode!(binary)` | Decode with header validation |
| `wrap(binary)` | Wrap binary in envelope for zero-copy access |
| `get(envelope, field)` | Get field from envelope (O(1) for fixed types) |
| `match(fields)` | Pattern match macro (requires `require`) |
| `block_length()` | Return fixed block size in bytes |
| `__schema__()` | Return schema metadata |

### GridCodec.Envelope

| Function | Description |
|----------|-------------|
| `wrap(binary, codec)` | Create envelope |
| `get(envelope, field)` | Get field value |
| `get_many(envelope, fields)` | Get multiple fields |
| `decode(envelope)` | Full decode to map |
| `binary(envelope)` | Get raw binary |
| `byte_size(envelope)` | Get binary size |

### GridCodec.Group

| Function | Description |
|----------|-------------|
| `encode(entries, encoder_fn)` | Encode list of entries |
| `parse(binary, decoder_fn, opts)` | Parse group from binary |
| `count(group)` | Get entry count (O(1)) |
| `get_entry(group, index)` | Get entry at index (O(1)) |
| `stream(group)` | Lazy stream over entries |
| `map(group, fun)` | Map over entries |
| `reduce(group, acc, fun)` | Reduce over entries |
| `to_list(group)` | Decode all entries |

### GridCodec.Dispatch

| Function | Description |
|----------|-------------|
| `decode(binary)` | Route and decode by template_id |
| `wrap(binary)` | Route and wrap for zero-copy |
| `lookup(schema_id, template_id)` | Get codec for message type |
| `list_codecs()` | List all registered codecs |

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Create a Pull Request
