# PostgreSQL SQL Generation

GridCodec can generate PostgreSQL functions that decode framed binaries stored
in `bytea` columns. This is useful for event journals and analytical tables that
keep the GridCodec binary as their source of truth while still supporting
indexed envelope queries and targeted payload inspection.

## Generate the catalog

Compile the application first so every codec is registered, then generate the
SQL artifact:

```bash
mix gridcodec.sql
mix gridcodec.sql --check
```

The default output is `priv/gridcodec_functions.sql`. Use `--output` when a
consumer keeps generated SQL with a particular Repo or schema:

```bash
mix gridcodec.sql --output priv/repo/sql/gridcodec_functions.sql
```

Application code can also select an explicit catalog:

```elixir
modules = [MyApp.Events.OrderCreated, MyApp.Events.RiskScored]
sql = GridCodec.SQL.generate_all(modules)
File.write!("priv/repo/sql/gridcodec_functions.sql", sql)
```

An explicit list is preferable in migrations because it is deterministic and
does not depend on which modules happen to be loaded in the migration runtime.

## Generated database API

The catalog creates:

- `gridcodec.read_header(bytea)` for the 8-byte GridCodec header.
- Primitive readers such as `gridcodec.read_u64/2`,
  `gridcodec.read_uuid_nullable/2`, and `gridcodec.read_string16/2`.
- `gridcodec.decode_<type>(bytea)` typed table functions.
- `gridcodec.decode_<type>_json(bytea)` per-codec JSONB functions.
- `gridcodec.decode(type_name, bytea)` as the universal JSONB dispatcher.
- `gridcodec_enums.*` lookup tables for registered enum types.

For an event envelope:

```sql
SELECT e.event_id, decoded.*
FROM events AS e
CROSS JOIN LATERAL gridcodec.decode_ordercreated(e.data) AS decoded
WHERE e.event_type = 'OrderCreated';
```

The universal dispatcher is convenient for mixed streams:

```sql
SELECT
  event_id,
  gridcodec.decode(event_type, data) AS payload
FROM events
WHERE stream_uuid = 'user:123'
ORDER BY stream_version;
```

Filter by indexed envelope columns before invoking a decoder. PostgreSQL cannot
use a normal B-tree index for values that exist only inside an arbitrary
function call:

```sql
SELECT decoded.payload->>'country_code'
FROM events AS e
CROSS JOIN LATERAL (
  SELECT gridcodec.decode(e.event_type, e.data) AS payload
) AS decoded
WHERE e.schema_id = 2
  AND e.template_id = 7
  AND e.created_at >= now() - interval '1 day';
```

## Fixed repeating groups

Standard fixed groups use a four-byte wire header:

```text
blockLength (u16 LE) | numInGroup (u16 LE) | entries
```

Typed decoders expose each fixed group as a `jsonb` column. JSON decoders expose
the same data as an ordered JSON array. Empty groups decode to `[]`.

```elixir
defmodule MyApp.Reservation do
  use GridCodec.Struct, template_id: 10, schema_id: 1

  defcodec do
    field :reservation_id, :u64
    field :amount, :u64
    field :active, :bool
  end
end

defmodule MyApp.AccountSnapshot do
  use GridCodec.Struct, template_id: 11, schema_id: 1

  alias MyApp.Reservation

  defcodec do
    field :account_id, :u64
    group :reservations, of: Reservation
    field :source, :string16
  end
end
```

```sql
SELECT d.account_id, d.reservations, d.source
FROM snapshots AS s
CROSS JOIN LATERAL gridcodec.decode_myapp_accountsnapshot(s.data) AS d;
```

Group and following variable-data offsets come from each encoded group header,
not only the currently compiled metadata. This lets a decoder skip longer
fixed entries written by a compatible newer producer.

Multiple sequential fixed groups are supported. Entry order is preserved for:

- Inline fixed groups declared with `group :name do ... end`.
- Typed fixed groups declared with `group :name, of: Module`.
- Fixed scalar groups such as `group :ids, of: :uuid`.

## Support boundaries

SQL generation supports the common fixed primitives, UUIDs, enums, prefixed
IDs, fixed `CharArray` custom types, booleans, decimals, microsecond timestamps,
and `string16` variable fields. A new GridCodec type or wire feature is not
automatically SQL-queryable merely because Elixir encode/decode supports it.
Its SQL column mapping, read expression, null sentinel, JSON representation,
tests, documentation, and benchmark coverage must be reviewed separately.

Length-prefixed/framed groups and heterogeneous batches are not decoded into
SQL rows or JSON arrays. If one precedes variable data, `GridCodec.SQL.generate/1`
raises rather than generating incorrect offsets. Bulk `generate_all/1` skips
that codec and emits a SQL comment; the universal dispatcher then treats its
type name as unknown.

## Migration lifecycle

Treat the generated catalog as application code:

1. Generate and review it with the codec change.
2. Install it from a normal database migration.
3. Run `mix gridcodec.sql --check` in CI when committing the artifact.
4. Exercise representative encoded binaries against PostgreSQL before release.

`CREATE OR REPLACE FUNCTION` cannot change every PostgreSQL return shape in
place. When adding or removing decoded columns, drop the affected typed and JSON
functions before installing the new definitions:

```sql
DROP FUNCTION IF EXISTS gridcodec.decode_my_event(bytea);
DROP FUNCTION IF EXISTS gridcodec.decode_my_event_json(bytea);
```

Keep old application binaries in mind during rolling deploys. Installing a
decoder for a new event type is additive; replacing a decoder used by both old
and new nodes requires a wire-compatible shape or a staged rollout.

## Verification and benchmarks

The example application includes:

- `test/example_app/sql_generation_test.exs` for consumer-side SQL generation.
- `priv/sql_integration_test.exs` for encode, store, install, and PostgreSQL
  decode coverage, including a fixed typed group.
- `benchmarks/sql_generation_bench.exs` for fixed-codec, grouped-codec, and
  catalog generation baselines.

Run them from `example_app/`:

```bash
mix test test/example_app/sql_generation_test.exs
MIX_ENV=prod mix run --no-start benchmarks/sql_generation_bench.exs
mix run priv/sql_integration_test.exs
```

The integration script requires PostgreSQL and `psql`; configure
`ExampleApp.Repo` before running it.
