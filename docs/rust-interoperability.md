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
| Field access | 5.3 ns | 61.2 ns | 10.5 ns |
| Encode | 41.2 ns | 116.5 ns | 156.1 ns |
| Decode | 14.5 ns | 167.8 ns | 89.6 ns |

The benchmark confirms the intended boundary: generated BEAM field access is excellent, while the NIF boundary dominates tiny native reads and decodes. Rust encoding can offset that boundary for this fixture, but production adoption should still be based on realistic schemas and batches rather than this microbenchmark. Treat absolute values as machine-specific and compare tiers from the same run.

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
