# Workload for perf profiling
# Run with: perf record -F 999 -g mix run benchmarks/perf_workload.exs

defmodule PerfCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

data = %{id: 12345, count: 100, flag: true}

# Warm up JIT
IO.puts("Warming up...")
for _ <- 1..100_000, do: PerfCodec.encode(data)

# Main workload
IO.puts("Running 10M encodes...")
{time, _} = :timer.tc(fn ->
  for _ <- 1..10_000_000, do: PerfCodec.encode(data)
end)

IO.puts("Completed in #{div(time, 1000)} ms")
