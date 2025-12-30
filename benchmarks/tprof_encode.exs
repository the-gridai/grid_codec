# Profiling script for mix profile.tprof
# Run with: mix profile.tprof benchmarks/tprof_encode.exs

defmodule TprofCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

# Pre-compile and warm up
data = %{id: 12345, count: 100, flag: true}
binary = TprofCodec.encode(data)

# Warmup JIT
for _ <- 1..10_000 do
  TprofCodec.encode(data)
  TprofCodec.decode(binary)
end

# The actual profiled workload
for _ <- 1..100_000, do: TprofCodec.encode(data)
