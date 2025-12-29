# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial `defcodec` macro for defining binary schemas
- Support for fixed-size fields: `:u8`, `:u16`, `:u32`, `:u64`, `:i8`, `:i16`, `:i32`, `:i64`
- Support for float fields: `:f32`, `:f64`
- Support for `:uuid` (16-byte binary) and `:bool` fields
- Support for variable-length `:string` fields
- `encode/1` - Encode map to binary
- `decode/1` - Decode binary to map
- `wrap/1` - Wrap binary for zero-copy access
- `get/2` - Get field from wrapped binary without full decode
- Configurable endianness (`:little` or `:big`)
- Schema versioning support

