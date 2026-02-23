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

## Next Steps

- See `docs/schemas.md` for `.grid` schema files.
- See `docs/performance.md` for profiling and optimization.
- See `docs/troubleshooting.md` for common errors.
