# Sustained Workload for perf Profiling
#
# Run with: ERL_FLAGS="+JPperf true" mix run benchmarks/deep_profiling/perf_workload.exs
#
# Then in another terminal:
#   sudo perf stat -e instructions,cycles,cache-references,cache-misses,branches,branch-misses -p <PID>
#
# Or for flame graph:
#   sudo perf record -F 999 -g -p <PID> -- sleep 10

IO.puts("""
================================================================================
DEEP PROFILING WORKLOAD
================================================================================

This script runs a sustained workload suitable for perf profiling.

USAGE:
  1. Start this script:
     ERL_FLAGS="+JPperf true" mix run benchmarks/deep_profiling/perf_workload.exs

  2. In another terminal, attach perf:
     sudo perf stat -e instructions,cycles,cache-references,cache-misses,branches,branch-misses -p #{System.pid()}

  3. For flame graphs:
     sudo perf record -F 999 -g -p #{System.pid()} -- sleep 10
     sudo perf script | ~/FlameGraph/stackcollapse-perf.pl | ~/FlameGraph/flamegraph.pl > gridcodec_flame.svg

Press Ctrl+C to stop.
================================================================================
""")

# Define test codecs
defmodule PerfCodec.Simple do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

defmodule PerfCodec.Medium do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:timestamp, :timestamp_us)
    field(:price, :u64)
    field(:quantity, :u32)
    field(:side, :u8)
    field(:flags, :u16)
    field(:sequence, :u64)
  end
end

defmodule PerfCodec.WithString do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:type, :u16)
    var_field(:symbol, :string16)
    var_field(:message, :string16)
  end
end

# Test data
simple_data = %{id: 12345678901234, count: 1000000, flag: true}
medium_data = %{
  id: 12345678901234,
  timestamp: System.system_time(:microsecond),
  price: 150_00,
  quantity: 100,
  side: 1,
  flags: 0x0001,
  sequence: 999999
}
string_data = %{id: 12345, type: 1, symbol: "AAPL", message: "Trade executed"}

# Pre-encode for decode tests
simple_bin = PerfCodec.Simple.encode(simple_data)
medium_bin = PerfCodec.Medium.encode(medium_data)
string_bin = PerfCodec.WithString.encode(string_data)

IO.puts("\nBinary sizes:")
IO.puts("  Simple: #{byte_size(simple_bin)} bytes")
IO.puts("  Medium: #{byte_size(medium_bin)} bytes")
IO.puts("  String: #{byte_size(string_bin)} bytes")

IO.puts("\nStarting sustained workload (press Ctrl+C to stop)...")
IO.puts("PID: #{System.pid()}")

# Sustained workload - mix of operations
loop = fn loop, iteration ->
  # Encode operations (most common in SBE use case)
  for _ <- 1..10_000 do
    PerfCodec.Simple.encode(simple_data)
    PerfCodec.Medium.encode(medium_data)
    PerfCodec.WithString.encode(string_data)
  end

  # Decode operations
  for _ <- 1..5_000 do
    PerfCodec.Simple.decode(simple_bin)
    PerfCodec.Medium.decode(medium_bin)
    PerfCodec.WithString.decode(string_bin)
  end

  # Zero-copy access (key SBE feature)
  for _ <- 1..5_000 do
    PerfCodec.Simple.get(simple_bin, :id)
    PerfCodec.Medium.get(medium_bin, :price)
    PerfCodec.Medium.get(medium_bin, :sequence)
  end

  if rem(iteration, 10) == 0 do
    IO.puts("  Iteration #{iteration}: 30k encodes, 15k decodes, 15k gets")
  end

  loop.(loop, iteration + 1)
end

loop.(loop, 1)
