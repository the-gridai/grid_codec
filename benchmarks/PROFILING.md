# C-Level Profiling Guide for GridCodec.Struct

This guide explains how to use C-level profiling and tracing tools to analyze GridCodec.Struct performance.

## Tools Available

### 1. Erlang-Level Profiling

#### :fprof (Function Profiler)
Profiles function calls and execution time:

```bash
mix run benchmarks/c_level_profiling.exs
```

This generates:
- `fprof_encode_struct.txt` - Encode profiling
- `fprof_decode_struct.txt` - Decode profiling
- `fprof_encode_hand.txt` - Hand-rolled comparison
- `fprof_decode_hand.txt` - Hand-rolled comparison

#### :eprof (Time Profiler)
Profiles time spent in functions:

```bash
mix run benchmarks/c_level_profiling.exs
```

Generates `eprof_encode_struct.txt` with time-based analysis.

### 2. JIT Analysis

Check JIT compilation status and hot paths:

```bash
mix run benchmarks/jit_analysis.exs
```

### 3. C-Level Profiling (macOS)

#### Using Instruments (macOS)

```bash
# Record profiling data
instruments -t "Time Profiler" -D profile.trace mix run benchmarks/struct_vs_legacy_bench.exs

# View results
open profile.trace
```

#### Using DTrace (macOS/Linux)

```bash
# Profile function calls
sudo dtrace -n 'pid$target:beam.smp::entry { @[probefunc] = count(); }' -p $(pgrep -f "beam.smp")

# Profile CPU time
sudo dtrace -n 'profile-997 /pid == $target/ { @[ustack()] = count(); }' -p $(pgrep -f "beam.smp")
```

### 4. Linux perf (if on Linux)

```bash
# Record profiling
perf record -g -- mix run benchmarks/struct_vs_legacy_bench.exs

# View report
perf report

# View with call graph
perf report -g graph,0.5,caller
```

### 5. :recon (Runtime Analysis)

Add to your code:

```elixir
# Identify hot functions
:recon.hot(100)  # Top 100 functions by call count

# Function info
:recon.info(TestOrder, :encode, 1)

# Process info
:recon.proc_count(:message_queue_len, 10)
```

## Performance Optimization Checklist

### 1. Verify JIT Compilation
- [ ] Check JIT is enabled (`:erlang.system_info(:emu_flavor) == :jit`)
- [ ] Warm up functions (100K+ iterations)
- [ ] Verify functions are JIT-compiled

### 2. Analyze Hot Paths
- [ ] Use `:fprof` to identify most-called functions
- [ ] Use `:eprof` to identify time-consuming functions
- [ ] Use `perf`/`instruments` for C-level hot paths

### 3. Check Inlining Opportunities
- [ ] Small functions (< 5 instructions) should inline
- [ ] Avoid function calls in tight loops
- [ ] Use `@compile {:inline, [function: arity]}` hints

### 4. Binary Operations
- [ ] Minimize `bs_create_bin` operations
- [ ] Use single binary construction `<<...>>` when possible
- [ ] Avoid binary concatenation

### 5. Pattern Matching
- [ ] Use pattern matching on function heads
- [ ] Avoid `case` statements in hot paths
- [ ] Prefer `cond` or pattern matching over `if/else`

### 6. Memory Allocations
- [ ] Minimize intermediate data structures
- [ ] Use direct struct creation (not map -> struct)
- [ ] Avoid unnecessary copying

## Example Workflow

1. **Baseline Measurement**
   ```bash
   mix run benchmarks/struct_vs_legacy_bench.exs
   ```

2. **Erlang-Level Profiling**
   ```bash
   mix run benchmarks/c_level_profiling.exs
   ```

3. **JIT Analysis**
   ```bash
   mix run benchmarks/jit_analysis.exs
   ```

4. **C-Level Profiling** (macOS)
   ```bash
   instruments -t "Time Profiler" -D profile.trace mix run benchmarks/struct_vs_legacy_bench.exs
   ```

5. **Analyze Results**
   - Review `fprof_*.txt` for function call counts
   - Check `eprof_*.txt` for time distribution
   - Open `profile.trace` in Instruments for C-level analysis

6. **Apply Optimizations**
   - Add JIT hints
   - Inline small functions
   - Optimize hot paths
   - Reduce allocations

7. **Verify Improvements**
   ```bash
   mix run benchmarks/struct_vs_legacy_bench.exs
   ```

## JIT Hints

Add to your codec modules:

```elixir
defmodule MyCodec do
  use GridCodec.Struct
  
  # Hint for JIT: inline small functions
  @compile {:inline, [encode: 1, decode: 1]}
  
  defcodec do
    # ...
  end
end
```

## Common Optimizations

1. **Direct Struct Pattern Matching**
   ```elixir
   # Good: Direct pattern match
   def encode(%MyStruct{field: value} = struct) do
     <<value::little-64>>
   end
   
   # Bad: Map conversion
   def encode(struct) do
     data = Map.from_struct(struct)
     <<data.field::little-64>>
   end
   ```

2. **Single Binary Construction**
   ```elixir
   # Good: Single binary
   <<field1::little-32, field2::little-64, field3::binary>>
   
   # Bad: Concatenation
   <<field1::little-32>> <> <<field2::little-64>> <> field3
   ```

3. **Nil Coalescing**
   ```elixir
   # Good: Direct || operator (for non-booleans)
   value || default
   
   # Bad: case statement
   case value do
     nil -> default
     v -> v
   end
   ```

## Interpreting Results

### :fprof Output
- `own` time: Time spent in the function itself
- `acc` time: Accumulated time (including called functions)
- `calls`: Number of function calls

### :eprof Output
- Shows time distribution across functions
- Helps identify bottlenecks

### perf/instruments Output
- Shows C-level CPU time
- Identifies assembly-level hot paths
- Helps with JIT optimization

## Next Steps

1. Run profiling tools
2. Identify bottlenecks
3. Apply optimizations
4. Re-measure performance
5. Iterate until performance goals are met

