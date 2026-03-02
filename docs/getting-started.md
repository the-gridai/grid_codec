# Getting Started

This guide walks through the smallest useful GridCodec setup: define a codec,
encode/decode values, and use zero-copy field access.

## 1) Install

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:grid_codec, git: "https://github.com/Spectral-Finance/grid_codec.git"}
  ]
end
```

Then install dependencies:

```bash
mix deps.get
```

## 2) Define Your First Codec

```elixir
defmodule MyApp.Events.UserCreated do
  use GridCodec.Struct, template_id: 1, schema_id: 100

  defcodec do
    field :user_id, :uuid, presence: :required
    field :score, :u64
    field :name, :string16
    field :active, :bool
  end
end
```

## 3) Encode and Decode

```elixir
event = %MyApp.Events.UserCreated{
  user_id: :crypto.strong_rand_bytes(16),
  score: 1500,
  name: "alice",
  active: true
}

# Includes an 8-byte GridCodec header by default
binary = MyApp.Events.UserCreated.encode(event)

{:ok, decoded} = MyApp.Events.UserCreated.decode(binary)
```

## 4) Use Zero-Copy Field Access

```elixir
require MyApp.Events.UserCreated

score = MyApp.Events.UserCreated.get(binary, :score)
```

`get/2` avoids full struct decoding for fixed-size fields.

## 5) Use Top-Level Dispatch

```elixir
framed = GridCodec.encode(event)
{:ok, decoded} = GridCodec.decode(framed)
```

Top-level decode routes by header `{schema_id, template_id}`.

## 6) Compare Fields Without Full Decode

```elixir
spec = MyApp.Events.UserCreated.field(:score)

# Field vs literal value
GridCodec.compare(binary, spec, :>=, 1000)

# Field vs same field in another binary
GridCodec.compare(binary_a, spec, :>, binary_b, rhs: :binary)
```

## 7) Type Names for EventStore Integration

Every codec has a stable type name, accessible via `__type__/0`. By default it
is the full module path:

```elixir
MyApp.Events.UserCreated.__type__()
#=> "MyApp.Events.UserCreated"
```

Set the `:name` option for short, clean names:

```elixir
defmodule MyApp.Events.UserCreated do
  use GridCodec.Struct, template_id: 1, schema_id: 100, name: "user_created"

  defcodec do
    field :user_id, :uuid
    field :score, :u64
  end
end

MyApp.Events.UserCreated.__type__()
#=> "user_created"
```

Use `GridCodec.Registry.lookup_by_type/1` for reverse lookup:

```elixir
{:ok, MyApp.Events.UserCreated} = GridCodec.Registry.lookup_by_type("user_created")
```

This enables compact event type strings in EventStore/Commanded instead of full
Elixir module names.

## Next Steps

- See `docs/schemas.md` for `.grid` schema files.
- See `docs/schema-evolution.md` for `:since` and backward compatibility.
- See `docs/performance.md` for profiling and optimization.
- See `docs/troubleshooting.md` for common errors.
