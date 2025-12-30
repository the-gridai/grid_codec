# Isolated Decode Profiling
#
# Usage:
#   mix profile.tprof benchmarks/profile_decode.exs -- simple
#   mix profile.tprof benchmarks/profile_decode.exs -- mixed
#
# This script profiles ONLY decoding with minimal overhead.

defmodule GridCodec.Profile.SimpleCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
    field(:price, :u64)
  end
end

defmodule GridCodec.Profile.MixedCodec do
  use GridCodec

  defcodec do
    field(:id, :uuid)
    field(:count, :u32)
    field(:score, :i64)
    field(:active, :bool)
    field(:name, :string16)
    field(:description, :string16)
  end
end

defmodule GridCodec.Profile.DecodeRunner do
  @iterations 50_000

  def run_simple do
    data = %{id: 12345, count: 100, flag: true, price: 99_99}
    binary = GridCodec.Profile.SimpleCodec.encode(data)
    do_decode(GridCodec.Profile.SimpleCodec, binary, @iterations)
  end

  def run_mixed do
    data = %{
      id: :crypto.strong_rand_bytes(16),
      count: 42,
      score: -1000,
      active: true,
      name: "Test User",
      description: "A test description"
    }
    binary = GridCodec.Profile.MixedCodec.encode(data)
    do_decode(GridCodec.Profile.MixedCodec, binary, @iterations)
  end

  # Unrolled loop to minimize iteration overhead
  defp do_decode(codec, binary, n) when n > 0 do
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    codec.decode(binary)
    do_decode(codec, binary, n - 10)
  end

  defp do_decode(_codec, _binary, _n), do: :ok
end

# Parse args and run
case System.argv() do
  ["--", "simple"] ->
    IO.puts("Profiling: SimpleCodec.decode/1 (#{50_000} iterations)")
    GridCodec.Profile.DecodeRunner.run_simple()

  ["--", "mixed"] ->
    IO.puts("Profiling: MixedCodec.decode/1 (#{50_000} iterations)")
    GridCodec.Profile.DecodeRunner.run_mixed()

  _ ->
    IO.puts("Profiling: SimpleCodec.decode/1 (default)")
    GridCodec.Profile.DecodeRunner.run_simple()
end
