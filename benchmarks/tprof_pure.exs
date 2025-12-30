# Pure profiling - no Enum overhead
# Run with: mix profile.tprof benchmarks/tprof_pure.exs

alias GridCodec.ProfilingCodec

data = %{id: 12345, count: 100, flag: true}
binary = ProfilingCodec.encode(data)

defmodule Loops do
  def encode_n(_, _, 0), do: :ok
  def encode_n(codec, data, n) do
    codec.encode(data)
    encode_n(codec, data, n - 1)
  end

  def decode_n(_, _, 0), do: :ok
  def decode_n(codec, binary, n) do
    codec.decode(binary)
    decode_n(codec, binary, n - 1)
  end
end

# Warmup
Loops.encode_n(ProfilingCodec, data, 10_000)
Loops.decode_n(ProfilingCodec, binary, 10_000)

# Profile just the hot function
Loops.encode_n(ProfilingCodec, data, 100_000)
