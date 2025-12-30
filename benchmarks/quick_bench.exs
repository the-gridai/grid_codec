# Quick Development Benchmark
#
# Run with: mix run benchmarks/quick_bench.exs
#
# A simple, fast benchmark for development iteration.
# For comprehensive benchmarks, use the Livebooks in livebooks/

defmodule QuickBench.Codec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
    field(:price, :u64)
    field(:name, :string16)
  end
end

IO.puts("GridCodec Quick Benchmark")
IO.puts(String.duplicate("=", 50))

# Test data
data = %{
  id: 12_345_678_901_234,
  count: 100_000,
  flag: true,
  price: 15_000_000_000,
  name: "Test Order"
}

# Encode/Decode verification
binary = QuickBench.Codec.encode(data)
{:ok, decoded} = QuickBench.Codec.decode(binary)

IO.puts("\nSchema:")
IO.puts("  Block length: #{QuickBench.Codec.block_length()} bytes")
IO.puts("  Encoded size: #{byte_size(binary)} bytes")
IO.puts("  Roundtrip OK: #{data == decoded}")

# Quick benchmark
iterations = 100_000

IO.puts("\nBenchmark (#{iterations} iterations):")

{encode_time, _} = :timer.tc(fn ->
  for _ <- 1..iterations, do: QuickBench.Codec.encode(data)
end)

{decode_time, _} = :timer.tc(fn ->
  for _ <- 1..iterations, do: QuickBench.Codec.decode(binary)
end)

env = QuickBench.Codec.wrap(binary)
{get_time, _} = :timer.tc(fn ->
  for _ <- 1..iterations, do: QuickBench.Codec.get(env, :price)
end)

encode_ns = encode_time / iterations * 1000
decode_ns = decode_time / iterations * 1000
get_ns = get_time / iterations * 1000

IO.puts("  encode: #{Float.round(encode_ns, 1)} ns/op (#{Float.round(iterations / encode_time * 1_000_000, 0)} ops/sec)")
IO.puts("  decode: #{Float.round(decode_ns, 1)} ns/op (#{Float.round(iterations / decode_time * 1_000_000, 0)} ops/sec)")
IO.puts("  get:    #{Float.round(get_ns, 1)} ns/op (#{Float.round(iterations / get_time * 1_000_000, 0)} ops/sec)")

IO.puts("\nDone! For detailed benchmarks, see livebooks/")
