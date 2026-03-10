# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.27.0] - 2026-03-10

### Added
- **`PrefixedId` composite type** — new parameterized type for self-describing entity
  identifiers on the wire (17 bytes: u8 tag + 16-byte UUID). Define types with
  `use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01`. Includes full coercion
  (auto-prefixes plain UUIDs), O(1) getter, DB-level tag byte queries, SQL generation,
  and helpers (`generate/0`, `from_uuid/1`, `to_uuid/1`, `valid?/1`).
- **String coercion** — String types (`:string8`, `:string16`, `:string32`) now coerce
  atoms and numbers via `to_string/1` instead of rejecting them.

### Changed
- **Integer coercion rejects out-of-range values** — `new/1` now returns
  `{:error, %ValidationError{}}` for values outside the type's range (e.g., 300 for `:u8`)
  regardless of `validate:` setting. Previously, out-of-range values were silently accepted
  and only failed at `encode/1`.
- **Enum coercion rejects unknown values** — `new/1` now rejects unknown integer/atom
  values for enum fields. Only known variants (by atom, string, or integer) are accepted.
  Enum types also implement `validate_ast/3`.
- **Encode errors preserve field name** — `ArgumentError` during encode now extracts the
  field name from the error message instead of reporting `field: :unknown`.

### Fixed
- **UUID coercion no longer raises** — Malformed UUID strings (36-char or 32-char with
  invalid hex) now return `{:error, reason}` instead of raising `FunctionClauseError`.
- **Decimal rescue narrowed** — `Decimal.new/1` parse failures now rescue only
  `Decimal.Error` instead of catching all exceptions.

## [0.26.1] - 2026-03-09

### Added
- **Extended Coq formal verification** — 55 machine-checked theorems (up from 37),
  adding heterogeneous field width struct roundtrip, schema evolution forward
  compatibility, signed integer two's complement roundtrip, bool tri-state exhaustive
  proof, and batch concatenation isolation.

### Fixed
- **Compile warning** — `GridCodec.Registry.lookup_enum_by_name/1` no longer triggers
  "undefined or private" warning at compile time (uses `apply/3` for late binding).

## [0.26.0] - 2026-03-09

### Added
- **`.grid` format versioning (`@syntax 1`)** — Every generated `.grid` file now starts
  with an `@syntax N` directive declaring the format version. The parser validates the
  version and rejects files with unsupported syntax. Files without `@syntax` are assumed
  to use the latest version. The generator accepts `--syntax N` CLI flag and
  `config :app, :grid_codec, syntax: N` for targeting specific versions.
- **Formal `.grid` specification** — Complete format spec for syntax 1 added to
  `GridCodec.Schema.Parser` moduledoc, covering directives, blocks, types, field options,
  imports, comments, and type resolution rules.
- **Self-contained individual files** — Each struct `.grid` file now imports the enum types
  it references, making it independently parseable without the master file's import tree.
- **Cross-schema type imports** — When a struct in schema A references an enum defined in
  schema B, the export task generates correct cross-schema import paths. Enum files are
  generated in their home schema (lowest schema_id) and imported by reference from others.
- **Global type alias resolution** — `Formatter.build_type_aliases/2` and
  `Formatter.detect_all_enums/1` now operate across all schema groups, ensuring consistent
  type names in multi-schema exports.
- **Compiler `types:` option** — `use GridCodec.Struct, types: %{OrderSide: MyApp.OrderSide}`
  enables explicit mapping of `.grid` type names to Elixir modules when compiling from
  `.grid` files via `grid_file:`.
- **Auto-resolve enum types** — `GridCodec.Registry.lookup_enum_by_name/1` provides
  automatic resolution of `.grid` enum names to loaded Elixir enum modules, used as a
  fallback when no explicit `types:` mapping is provided.
- **`WIRE_SYNTAX_VERSION_CHANGED` breaking rule** — Breaking change detection now flags
  `@syntax` version changes between baseline and current schemas.
- **EBNF grammar** — Formal EBNF grammar (22 productions) added to `Parser` moduledoc,
  covering all `.grid` syntax constructs from lexical elements to top-level definitions.
- **VS Code / Cursor syntax highlighting** — TextMate grammar for `.grid` files in
  `editors/vscode-grid/` with full keyword, type, enum, and field highlighting.
- **Codec correctness proof suite** — `codec_proofs_test.exs` with 39 tests proving
  size consistency (P3), garbage rejection (P6+), type isolation (P7), formatter/parser
  agreement (P8), byte-level idempotence (P9), exhaustive finite-domain proofs (P10),
  and parser EBNF compliance (P11).

### Changed
- Formatter functions (`format/5`, `format_master/5`, `format_struct_file/3`,
  `format_enum_file/2`) now accept an `opts` keyword list with `:syntax` for version
  targeting and `:imports` for individual file dependencies.

### Removed
- **Legacy `message` keyword** — The deprecated `message` keyword is no longer accepted
  by the parser. Use `struct` instead.
- **Lenient struct attribute parsing** — Commas between struct attributes (e.g.,
  `template_id: 1, version: 2`) are now required.
- **Empty `any_of` lists** — `any_of: []` in batch blocks is now rejected as invalid.

### Fixed
- **`valid_identifier?` regex** — `?` is now restricted to trailing position only;
  `f?oo` is rejected while `filled?` is accepted.

## [0.25.0] - 2026-03-09

### Added
- **Structured `.grid` export** — `mix grid_codec.export` now generates a directory per
  `schema_id`, each containing a `schema.grid` master file with `import` directives plus
  individual files for each struct and enum. File paths are derived from the struct's
  `name:` option (e.g., `"Namespace.EventName"` → `namespace/event_name.grid`). Structs
  are sorted alphabetically by name.
- **`import` directive** — The `.grid` parser now supports `import "path"` directives.
  `parse_file_with_imports/2` resolves imports recursively with cycle detection. Breaking
  change detection and the `grid_file:` compiler option resolve imports automatically.
