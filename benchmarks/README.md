# Benchmarks Directory

This directory contains development and profiling benchmarks for GridCodec.

## Note: Example App Benchmarks

For **real-world usage examples** and **benchmarks with consolidated code**, see the `example_app/` directory:

```bash
cd example_app
mix bench
```

The example app provides:
- Real-world event codecs
- Benchmarks with consolidated registry (when compiler is enabled)
- Comparison with other serialization formats
- Production-like usage patterns

## Development Benchmarks

These benchmarks are for development, profiling, and internal analysis:

### Quick Benchmarks
- `quick_bench.exs` - Fast iteration benchmark (~1 second)

### Comprehensive Benchmarks
- `struct_vs_legacy_bench.exs` - Compare Struct vs Legacy vs Hand-rolled
- `comprehensive_bench.exs` - Various codec scenarios
- `struct_bench.exs` - Struct-specific benchmarks

### Profiling Tools
- `c_level_profiling.exs` - Erlang-level profiling (:fprof, :eprof)
- `jit_analysis.exs` - JIT (BeamAsm) analysis
- `PROFILING.md` - Profiling guide
- `README_PROFILING.md` - Quick profiling reference

### Verification
- `ast_verification.exs` - Verify generated AST is optimal

## Running Benchmarks

```bash
# Quick benchmark
mix run benchmarks/quick_bench.exs

# Comprehensive comparison
mix run benchmarks/struct_vs_legacy_bench.exs

# Profiling
mix run benchmarks/c_level_profiling.exs
mix run benchmarks/jit_analysis.exs
```

## Future Migration

Some of these benchmarks may be migrated to `example_app/` in the future to:
- Keep the library lightweight
- Provide real-world usage examples
- Test with consolidated code

For now, both locations serve different purposes:
- `benchmarks/` - Development and profiling
- `example_app/benchmarks/` - Real-world usage and consolidated code testing
