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
- Per-codec fixed-field readers such as
  `gridcodec.read_ordercreated_quantity(bytea)`.
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

When only a few fixed fields are needed, use their generated readers directly.
They return native PostgreSQL scalars without constructing a row or JSONB:

```sql
SELECT
  gridcodec.read_ordercreated_side(data) AS side,
  sum(gridcodec.read_ordercreated_quantity(data)) AS quantity
FROM events
WHERE event_type = 'OrderCreated'
GROUP BY side;
```

These readers are `IMMUTABLE STRICT PARALLEL SAFE`, so they can also back
expression indexes when a payload field is important enough to index. Variable
fields and groups do not have compile-time-fixed offsets and therefore do not
receive scalar reader functions.

## Decode a complete indexed stream

GridCodec does not assume an event table name or envelope schema. Consumers can
generate a set-returning function for their own table:

```elixir
GridCodec.SQL.generate_stream_decoder(
  function: "risk.read_user_stream",
  table: "risk.recorded_events",
  stream_id_type: :uuid,
  stream_id_column: :stream_uuid,
  decode: :raw
)
```

The generated function returns `stream_version`, `event_type`, and the original
`bytea` in version order. This is the preferred replay and application path:
fetch the indexed stream once and decode it with GridCodec on the BEAM.

```sql
SELECT *
FROM risk.read_user_stream('98a01a76-614d-48b7-9364-d0c79a7684c1');
```

The `:decode` option controls representation:

- `:raw` returns `data bytea` without database decoding.
- `{:fields, EventModule, [:field, ...]}` filters to that event type and returns
  selected fixed fields as native PostgreSQL columns.
- `:jsonb` (the backward-compatible default) returns the complete decoded
  payload. Reserve it for JSON consumers and ad hoc inspection.

The event table should have an index beginning with the native stream-id and
version columns:

```sql
CREATE INDEX recorded_events_stream_timeline_idx
ON risk.recorded_events (stream_uuid, stream_version);
```

The generated predicate does not cast the stream-id column, so PostgreSQL can
use that index. Supported argument types are `:text`, `:uuid`, `:bigint`, and
`:integer`. Envelope column names are configurable; see
`GridCodec.SQL.generate_stream_decoder/1`.

## Optional PL/Rust TLE accelerator

`GridCodec.SQL.PLRust` generates bounds-checked native readers and can package
them as a `pg_tle` extension:

```elixir
File.write!(
  "priv/repo/sql/gridcodec_plrust.sql",
  GridCodec.SQL.PLRust.generate_tle_install()
)
```

The database must preload and install both `pg_tle` and `plrust`; installation
also requires the appropriate `pgtle_admin` and PL/Rust language privileges.
After registering the generated package, run:

```sql
CREATE EXTENSION gridcodec_plrust;
```

This accelerator is experimental and optional. Amazon RDS supports PL/Rust on
PostgreSQL 13–17 but explicitly discontinued it for PostgreSQL 18, so
production schemas and application queries must retain the pure-SQL/raw-BEAM
path. Do not make core event replay depend on the extension.

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

Enum lookup tables and readers follow each enum's `:u8`, `:u16`, or `:u32`
encoding. Parameterized decimal groups preserve their declared scale and the
null sentinel of the configured integer wire format.

Length-prefixed/framed groups and heterogeneous batches are not decoded into
SQL rows or JSON arrays. `GridCodec.SQL.generate/1` rejects any codec containing
one rather than emitting a partial or empty decoder. Bulk `generate_all/1`
skips that codec and emits a SQL comment; the universal dispatcher then treats
its type name as unknown.

## Migration lifecycle

Treat the generated catalog as application code:

1. Generate and review it with the codec change.
2. Install it from a normal database migration.
3. Run `mix gridcodec.sql --check` in CI when committing the artifact.
4. Exercise representative encoded binaries against PostgreSQL before release.

`CREATE OR REPLACE FUNCTION` cannot change every PostgreSQL return shape in
place. Use the statement APIs from a migration so drops and every generated
function are executed individually:

```elixir
modules = [MyApp.Events.OrderCreated, MyApp.Events.RiskScored]

statements =
  GridCodec.SQL.drop_statements(modules) ++
    GridCodec.SQL.generate_all_statements(modules)

Enum.each(statements, &Ecto.Migration.execute/1)
```

Do not parse `generate_all/1` with a consumer-owned regex. That can silently
miss new function forms such as scalar readers with `PARALLEL SAFE`.

Fields marked `since: N` are guarded by the encoded header version in typed,
JSONB, and scalar decoders. Historical payloads return `NULL` for fields added
after their version instead of reading past the old fixed block. Variable data
starts at the block length stored in each payload header, so an older string
tail remains readable after later fixed-field appends.

Keep old application binaries in mind during rolling deploys. Installing a
decoder for a new event type is additive; replacing a decoder used by both old
and new nodes requires a wire-compatible shape or a staged rollout.

## Verification and benchmarks

The example application includes:

- `test/example_app/sql_generation_test.exs` for consumer-side SQL generation.
- `priv/sql_integration_test.exs` for encode, store, install, and PostgreSQL
  decode coverage, including a fixed typed group.
- `priv/sql_decoder_evolution_test.exs` for V1 → V2 → V3 catalog refreshes,
  historical fixed/variable payloads, scalar readers, JSONB, and an idempotent
  V3 reinstall.
- `benchmarks/sql_decode_bench.exs` for PostgreSQL decoding and indexed
  whole-stream query baselines, including raw plus BEAM, selected scalar
  columns, typed rows, JSONB, and a configurable large scalar workload.

Run them from `example_app/`:

```bash
mix test test/example_app/sql_generation_test.exs
DATABASE_HOST=db MIX_ENV=prod mix run benchmarks/sql_decode_bench.exs
GRIDCODEC_SQL_SCALAR_ROWS=2000000 DATABASE_HOST=db MIX_ENV=prod \
  mix run benchmarks/sql_decode_bench.exs
mix run priv/sql_integration_test.exs
mix run priv/sql_decoder_evolution_test.exs
```

The SQL benchmark reports `EXPLAIN ANALYZE` execution time, throughput,
decoded JSON size, shared/read/temp buffers, plan-node peak memory when
PostgreSQL exposes it, and retained backend-memory delta. It forces values to
be consumed rather than timing a projection that PostgreSQL can optimize away.
Cached execution time is a CPU-dominant proxy rather than a direct process-CPU
counter. Retained memory is not peak resident set size; production capacity
tests should also observe PostgreSQL process/container CPU and RSS externally.

On the development PostgreSQL 17 container, the representative 1,000-event
comparison measured approximately 0.12 ms for raw database execution, 0.55 ms
for raw fetch plus BEAM decode, 4 ms for three selected native columns, 259 ms
for complete typed rows, and 335–352 ms for complete JSONB. The two-million
event fixed-field aggregate completed in about 0.90 seconds (2.23 million
events/second) while reading part of the table from shared storage. Treat these
as relative baselines, not hardware-independent promises.

The integration and benchmark scripts require PostgreSQL; the broad integration
script also invokes `psql`. Configure `ExampleApp.Repo` before running them.
