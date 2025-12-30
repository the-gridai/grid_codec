# Native Code Inspection
#
# Uses various BEAM introspection techniques to understand the generated code

IO.puts(String.duplicate("=", 80))
IO.puts("NATIVE CODE INSPECTION")
IO.puts(String.duplicate("=", 80))

# Pre-compile a codec module
defmodule InspectCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

IO.puts("\nCodec loaded: #{inspect(InspectCodec)}")

# Method 1: Check if disassembly functions are available
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("Available :erts_debug functions:")
IO.puts(String.duplicate("-", 80))

erts_exports =
  :erts_debug.module_info(:exports)
  |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)
  |> Enum.sort()

IO.puts("  " <> Enum.join(erts_exports, ", "))

# Method 2: Get function info
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("Function info for InspectCodec.encode/1:")
IO.puts(String.duplicate("-", 80))

try do
  # Get the function reference
  fun = &InspectCodec.encode/1

  # Function info
  fun_info = Function.info(fun)
  IO.puts("  Module: #{fun_info[:module]}")
  IO.puts("  Name: #{fun_info[:name]}")
  IO.puts("  Arity: #{fun_info[:arity]}")
  IO.puts("  Env: #{inspect(fun_info[:env])}")
  IO.puts("  Type: #{fun_info[:type]}")
rescue
  e -> IO.puts("Error: #{inspect(e)}")
end

# Method 3: Process dictionary and internals
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("Memory and process info during encoding:")
IO.puts(String.duplicate("-", 80))

data = %{id: 12345678901234, count: 1000000, flag: true}

# Get baseline
:erlang.garbage_collect()
{:reductions, red_before} = Process.info(self(), :reductions)
{:memory, mem_before} = Process.info(self(), :memory)

# Run encoding
for _ <- 1..100_000 do
  InspectCodec.encode(data)
end

{:reductions, red_after} = Process.info(self(), :reductions)
{:memory, mem_after} = Process.info(self(), :memory)

reductions_per_encode = (red_after - red_before) / 100_000

IO.puts("  Reductions per encode: #{Float.round(reductions_per_encode, 2)}")
IO.puts("  Memory before: #{mem_before} bytes")
IO.puts("  Memory after: #{mem_after} bytes")
IO.puts("  Memory delta: #{mem_after - mem_before} bytes")

# Method 4: Inspect binary construction
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("Binary output analysis:")
IO.puts(String.duplicate("-", 80))

binary = InspectCodec.encode(data)
IO.puts("  Size: #{byte_size(binary)} bytes")
IO.puts("  Content: #{inspect(binary)}")

# Check if it's a heap binary or refc binary
is_heap = byte_size(binary) < 64
IO.puts("  Type: #{if is_heap, do: "heap binary (no refcount)", else: "refc binary"}")

# Method 5: Scheduler info during workload
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("Scheduler utilization:")
IO.puts(String.duplicate("-", 80))

:erlang.system_flag(:scheduler_wall_time, true)
sw1 = :erlang.statistics(:scheduler_wall_time)

for _ <- 1..1_000_000 do
  InspectCodec.encode(data)
end

sw2 = :erlang.statistics(:scheduler_wall_time)
:erlang.system_flag(:scheduler_wall_time, false)

util =
  Enum.zip(Enum.sort(sw1), Enum.sort(sw2))
  |> Enum.map(fn {{i, a1, t1}, {_, a2, t2}} ->
    util = if t2 - t1 > 0, do: (a2 - a1) / (t2 - t1) * 100, else: 0
    {i, Float.round(util, 1)}
  end)

for {i, u} <- util do
  if u > 0, do: IO.puts("  Scheduler #{i}: #{u}%")
end

# Method 6: GC analysis
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("GC behavior during 1M encodes:")
IO.puts(String.duplicate("-", 80))

:erlang.garbage_collect()
gc_before = :erlang.statistics(:garbage_collection)

for _ <- 1..1_000_000 do
  InspectCodec.encode(data)
end

gc_after = :erlang.statistics(:garbage_collection)

{gc_count_before, _, _} = gc_before
{gc_count_after, _, _} = gc_after

IO.puts("  GC count: #{gc_count_after - gc_count_before}")
IO.puts("  GC per 1000 encodes: #{Float.round((gc_count_after - gc_count_before) / 1000, 2)}")

# Method 7: Timing with :timer.tc
IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("Precise timing:")
IO.puts(String.duplicate("-", 80))

{encode_time, _} =
  :timer.tc(fn ->
    for _ <- 1..100_000 do
      InspectCodec.encode(data)
    end
  end)

{decode_time, _} =
  :timer.tc(fn ->
    for _ <- 1..100_000 do
      InspectCodec.decode(binary)
    end
  end)

{get_time, _} =
  :timer.tc(fn ->
    for _ <- 1..100_000 do
      InspectCodec.get(binary, :id)
    end
  end)

IO.puts("  Encode: #{Float.round(encode_time / 100_000, 2)} µs/op (#{Float.round(encode_time / 100_000 * 1000, 1)} ns)")
IO.puts("  Decode: #{Float.round(decode_time / 100_000, 2)} µs/op (#{Float.round(decode_time / 100_000 * 1000, 1)} ns)")
IO.puts("  Get:    #{Float.round(get_time / 100_000, 2)} µs/op (#{Float.round(get_time / 100_000 * 1000, 1)} ns)")

# Summary
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("SUMMARY")
IO.puts(String.duplicate("=", 80))

IO.puts("""

PERFORMANCE CHARACTERISTICS:
----------------------------
- Reductions per encode: #{Float.round(reductions_per_encode, 2)} (lower is better, ~5-10 is excellent)
- GC per 1000 ops: #{Float.round((gc_count_after - gc_count_before) / 1000, 2)} (lower is better)
- Binary type: #{if is_heap, do: "heap (optimal)", else: "refc (watch for contention)"}

WHAT THIS MEANS:
----------------
- Low reductions = efficient bytecode (JIT doing its job)
- Low GC = minimal allocation (good for latency)
- Heap binary = no reference counting overhead

FOR DEEP PROFILING:
-------------------
Since this Erlang build doesn't include :msacc, :lcnt, :fprof, etc.,
you'll need to use external tools:

1. perf (Linux):
   sudo perf stat -e instructions,cycles,cache-misses -p <PID>

2. FlameGraph:
   ERL_FLAGS="+JPperf true" mix run workload.exs &
   sudo perf record -F 999 -g -p <PID>

3. GDB (for live inspection):
   gdb -p <PID>
   (gdb) info registers

""")
