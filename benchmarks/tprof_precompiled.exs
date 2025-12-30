# Profiling with pre-compiled codec
# Run with: mix profile.tprof benchmarks/tprof_precompiled.exs

alias GridCodec.ProfilingCodec

data = %{id: 12345, count: 100, flag: true}
binary = ProfilingCodec.encode(data)

# Warmup JIT
for _ <- 1..10_000 do
  ProfilingCodec.encode(data)
  ProfilingCodec.decode(binary)
end

# The actual profiled workload - just encoding
for _ <- 1..100_000, do: ProfilingCodec.encode(data)
