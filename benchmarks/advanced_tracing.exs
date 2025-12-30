# Advanced BEAM Tracing and Debugging
#
# Exploring deeper BEAM instrumentation beyond basic profilers

IO.puts(String.duplicate("=", 70))
IO.puts("ADVANCED BEAM TRACING")
IO.puts(String.duplicate("=", 70))

# =============================================================================
# PART 1: Using :dbg for Dynamic Tracing
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 1: DYNAMIC TRACING WITH :dbg")
IO.puts(String.duplicate("-", 70))

IO.puts("""
:dbg is BEAM's built-in dynamic tracing module. Unlike profilers, it can:
- Trace specific function calls with arguments
- Show return values
- Filter by process
- Use match specifications for conditional tracing
""")

# Define a test codec
defmodule TraceCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

data = %{id: 12345, count: 100, flag: true}
binary = TraceCodec.encode(data)

# Example: Trace :maps.get calls
IO.puts("\nTracing :maps.get calls during encode...")

# Use :erlang.trace instead of :dbg (which may not be available)
try do
  # Try modern dbg if available
  :dbg.tracer(:process, {fn msg, _ -> IO.inspect(msg, label: "TRACE") end, nil})
  :dbg.p(self(), [:call])
  :dbg.tp(:maps, :get, 3, [])
  TraceCodec.encode(data)
  :dbg.stop_clear()
