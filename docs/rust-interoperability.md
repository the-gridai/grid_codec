# Rust interoperability

GridCodec includes two Rust components under `native/`:

- `native/grid_codec` is a safe Rust implementation of the common GridCodec wire primitives.
- `native/grid_codec_nif` is an experimental Rustler bridge used for parity tests and profiling.

The Rust core supports the eight-byte little-endian header, fixed-width numeric values, nullable booleans and UUIDs, length-prefixed strings and bytes, group headers, borrowed reads, typed encode/decode traits, and structured errors. Elixir-generated fixtures under `test/fixtures/` are consumed by Rust tests so the Elixir implementation remains the wire-format authority.

The Rustler module is intentionally opt-in and exists primarily as a test adapter. Shared ExUnit cases encode one schema with generated Elixir code, decode and access it through Rust, and compare the results in both directions. This lets new Rust operations reuse the Elixir implementation as the wire-format oracle without making NIFs the production default.

## Three-tier operation benchmark

The benchmark uses one message and identical wire bytes for field access, encoding, and decoding. It reports three distinct costs:

- `pure_rust/*`: Criterion calls the safe Rust codec directly.
- `rustler/*`: Elixir calls the same Rust operations through one NIF invocation.
- `pure_elixir/*`: generated GridCodec code runs on the BEAM.

A two-core Daytona run on September 29, 2026 measured these representative medians:

| Operation | Pure Rust | Rustler | Pure Elixir |
| --- | ---: | ---: | ---: |
| Field access | 1.8 ns | 61.2 ns | 10.5 ns |
| Encode with a new buffer | 20.9 ns | 116.5 ns | 156.1 ns |
| Encode with a reused buffer | 7.5 ns | Not exposed | Not exposed |
| Decode | 14.1 ns | 167.8 ns | 89.6 ns |

The Rust values include safe bounds checks and contain no `unsafe` code. Direct header parsing reduced field access by 66%. Exact capacity hints removed a second allocation and reduced ordinary encoding by 52%. `Encode.encode_to/2` reuses caller-owned storage and reduced encoding by another 64%. The generic decode experiment did not produce a significant gain, so this change keeps the simpler reader path.

Generated BEAM field access remains excellent. The NIF boundary dominates tiny reads and decodes. Rust encoding offsets that boundary for this fixture. Production adoption must use realistic schemas and batches, not this microbenchmark. Treat absolute values as machine-specific and compare tiers from the same run.

### Compile-time layout paths

GridCodec schemas know each fixed field's width and offset. Generated Rust codecs can use that information without a dynamic cursor:

- `BenchmarkMessage.encode_into` writes directly into caller-owned memory and checks its total size once.
- `BenchmarkMessageView.new` validates the header, fixed block, boolean, variable length, and UTF-8 once.
- View getters use generated constant offsets after validation.

The same Daytona host measured 4.4 ns for `encode_into` and 0.9 ns for field access through a validated view. These paths preserve the GridCodec wire format and safe-Rust policy.

### Techniques reviewed

[Speedy](https://docs.rs/speedy/latest/speedy/) generates minimum byte counts, checks buffer capacity before decode, borrows variable data, and bulk-copies primitive slices. Its pointer readers and unaligned reads use `unsafe`. GridCodec uses the compile-time size and borrowing ideas, but keeps safe indexing and explicit little-endian conversion.

[OxiCode](https://github.com/cool-japan/oxicode) provides exact encoded sizes, caller-provided fixed arrays, borrowed decoding, and separate SIMD bulk-array paths. GridCodec adopts exact size hints and caller-provided output. SIMD is not useful for one small message. It can help large homogeneous groups later.

[`ser_raw`](https://docs.rs/ser_raw/latest/ser_raw/) copies native Rust object memory into aligned storage. That is fast for same-binary IPC, but native layout and pointers do not satisfy GridCodec's stable cross-language wire contract. GridCodec does not adopt this representation.

[Rusteron](https://github.com/gsrxyz/rusteron) optimizes transport and C bindings, not schema serialization. Its reusable buffers and separation of control from data support the same allocation strategy, but its unsafe FFI model does not apply to the codec core.

Run the parity and bridge checks with:

```bash
mix test test/grid_codec/native_test.exs test/rust_fixture_test.exs
cargo test --manifest-path native/grid_codec/Cargo.toml
cargo test --manifest-path native/grid_codec_nif/Cargo.toml
```

Regenerate cross-language fixtures with:

```bash
elixir test/fixtures/generate.exs
```

Run the BEAM and Rustler operation benchmark with:

```bash
ITERATIONS=1000000 mix run example_app/benchmarks/native_bridge.exs
```

Run the pure Rust side with:

```bash
cargo bench --manifest-path native/grid_codec/Cargo.toml --bench codec_operations
```
