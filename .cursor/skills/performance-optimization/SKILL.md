---
name: performance-optimization
description: Profile and optimize GridCodec encode/decode performance using tprof, Benchee, and perf. Use when investigating bottlenecks, running benchmarks, inlining AST, or comparing approaches.
---

# Performance Optimization for GridCodec

## Profiling Workflow

1. **Identify the hot path** with `mix profile.tprof`:
   ```elixir
   Mix.Tasks.Profile.Tprof.profile(fn -> work end,
     type: :time, sort: :time, report: :total, set_on_spawn: false)
   ```
   Run `:memory` type too for allocation analysis.

2. **Measure with Benchee** (never hand-rolled timer loops):
   ```elixir
   Benchee.run(%{"name" => fn -> work end}, warmup: 2, time: 5, memory_time: 1)
   ```

3. **Iterate**: profile → identify bottleneck → fix → re-profile → verify improvement.

## Key Optimization Patterns

### AST Inlining
The #1 pattern in this codebase. Replace runtime function calls in `encode_ast`/`decode_value_ast` with inline `case` expressions. The JIT can optimize inline code but can't see through function captures or dynamic dispatch.

**Signs a type needs inlining:**
- `ModuleName.some_function/1` appears in tprof with high call count
- IIFE pattern `(fn -> ... end).()` in encode_ast
- Dynamic dispatch through `&module.fun/arity` capture

**Template:**
```elixir
# Before (runtime call):
def encode_ast(name, default, _endian, data_var) do
  quote do
    MyModule.encode_value(:maps.get(unquote(name), unquote(data_var), unquote(default))) :: binary
  end
end

# After (inline):
def encode_ast(name, default, _endian, data_var) do
  quote do
    (case :maps.get(unquote(name), unquote(data_var), unquote(default)) do
      nil -> <<null_sentinel...>>
      %Struct{field: f} -> <<f::spec>>
    end) :: binary-size(N)
  end
end
```

### Batch Operations
For groups, generate dedicated recursive functions instead of using `Enum.map` + function captures:
- `__encode_<group>_group__/1` — direct local calls, JIT-inlineable
- `__decode_all_<group>__/2` — pattern-matches all fields from binary, no sub-binary allocation

### Parallel Decode
`Group.to_lists_parallel/2` spawns one process per group with pre-sized heaps. Only wins for >256KB total group data. Use `:erlang.spawn_opt` with `min_heap_size` and `fullsweep_after: 0`.

## Benchmark Scripts

- `example_app/benchmarks/group_bench.exs` — realistic exchange shapes with Benchee
- `example_app/benchmarks/group_profile.exs` — tprof time + memory analysis
- `example_app/benchmarks/lazy_decode_bench.exs` — binary scan vs decoded map access
- `example_app/benchmarks/parallel_decode_bench.exs` — parallel vs sequential decode
- `example_app/benchmarks/parallel_threshold.exs` — find the parallel crossover point
- `example_app/benchmarks/constructor_bench.exs` — new/1, coercion, validation, content_hash, decode_only
- `example_app/benchmarks/constructor_profile.exs` — tprof analysis of new/1 internals

## `get(..., copy: true)` (memory vs CPU)

- **Default `get/2`:** zero-copy sub-binary for `:uuid` (no allocation).
- **`copy: true`:** `:binary.copy/1` only when the type implements
  `getter_returns_binary?/0` (`:uuid`, fixed `char_array`). Resolved at macro
  expansion — **no runtime type dispatch**.
- **Do not** set `getter_returns_binary?` on types that already allocate on read
  (`:uuid_string`, `prefixed_id`); `copy: true` would add a useless full copy.
- Integer/bool/`copy: true` expands to the plain getter (identical to `copy: false`).

## Known Non-Optimizations

### IOList vs Binary Concatenation for Encode Assembly

**Do NOT replace `<<fixed::binary, groups::binary>>` with `:erlang.iolist_to_binary([fixed | groups])`.**

Benchmarked on Apple M3 Max, OTP 28.3 (JIT enabled), 2026-03-05:

| Scenario | `<<a, b>>` | `iolist_to_binary` | Result |
|----------|-----------|-------------------|--------|
| 2-part, small (46B + 9B) | 75 ns / 64B | 67 ns / 104B | ~tie |
| 2-part, 4KB groups | 155 ns / 64B | 207 ns / 96B | concat 1.34x faster |
| 2-part, 64KB groups | 954 ns / 64B | 940 ns / 96B | ~tie |
| 3-part (fixed+groups+var) | 75 ns / 64B | 155 ns / 112B | concat 2.06x faster |

The BEAM JIT optimizes `<<a::binary, b::binary>>` into a direct size calculation + memcpy, avoiding iolist traversal overhead. The iolist approach pays for cons cell allocation and list walking. When both inputs are already materialized binaries, binary concat wins.

Benchmark: `example_app/benchmarks/iolist_vs_concat_bench.exs`

## What to Track Per Iteration

Always report improvement vs PREVIOUS step, not just vs baseline:

| Step | Latency | vs previous | vs baseline |
|------|---------|-------------|-------------|
| baseline | X ms | — | — |
| + change A | Y ms | factor | factor |
| + change B | Z ms | factor | factor |
