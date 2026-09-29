# Rust interoperability

GridCodec includes two Rust components under `native/`:

- `native/grid_codec` is a safe Rust implementation of the common GridCodec wire primitives.
- `native/grid_codec_nif` is an experimental Rustler bridge used for parity tests and profiling.

The Rust core supports the eight-byte little-endian header, fixed-width numeric values, nullable booleans and UUIDs, length-prefixed strings and bytes, group headers, borrowed reads, typed encode/decode traits, and structured errors. Elixir-generated fixtures under `test/fixtures/` are consumed by Rust tests so the Elixir implementation remains the wire-format authority.

The Rustler module is intentionally opt-in. Generated BEAM pattern matching remains the default. A two-core, one-million-iteration microbenchmark measured:

- BEAM header decode: 519 ns/op
- Rustler header decode: 1,507 ns/op
- BEAM primitive pattern match: 131 ns/op
- Rustler primitive decode: 1,385 ns/op

Crossing the NIF boundary makes tiny operations slower. Native code should be considered for large batches, schema compilation, checksums, compression, or other operations that amortize that boundary—not ordinary single-field access.

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

Run the bridge microbenchmark with:

```bash
ITERATIONS=1000000 mix run example_app/benchmarks/native_bridge.exs
```
