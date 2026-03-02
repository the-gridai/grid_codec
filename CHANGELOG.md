# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

