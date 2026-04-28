# Schema Evolution

GridCodec supports backward-compatible fixed-block schema evolution using the
`:since` field option and SBE-style `block_length` padding. Older binaries are
decoded correctly by newer codecs when new fixed-block fields can be padded from
null sentinels or defaults.

## Recommended Versioning Model

For an existing message type, keep the same wire identity:

- keep the same `schema_id`
- keep the same `template_id`
- bump `version` when the schema changes

Then evolve the layout additively:

- append new fixed fields at the end and mark them with `since: <new_version>`
- add new groups in a backward-compatible way
- deploy new readers before new writers

Do **not** treat `version` as part of the dispatch key. In GridCodec, dispatch
always happens by `{schema_id, template_id}` first, and version compatibility is
checked only after the codec is selected.

Today the evolution mechanism is built around:

- `version` on the codec / struct
- `since` on newly added fields
- breaking-change detection via `mix grid_codec.breaking`

## Export Drift vs Breaking Changes

GridCodec keeps `.grid` files as generated artifacts. Two checks serve different
purposes and are usually run together:

- `mix grid_codec.export --check` verifies that checked-in `.grid` files exactly
  match the current code. It fails if a file is missing, stale, or unexpectedly
  present in the export directory.
- `mix grid_codec.breaking` compares the current schema snapshot to a baseline and
  reports semantic compatibility issues such as `WIRE_STRUCT_REMOVED`.

If you delete or rename a codec, `mix grid_codec.export --prune` removes orphaned
generated files before you commit the new baseline.

## How It Works

Every encoded message carries an 8-byte header with `block_length` (the size of
the fixed-field block at encode time) and `version`. When a newer codec decodes
an older binary:

1. The decoder reads `block_length` from the header.
2. If the binary's fixed block is shorter than the current codec expects, the
   missing bytes are filled with precomputed null sentinels.
3. Compatible new fixed-block fields decode as `nil` or as their declared
   `:default`. Existing fields decode normally.
4. Existing variable-length fields (strings) and groups after the fixed block
   are unaffected — the decoder splits at the header's `block_length`, not the
   codec's current length. Newly added variable-length fields are different:
   historical payloads have no tail bytes for their length prefix.

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

- **Add optional fixed-block fields at the end** with `:since` — they decode as
  `nil` from older binaries.
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
- **Appending a `:required` fixed-block field without a `:default`** — the
  decoder now rejects historical events with
  `{:error, {:required_field_absent, field}}` because the null-sentinel
  padding would otherwise surface as `nil`, violating the typespec. Declare
  a `:default` on the new field to make the append safe (old events decode
  with the default). See below.
- **Appending a variable-length field** — historical events do not include the
  new field's length prefix or payload bytes, and the current decoder does not
  synthesize missing var-data. Introduce a new message type or use a
  compatibility shim at the deserializer boundary.
- **Reusing a `template_id`** for a different message shape.
- **Using the same `{schema_id, template_id}` for two codecs with different
  versions at the same time** as if version were part of identity. It is not.

## Safely Appending a Required Field

The fixed-block null-padding path that makes appending new fixed fields
backward-compatible has a hazard for `:required` fields: when a historical
(shorter) payload is decoded by a newer codec, the decoder pads the missing
trailing bytes from a precomputed block synthesized from each field's **type
null sentinel** — zero bytes for integers, NaN for floats, `i64_min` for
decimals backed by i64, an empty binary pattern for fixed-size strings, etc.

