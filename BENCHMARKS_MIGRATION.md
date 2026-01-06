# Benchmarks Migration

## Summary

All benchmarks have been migrated from `benchmarks/` to `example_app/benchmarks/` to:
- Test with consolidated code (when Mix compiler is enabled)
- Keep the main library lightweight (no benchmark dependencies)
- Provide real-world usage examples
- Enable proper dependency management

## What Was Migrated

All benchmark files have been moved to `example_app/benchmarks/`:

- ✅ `encode_decode.exs` - Basic encode/decode performance
- ✅ `dispatch.exs` - Dispatch performance
- ✅ `comparison.exs` - Comparison with other codecs
- ✅ `struct_vs_legacy_bench.exs` - Struct vs Legacy comparison
- ✅ `comprehensive_bench.exs` - Various codec scenarios
- ✅ `struct_bench.exs` - Struct-specific benchmarks
- ✅ `quick_bench.exs` - Quick dev benchmark
- ✅ `ast_verification.exs` - AST verification
- ✅ `c_level_profiling.exs` - Profiling tools
- ✅ `jit_analysis.exs` - JIT analysis
- ✅ `PROFILING.md` - Profiling guide (moved to `docs/`)
- ✅ `README_PROFILING.md` - Quick profiling reference (moved to `docs/`)

## New Location

All benchmarks are now in `example_app/benchmarks/`:

```bash
cd example_app
mix bench                    # Run all benchmarks
mix bench.quick              # Quick dev benchmark
mix bench.struct             # Struct vs Legacy
mix bench.comprehensive      # Comprehensive scenarios
mix bench.verify             # AST verification
mix bench.profile            # Profiling tools
mix bench.jit                # JIT analysis
```

## What Remains

- `livebooks/` - Interactive analysis notebooks (they manage deps differently)
- `example_app/` - All benchmarks and profiling tools

## Benefits

1. **Consolidated Code** - Benchmarks run with optimized dispatch when compiler is enabled
2. **Lightweight Library** - Main library has no benchmark dependencies
3. **Real-World Examples** - Benchmarks use actual event codecs
4. **Better Organization** - All benchmark-related code in one place

