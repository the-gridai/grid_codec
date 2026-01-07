# GridCodec.Struct Performance Profiling

## Quick Start

### 1. Run JIT Analysis
```bash
mix run benchmarks/jit_analysis.exs
```

### 2. Run Erlang-Level Profiling
```bash
mix run benchmarks/c_level_profiling.exs
```

### 3. Run C-Level Profiling (macOS)
```bash
instruments -t "Time Profiler" -D profile.trace mix run benchmarks/struct_vs_legacy_bench.exs
open profile.trace
```

## Current Status

✅ **Test Coverage**: 78.49% overall
✅ **All Type Tests**: 14/14 passing (comprehensive coverage of all built-in types)
✅ **Profiling Tools**: Ready for use

## Performance Baseline

From `struct_vs_legacy_bench.exs`:

### ENCODE
- **Struct (new)**: 7.26M ips (1.0x vs hand-rolled)
- **Legacy (map)**: 6.68M ips (0.92x vs hand-rolled)
- **Struct vs Legacy**: 1.09x faster

### DECODE
- **Struct (new)**: 19.56M ips (3.15x vs hand-rolled)
- **Legacy (map)**: 14.65M ips (2.36x vs hand-rolled)
- **Struct vs Legacy**: 1.34x faster

### Memory
- **Dispatch decode**: 400 B (97% reduction from 15KB)
- **Direct decode**: 184 B

## Profiling Workflow

1. **Establish Baseline**
   ```bash
   mix run benchmarks/struct_vs_legacy_bench.exs
   ```

2. **Identify Hot Paths**
   ```bash
   mix run benchmarks/jit_analysis.exs
   mix run benchmarks/c_level_profiling.exs
   ```

3. **C-Level Analysis** (macOS)
   ```bash
   instruments -t "Time Profiler" -D profile.trace mix run benchmarks/struct_vs_legacy_bench.exs
   ```

4. **Apply Optimizations**
   - Add JIT hints (`@compile {:inline, [...]}`)
   - Optimize hot paths
   - Reduce allocations

5. **Verify Improvements**
   ```bash
   mix run benchmarks/struct_vs_legacy_bench.exs
   ```

## Optimization Opportunities

### 1. JIT Hints
Add to codec modules:
```elixir
@compile {:inline, [encode: 1, decode: 1]}
```

### 2. Inlining
Small functions (< 5 instructions) should inline automatically, but explicit hints help.

### 3. Binary Operations
- ✅ Already using single binary construction `<<...>>`
- ✅ No binary concatenation
- ✅ Direct pattern matching

### 4. Pattern Matching
- ✅ Direct struct pattern matching in encode
- ✅ Direct struct creation in decode
- ✅ No intermediate maps

## Next Steps

1. Run profiling tools to identify bottlenecks
2. Apply JIT hints where beneficial
3. Measure improvements
4. Iterate until performance goals are met

See `PROFILING.md` for detailed instructions.