- **Configurable schema directory names** — Schema directories are configurable via
  application config: `config :my_app, :grid_codec, schemas: %{100 => "events"}`.
  Unconfigured schema_ids default to `schema_{id}`.
- **Formatter API** — New public functions: `format_master/4` (master file with imports),
  `format_struct_file/2` (standalone struct file), `format_enum_file/1` (standalone enum
  file), `build_type_aliases/2`, `struct_name/1`.

### Changed
- `.grid` export now produces directories instead of flat files. Old flat format is still
  fully supported by the parser and breaking change detection for backward compatibility.
- Struct ordering in generated `.grid` files changed from `template_id` to alphabetical
  by name.
- The `Schema` parser struct now includes an `imports` field (`[String.t()]`).

## [0.24.0] - 2026-03-09

### Added
- **Breaking change detection** — New `mix grid_codec.breaking` task compares `.grid`
  schema files against a baseline (git ref or file path) and reports wire-incompatible
  and source-incompatible changes. Inspired by [Buf](https://buf.build/docs/breaking/).
  Includes 21 WIRE rules (binary compatibility) and 8 SOURCE rules (API compatibility).
  Configurable via `.grid_codec.exs` with support for rule exclusions and category filters.
- **`.grid` schema export** — New `mix grid_codec.export` task generates declarative
  `.grid` schema files from compiled `defcodec` modules. Supports all field options
  (`wire_format`, `since`, `default`, `presence`, `value`), parameterized types
  (`decimal(scale: 8)`), groups, batches, and enums.
- **`.grid` schema parser** — Extended `GridCodec.Schema.Parser` to support batch/any_of
  syntax, parameterized type parameters, and all field options. Full round-trip fidelity:
  parse → format → re-parse produces equivalent schemas.
- **`--check` mode for `mix gridcodec.sql`** — Verifies the generated SQL file is up to
  date without writing to disk. Exits non-zero if stale or missing. Intended for CI and
  pre-push hooks.
- **`--check` mode for `mix grid_codec.export`** — Same check-without-write pattern for
  `.grid` schema files. Reports each stale or missing file individually.
- **CI breaking change job** — New `breaking` job in GitHub Actions runs
  `mix grid_codec.breaking` on pull requests with full git history.
- **Schema metadata in `__schema__/0`** — `batches` and `group_fields` are now included
  in the compile-time schema map, enabling the formatter and export task to produce
  complete `.grid` files.

## [0.23.2] - 2026-03-06

### Fixed
- **SQL signed integer decoding** — `sql_read_expr` used unsigned readers (`read_u16`,
  `read_u32`) for `:i16` and `:i32` types, producing incorrect positive values instead of
  negative values. Added `gridcodec.read_i8`, `gridcodec.read_i16`, `gridcodec.read_i32`
  helper functions with proper two's complement conversion. Also fixed `null_check_expr`
  to include signed integer null sentinels and corrected `sql_json_value_expr` signed null
  sentinel values.
- **F32/F64 NaN null decode** — `decode_value_ast` was missing for `:f32` and `:f64`,
  so IEEE 754 NaN (the null sentinel) was returned as-is instead of being converted to
  `nil`. Added `maybe_nil/1` helper that detects NaN via the canonical `v != v` check.

### Changed
- **UUID parsing uses arithmetic conversion** — Replaced `Base.decode16!/2` with a new
  `parse_uuid_nodash!/1` function that extracts individual bytes and converts hex chars
  to nibbles via arithmetic, avoiding sub-binary allocation and generic parsing overhead.
  Same approach already used by `parse_uuid_string!/1` for dashed UUIDs. Affects
  `uuid_string` encode hot path and both `uuid`/`uuid_string` coercion paths.
- **JSON pretty_format eliminates encode/decode round-trip** — `json_encode_map` now
  calls `do_pretty/2` directly on the map instead of encoding to JSON, decoding back,
  and then pretty-formatting.
- **PromEx metrics deduplicated** — `prom_ex_metrics/1` now delegates to
  `metric_definitions/1` instead of duplicating metric definitions.

### Deprecated
- **`GridCodec.Json.encode/2,3`** — Use `to_json/3` instead.
- **`GridCodec.Json.encode!/2,3`** — Use `to_json/3` with pattern matching instead.
- **`GridCodec.Json.decode/2,3`** — Use `from_json/3` instead.
- **`GridCodec.Json.decode!/2,3`** — Use `from_json/3` with pattern matching instead.

### Documentation
- Fixed `AGENTS.md` example using `gridcodec do` (should be `defcodec do`)
- Fixed `README.md` Elixir version requirement to match `mix.exs` (`1.18+`)

## [0.23.1] - 2026-03-06

### Added
- **Zero-surprise test suite** — 97 new tests (35 property-based, 62 unit) exercising
  every type invariant from first principles: roundtrip identity, `new/1` idempotence,
  encode determinism, `get/2` consistency, `new_binary` equivalence, multi-pass pipeline
  stability, content_hash reproducibility, concurrent thread safety, and decode resilience
  to garbage/truncated input. Covers integers, floats, strings, UUIDs, timestamps,
  datetimes, decimals, booleans, enums, bitsets, and char arrays.

### Fixed
- **CI compilation order bug** — Type modules guarded `generator/0` with
  `Code.ensure_loaded?(GridCodec.Generators)` which failed on fresh CI builds when
  the type file compiled before `generators.ex`. Changed to
  `Code.ensure_loaded?(StreamData)` across all 26 occurrences in 21 type files,
  eliminating the compilation order dependency.

## [0.23.0] - 2026-03-05

### Added
- **`:datetime_us` and `:datetime_ns` types** — DateTime-domain timestamp types
  that decode to `%DateTime{}` instead of raw integer microseconds/nanoseconds.
  Same 8-byte i64 LE wire format as `:timestamp_us`/`:timestamp_ns`, binaries
  are interchangeable. Use `:datetime_us` for application code, JSON APIs, and
  Ecto-like workflows; use `:timestamp_us` for hot paths where decode overhead
  matters.
- **`GridCodec.Batch` — heterogeneous batch encoding** with compile-time
  `any_of:` type sets. Preserves insertion order with O(1) count, random access,
  lazy streaming, and type-based filtering. Two strategies available:
  - **`:padded_union`** (default) — fixed-size entries padded to max block length,
    reuses `GridCodec.Group` wire format, O(1) random access from raw binary.
  - **`:typed_frames`** — length-prefixed entries with no padding waste, builds
    offset index on decode for O(1) access. 30% smaller wire size when types
    have different `block_length` values.
- **`batch/2` DSL macro** — `batch :commands, any_of: [PlaceOrder, CancelOrder],
  strategy: :typed_frames` generates compile-time union encoders/decoders with
  type-tag dispatch. Strategy is chosen once at compile time; the runtime API
  is identical regardless of strategy.
- **`GridCodec.Binary` module** — utilities for managing binary memory lifecycle.
  `detach/1` copies all binary-valued fields in a decoded struct, releasing
  sub-binary references to the original encoded data. `copy_field/1` is a
  nil-safe wrapper around `:binary.copy/1`.
- **`get/2` `:copy` option** — `get(binary, :field, copy: true)` wraps the
  result in `:binary.copy/1` to detach sub-binary references from the original
  encoded binary, preventing memory retention. Safe on any field type —
  non-binary values pass through unchanged.

### Changed
- **`GridCodec.Json` now uses Elixir's built-in `JSON` module** instead of
  `Jason`. The `:jason` dependency has been removed. Requires Elixir >= 1.18.
  Custom types should implement the `JSON.Encoder` protocol instead of
  `Jason.Encoder`. The `:pretty` and `:keys` options are preserved with the
  same behavior.

### Fixed
- **`coerce_ast` identity invariant** — fixed 6 types where `new/1` and
  `decode/1` produced different in-memory representations for the same value:
  - `:uuid_string` — coerce now normalizes to 36-char dash-separated string
    (was converting to raw 16-byte binary, breaking map key lookups)
  - `:timestamp_us`/`:timestamp_ns` — coerce now converts `%DateTime{}` and
    ISO 8601 strings to integer microseconds/nanoseconds (matching decode)
  - `:decimal`/`:positive_decimal` — `{mantissa, exponent}` tuple input now
    normalizes to `%Decimal{}` struct (matching decode)
  - Enum types — coerce now resolves known integer values to atoms (matching
    decode). Unknown integers still pass through.
  - `CharArray` — coerce now strips trailing null bytes (matching decode)

### Removed
- **`:jason` dependency** — `GridCodec.Json` now uses Elixir's native `JSON`
  module (available since 1.18). No external JSON library required.

### Documentation
- **Memory & Binary Lifecycle** section in performance guide — documents refc
  binary threshold (64 bytes), sub-binary retention problem, `on_heap` vs
  `off_heap` message queue strategy, `min_bin_vheap_size` tuning, the load
  balancer anti-pattern, and distribution wire efficiency.
- **Production Monitoring** section in performance guide — documents
  `erlang:memory(:binary)`, `recon:bin_leak/1`, common leak causes, and
  BEAM allocator flags for binary-heavy workloads.
- **AGENTS.md** updated with Binary Memory Model section explaining refc
  binary implications for GridCodec.
- **ExDoc**: All numeric type modules (U8–U64, I8–I64, F32, F64) now appear
  in the Types sidebar group. Consumer Integration guide added to extras.
- **Performance skill**: Documented that `iolist_to_binary` is NOT faster than
  `<<a::binary, b::binary>>` for encode assembly — the JIT optimizes binary
  concat into direct memcpy, avoiding iolist traversal overhead.

## [0.22.0] - 2026-03-05

### Added
- **`GridCodec.Match` — compile-time matchspec-like binary filtering** — Define
  predicate functions with `defmatch` that extract fields at compile-time known
  offsets and evaluate guard expressions without full decode.  Supports native
  Elixir guards (`==`, `<`, `band`, arithmetic), cross-field comparisons
  (`end_time_ns - start_time_ns > threshold`), multiple ANDed `where` clauses,
  and field selection via `select:`.  See [Binary filtering guide](docs/binary-filtering.md).
- **`GridCodec.Transcoder` — compile-time codec-to-codec transcoding** — Generate
  `transcode/1` functions that read fields from a source GridCodec binary at
  known offsets and pass them directly to a target encoder, skipping the full
  decode → struct → re-encode cycle.  Supports field rename (`to:`), value
  transforms (`transform:`), and partial field extraction.
- **`__match_meta__/0`** introspection function on all codec modules — exposes
  rich field metadata (wire module, domain module, offset, payload offset, size,
  endian) for use by `GridCodec.Match` and `GridCodec.Transcoder`.
- **UUID v5 generation** — `GridCodec.Types.UUID.generate_v5/2` (SHA-1
  name-based, RFC 4122 Section 4.3) with standard namespace helpers
  (`ns_dns/0`, `ns_url/0`, `ns_oid/0`, `ns_x500/0`).
- **Example app modules** — `ExampleApp.SpanFilters`, `ExampleApp.OrderFilters`,
  and `ExampleApp.SpanToEnvelope` demonstrating Match and Transcoder usage.
- **ETS binary-first benchmark** — `example_app/benchmarks/ets_binary_bench.exs`
  comparing struct-based vs binary-based ETS patterns across insert, lookup,
  scan+filter, batch export, and cross-field filtering.
- **Trace context benchmark** (revised) — `example_app/benchmarks/trace_context_bench.exs`
  with honest fan-out comparison: measures receive-side cost per recipient, full
  pipeline with real process sends, and cross-node ETF wire sizes.
- **Generators test suite** — `generators_test.exs` with property tests for all
  built-in type generators.
- **Property tests for Match and Transcoder** — randomized verification of
  predicate correctness and transcoding field preservation.

### Performance
- **Bitset `encode_ast` inlined** — `to_integer/1` call replaced with inline
  `MapSet.member?` + `Bitwise.bor` checks per flag, eliminating function call
  overhead in the encode hot path.
- **CharArray `encode_ast` inlined** — `encode/1` call replaced with inline
  `byte_size` + padding logic, eliminating function call overhead.

### Fixed
- **`__field_specs__/1`** now uses `effective_module` (respecting `wire_format:`
  overrides) instead of the raw domain module.  Previously, fields with
  `wire_format:` would return the domain type module, causing incorrect offset
  calculations in external tooling.
- **`defmatch` generated functions** no longer inject `@doc false`, allowing
  user-provided `@doc` annotations to flow through to ExDoc.
- **ExDoc warnings** — fixed stale function references (`GridCodec.new/1`,
  `GridCodec.new_binary/1`) and broken `consumer-integration.md` links.

### Documentation
- **[Binary filtering guide](docs/binary-filtering.md)** — new guide covering
  `GridCodec.Match`, `GridCodec.Transcoder`, binary-first ETS patterns, and an
  end-to-end telemetry span pipeline example.
- **ExDoc sidebar** — Match and Transcoder now appear under "Core DSL" group;
  binary-filtering guide added to extras navigation.

## [0.21.0] - 2026-03-05

### Added
- **UUID v4 and v7 generation** — `GridCodec.Types.UUID.generate_v4/0` (RFC 4122)
  and `generate_v7/0` (RFC 9562, time-sortable). Also `v7_timestamp/1` to extract
  the millisecond timestamp from a v7 UUID.
- **Auto-inferred `wire_format:`** — `{:decimal, scale: N}` and
  `{:positive_decimal, scale: N}` now automatically select `:i64` / `:u64`
  wire format. Explicit `wire_format:` is no longer required for the common case.
- **Per-type micro benchmark** — `example_app/benchmarks/type_micro_bench.exs`
  measures encode, decode, and zero-copy get for every built-in type in isolation.
- **Ecto comparison benchmark** — `example_app/benchmarks/ecto_comparison.exs`
  compares GridCodec vs Ecto changeset + JSON across all pipeline stages.

### Performance
- **UUID parse/format**: `parse_uuid_string!/1` and `format_uuid/1` rewritten
  with direct nibble-level operations — no `String.replace`, no `Base.encode16`
  allocation chain.
- **Bitset inlined**: `to_integer/1` and `from_integer/1` now use compile-time
  generated `Bitwise.bor`/`Bitwise.band` checks instead of `Enum.reduce`.
- **Zero-overhead validation**: `__validate__/1` call eliminated entirely when
  `validate: false` — no function definition, no call site.
- **Static var decoder dispatch**: Replaced `apply/3` with direct module calls
  for string decode functions.

### Removed
- **`decode_as:` field option** — removed entirely (was deprecated in 0.20.0).
  Use `wire_format:` or parameterized types instead.

### Fixed
- **`compute_null_fixed_block`** now uses wire module for `wire_format:` fields.
- **Getter macro** uses wire module for offset calculation on `wire_format:` fields.

## [0.20.0] - 2026-03-04

### Added
- **Parameterized types** — field types can now accept options via tuple syntax:
  `field :amount, {:decimal, scale: 8}`. The type module receives these options
  to customize encoding behavior.
- **`wire_format:` field option** — explicitly control the binary encoding format
  while keeping the domain type for input/output. Works in both top-level fields
  and groups:
  ```elixir
  field :price, {:decimal, scale: 8}, wire_format: :i64
  ```
  This encodes as i64 on the wire (8 bytes) but accepts `Decimal.t()` as input
  and returns `Decimal.t()` on decode. Supported wire types: `:i8`, `:i16`, `:i32`,
  `:i64`, `:u8`, `:u16`, `:u32`, `:u64`, `:f32`, `:f64`.
- **`encode_to_wire_ast/2` callback** on `GridCodec.Type` — domain types implement
  this to convert their values to the wire type for encoding.
- **`int_pow10/1` helper** on `GridCodec.Types.Decimal` for efficient scaled integer
  arithmetic (lookup table for powers 0–8, recursive fallback).

### Changed
- **`field/3` macro** now accepts parameterized type tuples as the type argument.
- **Field documentation** now describes the Input/Wire/Output model clearly.

### Removed
- **`decode_as:` field option** — removed entirely. Use `wire_format:` instead.
  The `decode_as_ast/2` callback on `GridCodec.Type` is retained for internal use
  by the `wire_format:` mechanism.

## [0.19.0] - 2026-03-04

### Changed (BREAKING)
- **`encode/1,2` now returns `{:ok, binary()} | {:error, ValidationError.t()}`** instead
  of bare `binary()`. This applies to all generated codec modules and `GridCodec.encode/1,2`.
  Encode errors (validation failures, argument errors) are returned as `{:error, ...}`
  instead of raising.
- **Removed `new!/1`** — use `new/1` which returns `{:ok, struct} | {:error, ...}`.
  Libraries should not raise; callers can pattern-match on the result.
- **`GridCodec.Registry.encode/2`** no longer raises on unknown structs — returns
  `{:error, ValidationError.t()}` instead.

### Added
- `@spec encode(t(), keyword())` typespec on all generated encode functions
  (conditional on `generate_typespec: true`).

### Docs
- Updated docs/examples/tests to reflect new `{:ok, binary}` return type and
  removal of bang functions.

## [0.18.0] - 2026-03-04

### Added
- **`decode_as_ast/2` callback** on `GridCodec.Type` — general mechanism for
  decode-time type coercion. Any custom type can implement it. Source type module
  is passed via opts for generating optimized code (e.g., no unreachable clauses
  for integer source types).
- **`coerce_ast/1` for enum, bitset, chararray** — custom macro-based types now
  participate in `new/1` coercion. Enum: `"buy"` → `:buy`. Bitset: `["read"]` →
  `MapSet`. CharArray: string passthrough.
- **Group entry coercion** — `new/1` and `new_binary/1` now coerce group entry
  fields (string keys, string values). Error messages include group name context.

### Fixed
- **Unreachable clause warnings** in `decode_as` for integer source types — Elixir
  1.18 type checker no longer warns with `--warnings-as-errors`.

## [0.17.0] - 2026-03-04

### Added
- **`decode_as` option for group fields**: Wire-efficient types with typed decode
  output. `field :amount, :i64, decode_as: :decimal` stores as i64 on wire but
  decodes to `%Decimal{}`. `decode_as: {:decimal, scale: 8}` applies fixed-point
  scaling. Eliminates the double-scaling bug in period rotation carry-forward.
- **`new_binary/1`**: Coerce + validate + encode in one shot, zero struct allocation.
  Accepts maps (atom/string keys), keyword lists, or structs. Returns `{:ok, binary}`.
- **`content_hash/1`**: Deterministic SHA-256 from wire format for deduplication.
- **`decode_only/2`**: Selective field extraction using compile-time offsets.

### Changed
- **Unified `new/1` constructor**: Does coercion AND validation in one call.
  Accepts string keys, string values, atom keys, typed values — any mix.
  Returns `{:ok, struct}` or `{:error, %ValidationError{}}`.
- **`cast/1` removed**: `new/1` replaces it entirely — one constructor, one API.
- **Lazy error messages**: `ValidationError` message generated only when printed.
  Error path: 7.7x faster, 5x less memory.
- **Constructor optimized**: `:maps.find` short-circuit + `struct/2` (no key validation).
- **Decimal coercion**: `new(price: 100)` now returns `%Decimal{}` not raw integer.
- **Internal functions hidden** from ExDoc (`@doc false` on `__schema__`, `__type__`, etc.)
- **Auto `@moduledoc`** for custom enum/bitset/chararray modules (fixes ExDoc warnings).

### Fixed
- **Registry consolidation path**: Writes to `grid_codec/ebin/` not protocol consolidation dir.
- **Registry module discovery**: Scans beam files on disk, not `:code.all_loaded()`.
- **`ensure_all_loaded/0`** on Registry for runtime eager loading.

## [0.15.1] - 2026-03-04

### Fixed
- **CRITICAL: Consolidated Registry destroyed by protocol consolidation** — The
  `:grid_codec` Mix compiler was writing the Registry beam to
  `Mix.Project.consolidation_path()`, which Elixir's protocol consolidation
  recreates on every compile, destroying the Registry. Now writes to
  `_build/<env>/lib/grid_codec/ebin/` which is on the code path and not
  touched by protocol consolidation.
- **Fallback Registry finds 0 codecs due to lazy module loading** — `collect_codecs`
  now scans beam files on disk via `Path.wildcard` instead of relying on
  `:code.all_loaded()` which misses lazily-loaded modules.

### Added
- **`ensure_all_loaded/0` on Registry** — Eagerly loads all GridCodec modules from
  beam files on the code path. Call at application startup to ensure the fallback
  registry can find all codecs without the consolidated registry.

## [0.15.0] - 2026-03-04

### Added
- **`cast/1` coercion pipeline**: Converts external data (string keys, string values
  from JSON) to typed structs. Coerces `"100"` → integer, `"true"` → boolean,
  `"2026-01-01T00:00:00Z"` → DateTime, `"100.50"` → Decimal, UUID strings → binary.
  Returns `{:ok, struct}` or `{:error, field, reason}`.
- **`content_hash/1`**: Deterministic SHA-256 hash from the wire representation.
  Two structs with identical values always produce the same hash regardless of
  map key ordering. Useful for deduplication, idempotency, event fingerprinting.
- **`decode_only/2` projection**: Decodes only the requested fields from a binary
  using compile-time field offsets (O(1) per field). Returns a map with just
  the selected fields — no allocation for skipped fields.
- **`coerce_ast/1` optional callback** on `GridCodec.Type` — custom types can
  implement this for `cast/1` support. Implemented for all built-in types.

## [0.14.0] - 2026-03-04

### Added
- **Type-level validation** via `validate: true` option (per-module or global config).
  Generated at compile time — zero overhead when disabled. Catches type mismatches,
  integer overflow/underflow, invalid UUID formats, and wrong types for decimal/bool/
  timestamp fields BEFORE encoding, with structured `GridCodec.ValidationError` errors.
- **`GridCodec.ValidationError`** exception struct with `code` (`:type_mismatch`,
  `:out_of_range`, `:invalid_format`), `message`, and `details` (field, type, value,
  module). Pattern-matchable for programmatic error handling.
- **`validate_ast/3` optional callback** on `GridCodec.Type` behaviour — custom types
  can implement this to participate in pre-encode validation.
- Implemented `validate_ast` for all built-in types: u8-u64, i8-i64, f32, f64, bool,
  uuid, uuid_string, decimal, positive_decimal, timestamp_us, timestamp_ns.
- **`new/1` and `new!/1` constructors** on every codec struct. `new/1` returns
  `{:ok, struct}` or `{:error, %ValidationError{}}`. `new!/1` raises. Accepts
  maps or keyword lists. Runs validation when `validate: true` is enabled.

## [0.13.0] - 2026-03-04

### Added
- **`Group.to_lists_parallel/2`**: Decodes multiple groups in parallel, one
  process per group with pre-sized heaps (avoids GC during decode). Binary
  sharing is zero-copy. Auto-threshold at 256KB total group data; configurable
  via `:threshold` option. Falls back to sequential for small groups.
- **Property-based tests** for groups with custom types (enum roundtrip,
  multiple enums, decimal fields with nil values)

### Documentation
- Updated `GridCodec.Struct` moduledoc with `telemetry`, `telemetry_min_duration`
  options and global config example

## [0.12.0] - 2026-03-04

### Added
- **Optional telemetry** for encode/decode: per-module `telemetry: true` option
  or global `config :grid_codec, telemetry: true`. Emits `[:grid_codec, :encode]`
  and `[:grid_codec, :decode]` events with `duration` (native time), `bytes`,
  and metadata (`module`, `type_name`, `schema_id`, `template_id`). Zero
  overhead when disabled (default) — no timing code generated.
- **`telemetry_min_duration` option** — skip emitting events when duration is
  below a threshold (in `:native` time units). Filters out cheap operations
  so histograms focus on the latency you care about. Per-module or global config.
- **`GridCodec.Telemetry.Metrics`** — metric definitions for PromEx, LiveDashboard,
  or any `Telemetry.Metrics` consumer. `prom_ex_metrics/1` returns PromEx-compatible
  `Event.build` tuples; `metric_definitions/1` returns raw metric structs.
  Always compiles (no PromEx dependency required at grid_codec level).
- **Grafana dashboard** (`grafana/grid_codec.json`) — pre-built dashboard with
  encode/decode latency percentiles (p50/p90/p99), throughput, and binary sizes.

### Changed
- **Enum**: `to_integer/1` and `to_atom/1` now use pattern-matched function clauses
  instead of runtime map lookups (JIT compiles to direct comparisons).
  `encode_ast` and `decode_value_ast` generate fully inlined case clauses — no
  function calls in the encode/decode hot path. `getter_ast` also inlined.
- **Bitset**: Removed IIFE wrapper from `encode_ast`; uses direct case with nil
  handling instead of anonymous function allocation
- **CharArray**: Removed IIFE from `encode_ast`; `decode_value_ast` and `getter_ast`
  now use `:binary.match/2` for null-byte detection instead of
  `bin_to_list + take_while + list_to_bin` (pure binary ops, no list conversion).
  `decode/1` also updated.
- Added parallel decode benchmarks and threshold analysis scripts

## [0.11.0] - 2026-03-04

### Added
- **Custom types in groups**: Module aliases (enums, bitsets, char arrays, any
  `GridCodec.Type` implementation) now resolve correctly inside `group do` blocks
- **`:positive_decimal` type**: Optimized decimal for non-negative values (prices,
  quantities, balances). Skips sign handling on encode/decode. Wire-compatible
  with `:decimal` for positive values
- **`Group.encode_fast/3`**: Fast encoding with compile-time block length — skips
  per-entry size validation, single-pass count+encode via `:lists.mapfoldl`
- **`Group.parse_with_rest!/2,3`**: Combined parse + rest extraction in one call
- **Inline batch decoder**: Auto-generated `__decode_all_<group>__/2` function that
  pattern-matches all fields directly from the binary in a single recursive loop.
  No sub-binary allocation, no dynamic dispatch, no `{:ok, ...}` tuple per entry.
  Used automatically by `Group.to_list/1`
- **Inline batch encoder**: Auto-generated `__encode_<group>_group__/1` with direct
  local function calls to the entry encoder (JIT-inlineable), replacing anonymous
  function wrappers and dynamic captures

### Changed
- **Group encoding pipeline**: Struct encoder fast path now enabled for codecs with
  groups (previously fell back to `Map.from_struct`). Compile-time block length
  eliminates runtime size discovery
- **Group decoding pipeline**: Inline sequential parsing replaces `Enum.reduce` over
  runtime lists. Struct decoder builds the struct directly with all fields
  (fixed + groups + var) in a single literal — no `Map.merge` + `struct!`
- **`Group.to_list/1`**: Uses sequential binary walking instead of per-index access
  with bounds checking. When batch decoder is available, dispatches to it for
  maximum throughput
- **Decimal encode inlined**: `encode_ast` now generates inline `case` expressions
  that pattern-match `%Decimal{}` directly into binary segments, eliminating
  `encode_value/1` and `from_decimal/1` function calls and tuple allocation
- **Enum decode optimized**: `decode_pattern_ast` now extracts integers directly
  from binary patterns (not sub-binaries), and `decode_value_ast` calls
  `to_atom/1` directly instead of going through `decode/1` + tuple destructure
- **Timestamp encode inlined**: Integer timestamps write directly into the outer
  binary segment (`:: little-signed-64`) with no intermediate 8-byte binary

### Performance (TradingPeriodSettled shape, 5k users + 50k orders)

| Operation | v0.10.0 | v0.11.0 | Improvement |
|-----------|---------|---------|-------------|
| Encode | 38.8 ms / 17.0 MB | 33.8 ms / 9.4 MB | 1.15x faster, -45% memory |
| Decode+list | 56.2 ms / 49.2 MB | 25.0 ms / 30.1 MB | 2.25x faster, -39% memory |
| Full roundtrip | 90.5 ms / 66.6 MB | 64.6 ms / 40.7 MB | 1.40x faster, -39% memory |
| Lazy decode | 150 ns / 536 B | 249 ns / 1.16 KB | O(1) regardless of size |

## [0.10.0] - 2026-03-03

### Added
- **Auto-generated codec typespecs** for `GridCodec.Struct` modules (enabled by default)
  - `@type t() :: %__MODULE__{}`
  - `@type layout()` for payload binaries (`header: false`)
  - `@type framed_layout()` for binaries that include the 8-byte GridCodec header
- **`generate_typespec: false` option** to disable generated types and let modules
  provide custom `@type` declarations without conflicts

### Changed
- Generated `layout()` and `framed_layout()` are now size-aware:
  - Fixed-size codecs use exact bit-size binary types
  - Codecs with variable fields/groups use minimum fixed-block size plus byte-aligned tail

### Documentation
- Updated `GridCodec.Struct` docs with generated type details and the
  `generate_typespec` option
- Added Getting Started guide section for auto-generated typespecs and opt-out usage
- Updated README feature list to include `framed_layout()`

### Tests
- Added core tests for default type generation, opt-out behavior, and binary type shape
- Added example app tests that validate generated types in consumer usage, including:
  - opt-out modules with no generated types
  - custom user-defined types preserved when generation is disabled

## [0.9.0] - 2026-03-02

### Added
- **Stable type names**: `:name` option on `use GridCodec.Struct` for short,
  module-independent type strings (e.g., `"OrderSubmitted"` instead of
  `"Elixir.MyApp.Events.OrderSubmitted"`)
  - `__type__/0` generated on every codec module
  - Defaults to last segment of module name when not specified
  - Accepts string or atom values
  - Type name included in `__schema__/0` metadata
- **`GridCodec.Registry.lookup_by_type/1`**: Reverse lookup from type name
  string to codec module, enabling EventStore/Commanded serializer integration

## [0.8.0] - 2026-03-02

### Added
- **Schema evolution with `:since`**: Decoder pads shorter binaries from older
  schema versions using precomputed null sentinels — new fields decode as `nil`
  - `:since` option on field definitions for schema version tracking
  - `field_versions` map in `__schema__/0` metadata
  - Compile-time validation that `:since` values are non-decreasing in the fixed block
  - Zero overhead on same-version decode (single integer comparison fast path)
- **Auto-generated group entry codecs**: Groups with field declarations now
  generate entry encoder/decoder automatically from the type system
  - Eliminates manual binary encode/decode boilerplate for group entries
  - Compile-time rejection of variable-length fields in group entries
  - Group names included in `defstruct` with default `[]`
- **`GridCodec.BinaryInspector`**: Runtime binary inspection and diagnostics
  - `GridCodec.inspect_binary/2` top-level API
- **Type-aware field comparison**: `compare/5` and `compare_binaries/4` for
  comparing fields directly on encoded binaries without full decode
- **`encode_field/2` macro**: Pre-encode values for pin matching on custom types
- **JSON transcoding improvements**: Enhanced `GridCodec.Json` encoding/decoding

### Fixed
- Dead `nil` branch in group decoder generation (eliminated Elixir 1.19 type warnings)

## [0.7.0] - 2026-01-09

### Added
- **`.grid` schema files**: Define GridCodec structs in external schema files
  - Protobuf-inspired syntax with `.grid` file extension
  - New `struct` keyword with explicit header parameters: `struct Order (template_id: 1001) { ... }`
  - Support for per-struct version overrides: `struct Trade (template_id: 1002, version: 2) { ... }`
  - Schema-level metadata: `schema Trading { id: 100 version: 1 }`
  - Composite types: `type Price { mantissa: i64 exponent: i8 }`
  - Enums: `enum Side : u8 { buy = 1 sell = 2 }`
  - Optional fields with `?` suffix
  - Repeating groups support
  - Parser in `GridCodec.Schema.Parser`
- **Sigils for inline schemas**: `~g` (runtime) and `~G` (compile-time) sigils
  - Define schemas directly in Elixir code for tests and prototyping
  - `import GridCodec.Schema.Sigil` to use
- **Load structs from `.grid` files**: `use GridCodec.Struct, grid_file: "path/to/schema.grid", message: :Order`
- **Load structs from sigils**: `use GridCodec.Struct, grid_schema: ~G"...", message: :Order`
- **`:uuid_string` type**: UUID stored as 16 bytes but decoded to human-readable string format
  - JSON-safe: no need for custom encoder protocols
  - Same binary efficiency as `:uuid` type
- **`GridCodec.Json` module**: Simple JSON transcoder wrapper
  - `GridCodec.Json.encode(binary, Schema)` - binary → JSON string
  - `GridCodec.Json.decode(json, Schema)` - JSON string → binary
  - Works with structs that have JSON-safe types (use `:uuid_string` instead of `:uuid`)
- **Compile-time safety for `match/1,2` macro**: Matching on literal `nil` now raises
  a `CompileError` with a helpful message

### Changed
- Improved documentation for `match/1,2` macro to clearly explain that it returns
  raw sentinel values for nullable fields, not `nil`. Use `get/2` for null-safe access.

## [0.6.0] - 2026-01-08

### Removed
- **Breaking: Removed `GridCodec.Envelope` module entirely**
  - Use `MyCodec.get(binary, :field)` macro for zero-copy field access
  - Use `MyCodec.decode(binary)` for full decoding
- **Breaking: Removed `wrap/1` and `wrap/2` functions**
  - `MyCodec.wrap(binary)` is no longer available
  - `GridCodec.wrap(binary)` is no longer available
  - `Dispatch.wrap(binary)` is no longer available
- Removed `__field_info__/1` runtime function (was internal to Envelope)

### Rationale
- **Simplicity**: Envelopes added complexity without meaningful benefit
- **Performance**: Direct `get/2` macro is faster than envelope-based access
- **API clarity**: One clear way to access fields - the `get/2` macro

## [0.5.0] - 2026-01-08

### Changed
- **Breaking: New encode/decode API** - Header is now included by default
  - `encode(struct)` → includes 8-byte header (was payload only)
  - `encode(struct, header: false)` → payload only (new)
  - `decode(binary)` → expects header (was payload only)
  - `decode(binary, header: false)` → expects payload only (new)
  - Removed `encode!/1` and `decode!/1` (use `encode/1` and `decode/1` instead)
- **Breaking: Simplified field access API**
  - Renamed `get!/2` macro to `get/2` (no more bang suffix)
  - Removed slow function-based `get/2` - now only the fast macro exists
- **Zero-copy access updated for header-by-default**
  - `get/2` macro now expects framed binary with header by default
  - `get(binary, :field, header: false)` for payload-only access
  - `match/1` macro expects framed binary by default
  - `match([field: v], header: false)` for payload-only patterns
- `Dispatch.decode/1` updated for new API
- `GridCodec.Registry.encode/2` now accepts options
- Updated moduledoc with new API examples

### Rationale
- **Consistency**: `GridCodec.encode(struct)` and `MyCodec.encode(struct)` now produce identical binaries
- **Usability**: Follows pattern from popular libraries like Jason (`encode/2` with options)
- **Simplicity**: One way to access fields from binary (`get/2` macro), one way from envelope (`Envelope.get`)
- **Performance**: Fast path for `encode(struct)` (no options) has zero overhead
- **Dispatch**: Header enables `GridCodec.decode/1` to route to correct codec automatically

## [0.4.0] - 2026-01-08

### Added
- **`get/2` macro**: Inline field access with compile-time binary pattern matching
  - Expands at compile time to direct binary pattern, achieving ~70M ops/sec
  - Handles null values automatically (returns `nil` for sentinel values)
  - Use: `require MyCodec; MyCodec.get(binary, :field_name)`
- **`field/1` macro**: Generate field specs for generic access
  - Returns `{type_module, offset, endian}` tuple at compile time
  - Use: `GridCodec.get(binary, MyCodec.field(:price))`
- **`GridCodec.get/2`**: Generic field access with field specs
  - Runtime dispatch via type module's `get_value/3` callback
  - Used by `Envelope.get/2` for dynamic field access
- **`get_value/3` callback**: Added to `GridCodec.Type` behaviour
  - Implemented for `:u64`, `:i64`, `:u32`, `:uuid` types
  - Enables runtime field extraction with null handling
- **Benchmark suite**: Maps vs binary field access comparison
  - `example_app/benchmarks/maps_vs_codec.exs`
  - Results documented in `RESULTS_maps_vs_codec.md`

### Changed
- Updated moduledoc with Field Access Methods section documenting performance hierarchy:
  - `get/2` macro: ~70M ips (inline binary pattern with null handling)
  - `match/1` macro: ~70M ips (multi-field extraction, raw bytes)

## [0.3.0] - 2026-01-07

### Added
- **Mix Compiler**: New `:grid_codec` Mix compiler for automatic registry consolidation
  - Scans all loaded modules for GridCodec struct codecs at compile time
  - Generates optimized `GridCodec.Registry` module with pattern-match dispatch
  - Validates no conflicts (duplicate schema_id + template_id combinations)
  - Add to your project with `compilers: Mix.compilers() ++ [:grid_codec]`
- **Production Profiling Tools**: Docker-based profiling suite in `profile/`
  - Two-phase profiling: JIT warmup without perf, then clean profiling
  - JIT symbol resolution via `+JPperf true` for readable Elixir function names
  - Generates flame graphs and detailed reports
  - Profile markers for tagging specific operations in perf output
- **Example Application**: New `example_app/` with benchmarks and sample codecs
  - `OrderCreated` and `TradeExecuted` example events
  - Parameterized benchmarks for different payload sizes
  - Profile runner for integration with profiling tools
- **AI Agent Instructions**: `AGENTS.md` with comprehensive profiling and optimization guide

### Changed
- **Breaking**: Removed legacy map-based codec API - now struct-only via `GridCodec.Struct`
  - Use `use GridCodec.Struct` instead of `use GridCodec`
  - All codecs now define Elixir structs with generated encode/decode functions
  - Simplified API: `encode/1`, `decode/1`, `wrap/1`, `get/2`
- Reorganized compiler into GridCodec.Struct.Compiler (internal module)
- Updated README with struct-only examples and usage

### Fixed
- Dialyzer errors for Mix compiler module (added `:mix` to PLT)
- Bitset type warnings

### Removed
- Legacy `defcodec` macro and map-based codec API
- Old Livebook documentation (moved to example_app benchmarks)
- Planning docs and RFC documents

## [0.2.1] - 2025-12-31

### Added
- Interactive Livebooks for benchmarking and documentation:
  - `01_performance_comparison.livemd` - Compare GridCodec vs JSON, ETF, Protobuf, MessagePack
  - `02_subbinary_fanout.livemd` - Demonstrate BEAM's refc binary sharing for efficient fan-out
  - `03_internal_analysis.livemd` - Deep dive into generated code and BEAM bytecode
- Tests for refc binary sharing behavior (`refc_binary_test.exs`)
- NIF-based JSON benchmark comparison using `jiffy`

### Changed
- Consolidated 30+ benchmark scripts into 3 educational Livebooks
- Updated terminology: "zero-copy" → "direct field access" / "sub-binary sharing"
- `03_internal_analysis.livemd` now accurately reflects implemented optimizations

### Removed
- Legacy benchmark scripts (moved to Livebooks)

## [0.2.0] - 2025-12-30

### Added
- Fast-path encoder using `get_map_elements` BEAM instruction for fixed-only codecs
- Comprehensive nullable roundtrip tests for all types
- Property-based tests for codec correctness
- Fast-path comprehensive tests covering all type combinations
- Enum integration tests
- String variant tests (`:string8`, `:string16`, `:string32`)
- Benchmarking and profiling scripts in `benchmarks/`

### Changed
- **Performance**: Encode is now 1.6-1.7x faster for fixed-field codecs
- **Performance**: Decimal decode is 1.6x faster using direct struct creation
- **Performance**: UUID null check is 220x faster using equality instead of pattern match
- Replaced `Map.get/3` with `:maps.get/3` BIF in all type encoders (~7-8% faster)
- Skip unnecessary binary concatenation when no groups/var fields (5.6x faster)
- Skip unnecessary `Map.merge` in decoder when no groups/var fields
- Inline Decimal struct creation in decode (avoids `Decimal.new/3` validation overhead)

### Fixed
- Float types (`f32`, `f64`) now correctly handle `nil` values (encode as NaN sentinel)
- UUID type now correctly handles `nil` values (encode as all-zeros, decode back to `nil`)
- Enum `encode_ast` now returns proper binary segment expression for fast-path compatibility
- Bitset types now correctly use endianness in bitstring specifiers

## [0.1.0] - 2025-12-29

### Added
- Initial `defcodec` macro for defining binary schemas
- Support for fixed-size fields: `:u8`, `:u16`, `:u32`, `:u64`, `:i8`, `:i16`, `:i32`, `:i64`
- Support for float fields: `:f32`, `:f64`
- Support for `:uuid` (16-byte binary) and `:bool` fields
- Support for variable-length `:string` fields with `:string8`, `:string16`, `:string32` variants
- Support for `:decimal` (9-byte mantissa + exponent) fields
- Support for `:timestamp_us` and `:timestamp_ns` fields
- Support for custom enum types via `GridCodec.Types.Enum`
- Support for bitset types via `GridCodec.Types.Bitset`
- Support for char array types via `GridCodec.Types.CharArray`
- Support for repeating groups via `GridCodec.Group`
- `encode/1` - Encode map to binary
- `decode/1` - Decode binary to map
- `wrap/1` - Wrap binary for zero-copy access
- `get/2` - Get field from wrapped binary without full decode
- Configurable endianness (`:little` or `:big`)
- Schema versioning support
- SBE-style null sentinels for optional fields

