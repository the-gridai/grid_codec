# Schema Evolution

GridCodec supports backward-compatible schema evolution using the `:since` field
option and SBE-style `block_length` padding. Older binaries are decoded correctly
by newer codecs — new fields come back as `nil`.

## Recommended Versioning Model

For an existing message type, keep the same wire identity:

- keep the same `schema_id`
- keep the same `template_id`
- bump `version` when the schema changes

Then evolve the layout additively:

- append new fixed fields at the end and mark them with `since: <new_version>`
- add new groups or var-data fields in a backward-compatible way
- deploy new readers before new writers

Do **not** treat `version` as part of the dispatch key. In GridCodec, dispatch
always happens by `{schema_id, template_id}` first, and version compatibility is
checked only after the codec is selected.

Today the evolution mechanism is built around:

- `version` on the codec / struct
- `since` on newly added fields
- breaking-change detection via `mix grid_codec.breaking`

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

`since` is the main way to express "this field did not exist before version N".

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
- **Keep the same `{schema_id, template_id}` and bump `version`** when evolving
  an existing message shape compatibly.
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
- **Using the same `{schema_id, template_id}` for two codecs with different
  versions at the same time** as if version were part of identity. It is not.

## If You Need To Remove A Field

Removing a field is a wire-breaking change. Version bumps and `since` do not
make removal safe.

Preferred options:

1. Keep the field on the wire and stop using it in application code.
2. Keep decoding old data, but stop populating the field for new writes if that
   is semantically acceptable.
3. If the wire shape truly must drop the field, define a new message shape with
   a new `template_id` and migrate producers/consumers explicitly.

In other words: use `version` + `since` for additive evolution, not for wire
subtraction.

## If You Need To Change A Field Type

Changing a field's type or wire size is also a wire-breaking change.

Examples:

- `:u32` → `:u64`
- `:string16` → `:string32`
- changing `wire_format:`
- changing parameterized type options that affect representation

Preferred options:

1. Add a new field with the new type at the end, mark it with `since: <version>`,
   and keep the old field for compatibility.
2. Migrate application code to read/write the new field.
3. Once old data/producers are gone, treat removal of the old field as a
   separate breaking change and, if necessary, introduce a new `template_id`.

This "add new, migrate, then optionally replace the message type" approach is
the safe way to evolve field types in GridCodec.

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

## Breaking Checker Rule Reference

`mix grid_codec.breaking` reports rules in two categories:

- `:wire` — binary compatibility and `.grid` compatibility
- `:source` — Elixir/API compatibility for generated structs and types

### Wire Rules

| Rule | Meaning | Typical fix |
|------|---------|-------------|
| `WIRE_SYNTAX_VERSION_CHANGED` | `.grid` `@syntax` changed | Upgrade parsers together or keep syntax stable |
| `WIRE_STRUCT_REMOVED` | Struct definition removed | Keep struct or introduce migration/new message type |
| `WIRE_TEMPLATE_ID_CHANGED` | `template_id` changed for existing struct | Keep `template_id` stable for same wire message |
| `WIRE_FIELD_REMOVED` | Field removed from struct | Keep field or create new message type |
| `WIRE_FIELD_REORDERED` | Fixed field order changed | Restore original order |
| `WIRE_FIELD_WIRE_FORMAT_CHANGED` | `wire_format` changed | Treat as type migration; add a new field instead |
| `WIRE_FIELD_SINCE_CHANGED` | `since` metadata changed | Keep original introduction version |
| `WIRE_FIELD_PRESENCE_CHANGED` | Presence mode changed | Avoid changing null/constant/required wire semantics in place |
| `WIRE_FIELD_CONSTANT_VALUE_CHANGED` | Constant field value changed | Introduce new field or new message type |
| `WIRE_FIELD_TYPE_PARAMS_CHANGED` | Parameterized type options changed | Treat as wire change; add a new field instead |
| `WIRE_FIELD_TYPE_CHANGED` | Field type changed incompatibly | Add a new field with `since`, migrate callers |
| `WIRE_GROUP_REMOVED` | Group removed | Keep group or create new message type |
| `WIRE_GROUP_FIELD_REMOVED` | Field removed from a group entry | Keep field or introduce a new message type |
| `WIRE_GROUP_FIELD_TYPE_CHANGED` | Group field type changed | Add a new field or new group/message shape |
| `WIRE_GROUP_FIELD_REORDERED` | Group field order/name changed incompatibly | Restore original group layout |
| `WIRE_BATCH_REMOVED` | Batch removed | Keep batch or create new message type |
| `WIRE_BATCH_STRATEGY_CHANGED` | Batch encoding strategy changed | Treat as new wire type; keep strategy stable |
| `WIRE_BATCH_TYPE_REMOVED` | Type removed from batch `any_of` | Keep old type or create a new batch/message type |
| `WIRE_BATCH_TYPE_REORDERED` | `any_of` order changed, which changes tags | Keep original order |
| `WIRE_ENUM_UNDERLYING_CHANGED` | Enum backing integer type changed | Keep underlying type stable |
| `WIRE_ENUM_VALUE_REMOVED` | Enum value removed | Keep old value for compatibility |
| `WIRE_ENUM_VALUE_CHANGED` | Enum integer changed | Keep original assigned integer |
| `WIRE_PREFIXED_ID_TAG_CHANGED` | `PrefixedId` tag byte changed | Keep tag stable; create a new type if needed |
| `WIRE_CHAR_ARRAY_LENGTH_CHANGED` | `CharArray` length changed | Create a new type/field instead |
| `WIRE_BITSET_UNDERLYING_CHANGED` | Bitset backing type changed | Keep underlying type stable |
| `WIRE_BITSET_FLAG_REMOVED` | Bitset flag removed | Keep old bit positions for compatibility |
| `WIRE_BITSET_FLAG_VALUE_CHANGED` | Bit position changed | Keep original assigned bit |

### Source Rules

| Rule | Meaning | Typical fix |
|------|---------|-------------|
| `SOURCE_SCHEMA_ID_CHANGED` | Schema namespace changed | Keep schema ID stable or plan a migration |
| `SOURCE_STRUCT_RENAMED` | Struct renamed with same `template_id` | Update consumers or keep public name stable |
| `SOURCE_FIELD_RENAMED` | Field renamed with same position/type | Update callers or keep old field name |
| `SOURCE_FIELD_DEFAULT_CHANGED` | Default value changed | Update callers and release notes |
| `SOURCE_FIELD_MADE_REQUIRED` | Field became required | Coordinate caller updates |
| `SOURCE_ENUM_RENAMED` | Enum renamed with same meaning | Update consumer code |
| `SOURCE_ENUM_VALUE_RENAMED` | Enum atom renamed at same integer | Update pattern matches and callers |
| `SOURCE_TYPE_RENAMED` | Composite type renamed | Update references/imports |
| `SOURCE_PREFIXED_ID_PREFIX_CHANGED` | `PrefixedId` string prefix changed | Update callers/storage expectations, even if wire tag is unchanged |