For a `:required` field, that sentinel would decode as `nil`, which violates
the declared typespec (the field's Elixir type forbids `nil`) and breaks
round-tripping (`encode/1` rejects `nil` for `:required`). To prevent that,
the decoder now enforces `:required` at read time:

- If the field declares a `:default`, the decoder **substitutes the default**
  whenever the wire value would otherwise be `nil`. The struct is fully
  populated and round-trips cleanly through `encode/1`.
- If the field has no `:default`, the decoder returns
  **`{:error, {:required_field_absent, field}}`**. The historical event
  cannot be materialized without code changes.

This applies uniformly across every built-in type and every custom type
whose `decode_value_ast/1` maps its null sentinel to `nil`. Custom types
that never produce `nil` (no null mapping) are unaffected because the
check's `nil` branch is unreachable by construction.

### Recipes for appending a required field

1. **Declare a `:default` alongside `:required`** (recommended for additive
   evolution):

   ```elixir
   field :counter, :u32, presence: :required, default: 0
   field :price, {:decimal, scale: 8}, wire_format: :i64,
         presence: :required, default: Decimal.new("0.00000000")
   ```

   Historical events decode with the default. New events carry the real
   value. Encode/decode round-trip.

2. **Use `presence: :optional` (or the `?` shorthand) for fixed-block fields**
   when `nil` is a sensible meaning for "field wasn't there yet":

   ```elixir
   field :counter, :u32, presence: :optional
   # or equivalently:
   field :counter?, :u32
   ```

   Historical events decode with `counter = nil`. Callers must handle `nil`
   explicitly, which matches the typespec.

3. **Introduce a new message type** with a new `template_id` when the
   semantic break is large enough that old and new events are meaningfully
   different shapes.

### What `:since` does and doesn't do

`:since` is metadata — it records the version that introduced the field and
lets `mix grid_codec.breaking` reason about the change. It does **not**
change the decoder's null-padding or required-enforcement behavior. Use
`:since` in combination with one of the recipes above, not as a substitute
for them.

### How the breaking checker catches this

`mix grid_codec.breaking` reports `WIRE_FIELD_ADDED_REQUIRED` for any
appended `:required` fixed-block field **without a `:default`**. Adding a
`:default` suppresses the warning (and makes the append actually safe).
`:optional` fixed-block fields and `:constant` value fields do not trigger.
Variable-length additions report `WIRE_VAR_FIELD_ADDED` because historical
events have no var-data bytes for the new field.

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

1. Deploy the new codec version to all **consumers** first. For compatible
   changes, they can decode both old and new binaries.
2. Then deploy the new version to **producers**. New binaries are now written with
   the updated schema.
3. For compatible changes, old binaries in event stores or snapshot stores
   continue to decode correctly indefinitely.

For aggregate snapshots specifically: if you add a compatible fixed-block field
with `:since`, existing snapshots decode with `nil` or the declared default for
the new field. No replay needed. If you make a breaking change (type change,
var-data append, reorder), bump `snapshot_version` in your Commanded config to
force a replay.

## Test coverage in this repo

Cross-version scenarios (`encode` with an older codec module, `decode` with a
newer one) live in `test/grid_codec/schema_evolution_test.exs`, backed by shared
fixtures in `test/support/z_schema_evolution_fixtures.ex` (compiled with the test
app so async tests can reference them safely). That suite covers `:required` +
`:since`, `field_defaults`, groups, `typed_frames` and `padded_union` batches,
scalar `group ... of:` lists, appended `:constant` fields, `wire_format: :i64`
decimals, custom `Enum` types, lazy `Group.stream/1` error propagation, and
payload-only decode boundaries.

`test/grid_codec/schema_evolution_generative_test.exs` runs StreamData
properties over many random valid V1 payloads for several of those fixtures.

`test/grid_codec/required_fields_invariant_test.exs` property-checks that any
successful same-version `decode` never leaves a top-level `:required` field as
`nil` (and materializes groups / batch entries to check nested required fields
where generators apply). The `example_app` includes
`test/example_app/schema_evolution_migration_test.exs` as a consumer-style
migration smoke test.

Payload-only binaries (`encode(..., header: false)` / `decode(..., header: false)`)
cannot participate in the same `:since` padding path as full frames: the
decoder learns the writer’s fixed-block size from `GridCodec.Header.block_length`,
so cross-version evolution tests should use the default headered encode/decode.

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
| `WIRE_FIELD_ADDED_REQUIRED` | `:required` fixed-block field appended without a `:default` — historical events decode to `{:error, {:required_field_absent, field}}` | Declare a `:default`, or use `presence: :optional`, or introduce a new message type |
| `WIRE_VAR_FIELD_ADDED` | Variable-length field added — historical events do not have bytes for the new length prefix/payload | Introduce a new message type or add a deserializer compatibility shim |
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
