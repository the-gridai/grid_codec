# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

