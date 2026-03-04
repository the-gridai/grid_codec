# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Removed legacy `:types` option on `use GridCodec.Struct`; custom type modules are now
  referenced directly in `field/2` (for example `field :side, MyApp.Types.Side`)
- Improved generated codec typespecs and typedocs:
  - `t()` now emits more specific field types instead of broad `term()`
  - Required fields are typed as non-`nil` in generated struct types
  - `layout()` / `framed_layout()` docs now include compact binary pattern sketches
  - Added literal return specs for generated constant metadata functions

### Added
- Generic top-level types on `GridCodec` for app-level specs:
  - `GridCodec.layout()`
  - `GridCodec.framed_layout()`
  - `GridCodec.codec_struct()`
  - `GridCodec.codec_data()`

### Docs
- Updated docs/examples/tests to reflect direct module type usage and current
  generated typespec behavior

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

