# Native C-Level Profiling of BEAM
#
# Options for profiling at the C/native level:
# 1. perf (Linux) - profiles JIT-compiled native code
# 2. Valgrind - profiles BEAM VM (very slow)
# 3. DTrace/SystemTap - BEAM has built-in probes
# 4. gprof - if BEAM compiled with profiling

IO.puts(String.duplicate("=", 70))
IO.puts("NATIVE PROFILING OPTIONS FOR BEAM")
IO.puts(String.duplicate("=", 70))

# Check what tools are available
IO.puts("\nChecking available profiling tools...")

tools = [
  {"perf", "perf --version 2>/dev/null"},
  {"valgrind", "valgrind --version 2>/dev/null"},
  {"strace", "strace --version 2>/dev/null"},
  {"ltrace", "ltrace --version 2>/dev/null"},
  {"gdb", "gdb --version 2>/dev/null | head -1"}
]

for {name, cmd} <- tools do
  result = System.cmd("sh", ["-c", cmd], stderr_to_stdout: true)

  case result do
    {output, 0} -> IO.puts("  ✅ #{name}: #{String.trim(output) |> String.split("\n") |> hd()}")
    _ -> IO.puts("  ❌ #{name}: not found")
  end
end

# Check BEAM compilation options
IO.puts("\nBEAM VM Information:")
IO.puts("  Emulator: #{:erlang.system_info(:system_architecture)}")
IO.puts("  OTP Version: #{:erlang.system_info(:otp_release)}")
IO.puts("  ERTS Version: #{:erlang.system_info(:version)}")
IO.puts("  Flavor: #{:erlang.system_info(:emu_flavor)}")
IO.puts("  Word size: #{:erlang.system_info(:wordsize) * 8} bit")

# Check for debug/profiling builds
IO.puts("\nBEAM Build Info:")
build_info = :erlang.system_info(:build_type)
IO.puts("  Build type: #{build_info}")

# Check if JIT is generating symbols
IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PROFILING APPROACHES")
IO.puts(String.duplicate("-", 70))

IO.puts("""

## 1. Linux perf (RECOMMENDED)

The BEAM JIT generates perf-compatible symbols since OTP 25.
This lets you see which Erlang functions are hot at native level.

### Setup:
```bash
# Enable perf for non-root (may need sudo)
echo 0 | sudo tee /proc/sys/kernel/perf_event_paranoid
echo 0 | sudo tee /proc/sys/kernel/kptr_restrict

# Record profile while running Elixir code
perf record -g mix run benchmarks/profile_encode.exs -- simple

# View results
perf report

# Generate flame graph
perf script | stackcollapse-perf.pl | flamegraph.pl > flame.svg
```

### What you'll see:
- Time in `beam.smp` (the BEAM VM)
- Time in JIT-compiled Erlang code
- Time in BIFs (C implementations)
- System calls (mmap, futex, etc.)

## 2. Valgrind (SLOW but detailed)

Valgrind instruments every instruction - extremely slow but precise.

### Setup:
```bash
# Cachegrind - cache/branch profiling
valgrind --tool=cachegrind erl -noshell -eval 'your:code()' -s init stop

# Callgrind - call graph profiling
valgrind --tool=callgrind erl -noshell -eval 'your:code()' -s init stop

# View with KCachegrind
kcachegrind callgrind.out.*
```

### Caveats:
- 10-50x slower than normal execution
- JIT code may not have symbols
- Mostly shows BEAM internals

## 3. DTrace / SystemTap (if available)

BEAM has built-in DTrace/SystemTap probes.

### Check if enabled:
```erlang
:erlang.system_info(:dynamic_trace)
```

### DTrace example (macOS/Solaris):
```bash
dtrace -n 'erlang*:process-spawn { printf("spawn!") }'
```

### SystemTap example (Linux):
```bash
stap -e 'probe process("beam.smp").mark("process-spawn") { println("spawn!") }'
```

## 4. strace (System Call Analysis)

Shows what system calls BEAM makes - useful for I/O profiling.

```bash
strace -c mix run benchmarks/profile_encode.exs -- simple
```

## 5. BEAM's Native Profilers

These are the most practical for Elixir code:

```bash
# tprof - total profiler (OTP 27+)
mix profile.tprof benchmarks/profile_encode.exs -- simple

# eprof - time profiler
mix profile.eprof benchmarks/profile_encode.exs -- simple

# fprof - detailed call graph
mix profile.fprof benchmarks/profile_encode.exs -- simple
```
""")

# Check DTrace support
dtrace_support = :erlang.system_info(:dynamic_trace)
IO.puts("\nDTrace/SystemTap support: #{dtrace_support}")

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("RUNNING ACTUAL NATIVE PROFILE")
IO.puts(String.duplicate("-", 70))

# Let's create a workload to profile
IO.puts("\nCreating workload for profiling...")

defmodule ProfileWorkload do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

# Warm up
data = %{id: 12345, count: 100, flag: true}
binary = ProfileWorkload.encode(data)

for _ <- 1..100_000 do
  ProfileWorkload.encode(data)
  ProfileWorkload.decode(binary)
end

IO.puts("Warmup complete. Ready for native profiling.")

IO.puts("""

To profile with perf, run:

```bash
# Record 10 seconds of encoding
perf record -F 999 -g -- mix run -e '
  data = %{id: 12345, count: 100, flag: true}
  for _ <- 1..10_000_000 do
    ProfileWorkload.encode(data)
  end
'

# View report
perf report --stdio
```
""")