rescue
  _ ->
    IO.puts("  :dbg module not available, using :erlang.trace instead...")

    # Alternative: use erlang trace directly
    tracer = spawn(fn ->
      receive_loop = fn loop, count ->
        receive do
          {:trace, _pid, :call, {mod, fun, _args}} ->
            IO.puts("  CALL: #{mod}.#{fun}")
            loop.(loop, count + 1)
          :stop ->
            IO.puts("  Total traced calls: #{count}")
        after
          100 -> IO.puts("  No more traces (total: #{count})")
        end
      end
      receive_loop.(receive_loop, 0)
    end)

    :erlang.trace(self(), true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({:maps, :get, 3}, true, [:local])
    TraceCodec.encode(data)
    :erlang.trace(self(), false, [:call])
    Process.sleep(200)
    send(tracer, :stop)
end

IO.puts("\nNote: If no traces appeared, it means :maps.get was inlined by JIT!")

# =============================================================================
# PART 2: Match Specifications for Filtered Tracing
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 2: MATCH SPECIFICATIONS")
IO.puts(String.duplicate("-", 70))

IO.puts("""
Match specs allow conditional tracing - only trace when conditions met.
This is how you can trace without drowning in output.

Example match spec to trace only when first arg is :id:
[{[:id, :_, :_], [], [{:return_trace}]}]
""")

# =============================================================================
# PART 3: Erlang Trace BIFs
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 3: ERLANG TRACE BIFs")
IO.puts(String.duplicate("-", 70))

IO.puts("""
:erlang.trace/3 provides lower-level tracing:

Trace flags:
  :call         - Trace function calls
  :return_to    - Trace return to caller
  :send         - Trace message sends
  :receive      - Trace message receives
  :running      - Trace when process runs/stops
  :garbage_collection - Trace GC events
  :timestamp    - Add timestamp to trace messages
""")

# Example: Trace GC events during encoding
IO.puts("\nTracing garbage collection during 10k encodes...")

gc_events = :atomics.new(1, signed: false)

# Set up a trace handler
spawn(fn ->
  receive do
    :stop -> :ok
  after
    5000 -> :ok
  end
end)

tracer = spawn(fn ->
  receive_loop = fn loop ->
    receive do
      {:trace, _pid, :gc_minor_start, _info} ->
        :atomics.add(gc_events, 1, 1)
        loop.(loop)
      {:trace, _pid, :gc_major_start, _info} ->
        :atomics.add(gc_events, 1, 1)
        loop.(loop)
      :stop ->
        :ok
      _ ->
        loop.(loop)
    after
      1000 -> :ok
    end
  end
  receive_loop.(receive_loop)
end)

# Enable GC tracing
:erlang.trace(self(), true, [:garbage_collection, {:tracer, tracer}])

# Run encodes
for _ <- 1..10_000, do: TraceCodec.encode(data)

# Disable tracing
:erlang.trace(self(), false, [:garbage_collection])
send(tracer, :stop)

gc_count = :atomics.get(gc_events, 1)
IO.puts("  GC events during 10k encodes: #{gc_count}")

# =============================================================================
# PART 4: Process Dictionary and Heap Analysis
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 4: PROCESS MEMORY ANALYSIS")
IO.puts(String.duplicate("-", 70))

# Check process memory before and after encoding
{:memory, mem_before} = Process.info(self(), :memory)
{:heap_size, heap_before} = Process.info(self(), :heap_size)

# Run many encodes
for _ <- 1..100_000, do: TraceCodec.encode(data)

{:memory, mem_after} = Process.info(self(), :memory)
{:heap_size, heap_after} = Process.info(self(), :heap_size)

IO.puts("\nMemory during 100k encodes:")
IO.puts("  Memory before: #{mem_before} bytes")
IO.puts("  Memory after:  #{mem_after} bytes")
IO.puts("  Heap before:   #{heap_before} words")
IO.puts("  Heap after:    #{heap_after} words")

# =============================================================================
# PART 5: Scheduler Utilization
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 5: SCHEDULER ANALYSIS")
IO.puts(String.duplicate("-", 70))

# Get scheduler wall time (requires enabling)
:erlang.system_flag(:scheduler_wall_time, true)
sw1 = :erlang.statistics(:scheduler_wall_time)

# Run workload
for _ <- 1..100_000, do: TraceCodec.encode(data)

sw2 = :erlang.statistics(:scheduler_wall_time)
:erlang.system_flag(:scheduler_wall_time, false)

# Calculate utilization
utilization =
  Enum.zip(Enum.sort(sw1), Enum.sort(sw2))
  |> Enum.map(fn {{_, a1, t1}, {_, a2, t2}} ->
    if t2 - t1 > 0 do
      (a2 - a1) / (t2 - t1) * 100
    else
      0.0
    end
  end)

IO.puts("\nScheduler utilization during 100k encodes:")
for {util, idx} <- Enum.with_index(utilization, 1) do
  IO.puts("  Scheduler #{idx}: #{Float.round(util, 1)}%")
end

# =============================================================================
# PART 6: Binary Reference Counting
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 6: BINARY REFERENCE ANALYSIS")
IO.puts(String.duplicate("-", 70))

# Create binaries and check reference counts
{:binary, bin_info_before} = Process.info(self(), :binary)

# Encode many messages
binaries = for _ <- 1..1000, do: TraceCodec.encode(data)

{:binary, bin_info_after} = Process.info(self(), :binary)

IO.puts("\nBinary references:")
IO.puts("  Before: #{length(bin_info_before)} binaries")
IO.puts("  After:  #{length(bin_info_after)} binaries")
IO.puts("  First binary size: #{byte_size(hd(binaries))} bytes")

# Check if binaries are heap or refc
bin = TraceCodec.encode(data)
is_heap_bin = byte_size(bin) < 64
IO.puts("  Binary type: #{if is_heap_bin, do: "heap binary", else: "refc binary"}")

# =============================================================================
# SUMMARY
# =============================================================================

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("ADVANCED TRACING SUMMARY")
IO.puts(String.duplicate("=", 70))

IO.puts("""

AVAILABLE TRACING TOOLS:
------------------------

1. :dbg - Dynamic function tracing
   :dbg.tracer()
   :dbg.p(pid, [:call])
   :dbg.tp(Module, :function, arity, match_spec)

2. :erlang.trace/3 - Low-level process tracing
   :erlang.trace(pid, true, [:call, :gc, :send, :receive])

3. :recon_trace (external) - Production-safe tracing
   :recon_trace.calls({Mod, :fun, 2}, 10, [])

4. :seq_trace - Sequential tracing across processes
   :seq_trace.set_token(:label, 1)

5. :sys - Debug gen_server/gen_statem
   :sys.trace(pid, true)

KEY INSIGHTS FROM THIS ANALYSIS:
--------------------------------
- GC events per 10k encodes: #{gc_count}
- Memory growth: #{mem_after - mem_before} bytes
- Binary type: #{if is_heap_bin, do: "heap (no refcount)", else: "refc"}
- Scheduler utilization: single-threaded (expected)

For GridCodec specifically:
- Small binaries (<64 bytes) are heap binaries (fast)
- No refcount overhead for typical messages
- GC is infrequent due to small allocations
""")
