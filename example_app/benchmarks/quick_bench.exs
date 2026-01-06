# Quick Development Benchmark
#
# Run with: mix run benchmarks/quick_bench.exs
#
# A simple, fast benchmark for development iteration.

defmodule QuickBench do
  defmodule Codec do
    use GridCodec.Struct, template_id: 1, schema_id: 1

    defcodec do
      field(:id, :u64)
      field(:count, :u32)
      field(:flag, :bool)
      field(:price, :u64)
      field(:name, :string16)
    end
  end

  def run do
    IO.puts("GridCodec.Struct Quick Benchmark")
    IO.puts(String.duplicate("=", 50))

    # Test data
    data = %Codec{
      id: 12_345_678_901_234,
      count: 100_000,
      flag: true,
      price: 15_000_000_000,
      name: "Test Order"
    }

    # Encode/Decode verification
    binary = Codec.encode(data)
    {:ok, decoded} = Codec.decode(binary)

    IO.puts("\nSchema:")
    IO.puts("  Block length: #{Codec.block_length()} bytes")
    IO.puts("  Encoded size: #{byte_size(binary)} bytes")
    IO.puts("  Roundtrip OK: #{data == decoded}")

    # Quick benchmark
    iterations = 100_000

    IO.puts("\nBenchmark (#{iterations} iterations):")

    {encode_time, _} = :timer.tc(fn ->
      for _ <- 1..iterations, do: Codec.encode(data)
    end)

    {decode_time, _} = :timer.tc(fn ->
      for _ <- 1..iterations, do: Codec.decode(binary)
    end)

    env = Codec.wrap(binary)
    {get_time, _} = :timer.tc(fn ->
      for _ <- 1..iterations, do: Codec.get(env, :price)
    end)

    encode_ns = encode_time / iterations * 1000
    decode_ns = decode_time / iterations * 1000
    get_ns = get_time / iterations * 1000

    IO.puts("  encode: #{Float.round(encode_ns, 1)} ns/op (#{Float.round(iterations / encode_time * 1_000_000, 0)} ops/sec)")
    IO.puts("  decode: #{Float.round(decode_ns, 1)} ns/op (#{Float.round(iterations / decode_time * 1_000_000, 0)} ops/sec)")
    IO.puts("  get:    #{Float.round(get_ns, 1)} ns/op (#{Float.round(iterations / get_time * 1_000_000, 0)} ops/sec)")

    IO.puts("\nDone!")
  end
end

QuickBench.run()
