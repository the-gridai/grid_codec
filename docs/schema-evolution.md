# Schema Evolution

GridCodec supports backward-compatible schema evolution using the `:since` field
option and SBE-style `block_length` padding. Older binaries are decoded correctly
by newer codecs — new fields come back as `nil`.

## How It Works

Every encoded message carries an 8-byte header with `block_length` (the size of
the fixed-field block at encode time) and `version`. When a newer codec decodes
an older binary:

1. The decoder reads `block_length` from the header.
2. If the binary's fixed block is shorter than the current codec expects, the
   missing bytes are filled with precomputed null sentinels.
3. New fields decode as `nil`. Existing fields decode normally.
4. Variable-length fields (strings) and groups after the fixed block are
   unaffected — the decoder splits at the header's `block_length`, not the
   codec's current length.

This happens automatically. No custom migration code is needed.

## The `:since` Option

Mark fields that were added after the initial schema version:

```elixir
defmodule MyApp.Aggregates.Account do
  use GridCodec.Struct, template_id: 1, schema_id: 200, version: 3

  defcodec do
    field :account_id, :uuid
    field :balance, :decimal
    field :status, :u8
    field :risk_score, :u32, since: 2
    field :tier, :u8, since: 3
  end
end
```

`:since` fields must be declared **after** all earlier-version fields in the
fixed block. The compiler enforces this at compile time — out-of-order `:since`
values raise a `CompileError`.

## Practical Example

Define a v1 codec and a v2 codec with the same `template_id` and `schema_id`:

```elixir
# v1 — deployed first
defmodule Events.OrderPlaced do
  use GridCodec.Struct, template_id: 10, schema_id: 100, version: 1

  defcodec do
    field :order_id, :uuid
    field :price, :decimal
  end
end

# v2 — deployed later, adds quantity
defmodule Events.OrderPlaced do
  use GridCodec.Struct, template_id: 10, schema_id: 100, version: 2

  defcodec do
    field :order_id, :uuid
    field :price, :decimal
    field :quantity, :u32, since: 2
  end
end
```

A v1 binary decoded by v2 code:

```elixir
{:ok, order} = Events.OrderPlaced.decode(v1_binary)
order.order_id  #=> <<...>>   (preserved)
order.price     #=> #Decimal<100.50>  (preserved)
order.quantity  #=> nil        (not present in v1, padded with null sentinel)
```

Re-encoding produces a valid v2 binary:

```elixir
updated = %{order | quantity: 50}
{:ok, v2_binary} = Events.OrderPlaced.encode(updated)
```

## Schema Metadata

The `:since` values are available at runtime via `__schema__/0`:

```elixir
Events.OrderPlaced.__schema__().field_versions
#=> %{quantity: 2}
```

Fields without `:since` are not included (they are implicitly version 1).

## Safe Changes

These changes are backward-compatible (older binaries decode correctly):

- **Add optional fields at the end** with `:since` — they decode as `nil` from
  older binaries.
- **Add new message types** with a new `template_id`.
- **Add enum values** — existing values are unchanged, new ones only appear in
  newer binaries.
- **Add groups** — missing groups decode as empty.

## Breaking Changes

These require coordinated deployment or snapshot version bumping:

- **Changing a field's type or size** (e.g., `:u32` to `:u64`) — the byte
  offsets shift for all subsequent fields.
- **Reordering fixed fields** — binary layout changes.
- **Removing a field** — the decoder expects bytes that are no longer present.
- **Reusing a `template_id`** for a different message shape.

## Forward Compatibility

A **newer** binary decoded by **older** code is rejected at the header level:

```elixir
{:error, {:version_too_new, 2, 1}}
```

The generated `validate_header/1` check ensures `header.version <= codec.version`.
This prevents silent data corruption from unknown fields.

## Deployment Strategy

1. Deploy the new codec version to all **consumers** first. They can decode both
   old and new binaries.
2. Then deploy the new version to **producers**. New binaries are now written with
   the updated schema.
3. Old binaries in event stores or snapshot stores continue to decode correctly
   indefinitely.

For aggregate snapshots specifically: if you add a field with `:since`, existing
snapshots decode with `nil` for the new field. No replay needed. If you make a
breaking change (type change, reorder), bump `snapshot_version` in your Commanded
config to force a replay.
