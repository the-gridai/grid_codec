# Deep Low-Level Profiling for GridCodec

This directory contains tools for profiling GridCodec at the hardware and VM level,
going far beyond bytecode analysis.

## Prerequisites

```bash
# Install perf (Linux)
sudo apt-get install linux-tools-generic linux-tools-$(uname -r)

# Install FlameGraph tools
git clone https://github.com/brendangregg/FlameGraph.git ~/FlameGraph

# For LTTng (optional, requires kernel support)
sudo apt-get install lttng-tools lttng-modules-dkms
```

## 1. Perf with JIT Support

Start the BEAM with JIT perf mapping enabled:

```bash
# Set the flag
export ERL_FLAGS="+JPperf true"

# Run the benchmark
mix run benchmarks/deep_profiling/perf_workload.exs &
PID=$!

# Record with perf (hardware counters)
sudo perf stat -e instructions,cycles,cache-references,cache-misses,branches,branch-misses -p $PID

# Or record for flame graph
sudo perf record -F 999 -g -p $PID -- sleep 10
```

## 2. Hardware Performance Counters

Key metrics for SBE-style encoding:

| Metric | Target | Meaning |
|--------|--------|---------|
| IPC (Instructions/Cycle) | > 1.5 | CPU efficiency |
| Branch Miss Rate | < 2% | Pattern match efficiency |
| Cache Miss Rate | < 5% | Memory locality |
| L1 Cache Hits | > 95% | Data fits in cache |

## 3. JIT Assembly Inspection

```elixir
# Dump the native code for a codec
:erts_debug.df(MyCodec)  # Dumps to file
:erts_debug.display_vcode(MyCodec)  # Prints to stdout
```

## 4. Microstate Accounting

```elixir
:msacc.start(5000)
# Run workload
stats = :msacc.stop()
:msacc.print(stats)
```

Key states:
- `emulator`: Executing Erlang/Elixir code (want this high)
- `gc`: Garbage collection (want this low)
- `bin_vheap`: Binary heap management (watch for zero-copy issues)

## 5. Lock Contention (requires OTP with --enable-lock-counter)

```elixir
:lcnt.rt_collect()
# Run workload
:lcnt.inspect(:all, [{:sort, :collisions}])
```

Watch for `refc_binary` lock contention on shared binaries.

## Files

- `perf_workload.exs` - Sustained workload for perf recording
- `jit_inspection.exs` - Dump and analyze JIT assembly
- `msacc_profile.exs` - Microstate accounting analysis
- `hardware_counters.exs` - Hardware counter interpretation
- `flamegraph.sh` - Generate flame graphs from perf data

