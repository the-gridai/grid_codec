# Getting Started

This guide walks through the smallest useful GridCodec setup: define a codec,
encode/decode values, and use zero-copy field access.

## 1) Install

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:grid_codec, git: "https://github.com/the-gridai/grid_codec.git"}
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
{:ok, binary} = MyApp.Events.UserCreated.encode(event)

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
{:ok, framed} = GridCodec.encode(event)
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

## 8) Custom Types

### Enums

Define domain enums as standalone modules:

```elixir
defmodule MyApp.Types.OrderSide do
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value :buy
    value :sell
  end
end
```

Reference them directly as field types — no registration needed:

```elixir
defmodule MyApp.Events.OrderPlaced do
  use GridCodec.Struct, template_id: 2, schema_id: 100

  alias MyApp.Types.OrderSide

  defcodec do
    field :order_id, :uuid_string
    field :side, OrderSide
    field :price, :decimal
  end
end
```

Any module that implements the `GridCodec.Type` behaviour can be used as a field
type. The compiler detects it automatically at compile time.

### Bitsets

Pack multiple boolean flags into a single integer:

```elixir
defmodule MyApp.Types.Permissions do
  use GridCodec.Types.Bitset, size: :u8

  flag :read,    0
  flag :write,   1
  flag :admin,   2
end
```

### Fixed-Length Strings

For fields with a known maximum length (e.g., currency codes, ticker symbols):

```elixir
defmodule MyApp.Types.CurrencyCode do
  use GridCodec.Types.CharArray, length: 3
end

defmodule MyApp.Types.Symbol do
  use GridCodec.Types.CharArray, length: 8
end
```

### Parameterization

Custom types are parameterized at the **module definition**, not per-field. If you
need the same base type with different parameters, define separate modules:

```elixir
defmodule MyApp.Types.ShortName do
  use GridCodec.Types.CharArray, length: 16
end

defmodule MyApp.Types.LongDescription do
  use GridCodec.Types.CharArray, length: 256
end

defcodec do
  field :name, MyApp.Types.ShortName
  field :description, MyApp.Types.LongDescription
end
```

This keeps all type behavior resolved at compile time — no runtime dispatch.

## 9) Auto-Generated Typespecs

`use GridCodec.Struct` generates typespecs by default:

```elixir
@type t() :: %__MODULE__{}
@type layout() :: <<...>>          # payload (header: false)
@type framed_layout() :: <<...>>   # with GridCodec header
```

Disable this behavior with `generate_typespec: false`:

```elixir
defmodule MyApp.Events.UserCreated do
  use GridCodec.Struct, template_id: 1, schema_id: 100, generate_typespec: false

  defcodec do
    field :user_id, :uuid
    field :score, :u64
  end
end
```

For generic app specs where codec type is not known in advance, use top-level
GridCodec types:

```elixir
@spec publish(GridCodec.codec_data()) :: :ok
def publish(data), do: ...
```

## Constructors and Coercion

Every codec has a `new/1` constructor that handles coercion and validation:

```elixir
# Typed input
{:ok, event} = MyCodec.new(price: 100, active: true)

# String input from JSON — automatically coerced
{:ok, event} = MyCodec.new(%{"price" => "100", "active" => "true"})

# Direct to binary — no struct allocation (2.7x less memory)
{:ok, binary} = MyCodec.new_binary(%{"price" => "100", "active" => "true"})

# From existing struct — just validate + encode (128 bytes allocated)
{:ok, binary} = MyCodec.new_binary(existing_struct)
```

Enable `validate: true` to catch type errors before encoding:

```elixir
use GridCodec.Struct, template_id: 1, schema_id: 100, validate: true

# Out of range:
{:error, %GridCodec.ValidationError{code: :out_of_range}} =
  MyCodec.new(count: 5_000_000_000)  # exceeds u32 max

# Cast error:
{:error, %GridCodec.ValidationError{code: :cast_error}} =
  MyCodec.new(price: "not_a_number")
```

## Groups

Groups encode variable-length collections with fixed-size entries:

```elixir
defcodec do
  field :symbol, :uuid

  group :orders do
    field :price, :i64
    field :quantity, :u32
    field :side, MyApp.OrderSide  # custom enum types work in groups
  end
end
```

For reusable fixed-size entry structs, you can also declare a typed group:

```elixir
defmodule Reservation do
  use GridCodec.Struct, template_id: 10, schema_id: 100

  defcodec do
    field :reservation_id, :u64
    field :amount, :u64
    field :active, :bool
  end
end

defcodec do
  field :account_id, :u64
  group :reservations, of: Reservation
end
```

Use `wire_format:` to control the binary encoding while keeping the domain type:

```elixir
# Parameterized type with wire format override:
# Domain type: Decimal with 8 decimal places
# Wire format: i64 (8 bytes, faster than full decimal encoding)
field :price, {:decimal, scale: 8}, wire_format: :i64

# Works in groups too:
group :balances do
  field :user_id, :uuid
  field :amount, {:decimal, scale: 8}, wire_format: :i64
end
```

Decoded groups are lazy — entries are only materialized when accessed:

```elixir
{:ok, data} = MyCodec.decode(binary)
GridCodec.Group.count(data.orders)           # O(1), no decode
GridCodec.Group.get_entry(data.orders, 42)   # O(1) random access
GridCodec.Group.to_list(data.orders)         # materialize all entries

# Parallel decode for large groups (auto-thresholds at 256KB)
[balances, orders] = GridCodec.Group.to_lists_parallel([data.balances, data.orders])
```

Typed groups decode to `GridCodec.Group` values whose entries materialize as the
typed struct module:

```elixir
{:ok, account} = AccountCodec.decode(binary)
[%Reservation{} = reservation] = GridCodec.Group.to_list(account.reservations)
```

## Projection and Content Hash

Decode only the fields you need:

```elixir
{:ok, %{price: 100, side: :buy}} = MyCodec.decode_only(binary, [:price, :side])
```

For named alternate access paths over decoded groups and batches, use codec lookups:

```elixir
defcodec do
  group :reservations, of: Reservation

  lookups do
    lookup :reservations_by_id do
      from :reservations
      into :map
      key :reservation_id
    end
  end
end

{:ok, account} = MyCodec.decode(binary)
{:ok, reservations_by_id} = MyCodec.reservations_by_id(account)
```

Lookups are Elixir-side helpers only. They are computed on demand and are not
stored on the decoded struct or exported to `.grid`.

Deterministic content hash for deduplication:

```elixir
hash = MyCodec.content_hash(struct)  # SHA-256 of wire format
```

## Telemetry

Enable per-module or globally for encode/decode latency metrics:

```elixir
use GridCodec.Struct, telemetry: true, telemetry_min_duration: 10_000

# Or globally:
config :grid_codec, telemetry: true
```

See `GridCodec.Telemetry.Metrics` for PromEx/Prometheus integration and
the `grafana/grid_codec.json` dashboard.

## Next Steps

- See [Schemas](schemas.md) for `.grid` schema files.
- See [Schema evolution](schema-evolution.md) for `:since` and backward compatibility.
- See [Binary filtering](binary-filtering.md) for matchspecs, transcoding, and ETS patterns.
- See [Performance](performance.md) for profiling and optimization.
- See [Troubleshooting](troubleshooting.md) for common errors.
