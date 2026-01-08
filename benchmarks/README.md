# Benchmarks Directory

Development and profiling benchmarks for GridCodec.

## Quick Start

```bash
# Quick performance check (~3 sec)
mix run benchmarks/struct_bench.exs

# Comprehensive analysis (~5 sec)
mix run benchmarks/comprehensive_bench.exs

# Verify generated code correctness
mix run benchmarks/ast_verification.exs
```

## Benchmark Files

### Performance Benchmarks

| File | Purpose | Time |
|------|---------|------|
| `struct_bench.exs` | Compare struct codec vs hand-rolled | ~3s |
| `comprehensive_bench.exs` | Various codec scenarios + dispatch | ~5s |
| `struct_vs_legacy_bench.exs` | Full analysis with bytecode inspection | ~10s |

### Analysis & Verification

| File | Purpose |
|------|---------|
| `ast_verification.exs` | Verify generated code is correct/optimal |
| `jit_analysis.exs` | JIT (BeamAsm) compilation analysis |
| `c_level_profiling.exs` | Erlang :fprof/:eprof profiling |

### Documentation

| File | Purpose |
|------|---------|
| `PROFILING.md` | Comprehensive profiling guide |
| `README_PROFILING.md` | Quick profiling reference |

## Expected Results (v0.6.0)

### Performance Targets

GridCodec.Struct should be within 15% of hand-rolled code for:
- Encode (payload-only, no header)
- Decode (payload-only, no header)

### Typical Performance

On modern hardware (Apple M-series, Intel i7+):

| Operation | Time | Throughput |
|-----------|------|------------|
| Encode (no header) | ~70ns | 14M ops/s |
| Decode (no header) | ~80-110ns | 9-12M ops/s |
| Get (single field) | ~15-20ns | 50-70M ops/s |
| Encode (w/header) | ~280-350ns | 3M ops/s |
| Decode (w/header) | ~130-180ns | 6-8M ops/s |

### Dispatch Overhead

| Path | Encode | Decode |
|------|--------|--------|
| Direct call | baseline | baseline |
| Protocol/Registry | +10-30% | +5-30% |

## Example App Benchmarks

For real-world usage examples with consolidated registry, see:

```bash
cd example_app
mix run benchmarks/run_all.exs
```

The example app benchmarks test:
- Real event codecs (OrderCreated, TradeExecuted)
- Maps vs binary access comparison
- Parameterized data sizes (small/medium/large)
