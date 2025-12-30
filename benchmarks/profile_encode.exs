# Isolated Encode Profiling
#
# Usage:
#   mix profile.tprof benchmarks/profile_encode.exs -- simple
#   mix profile.tprof benchmarks/profile_encode.exs -- mixed
#   mix profile.eprof benchmarks/profile_encode.exs -- simple
#
# This script profiles ONLY encoding with minimal overhead.

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

defmodule GridCodec.Profile.EncodeRunner do
  @iterations 50_000

  def run_simple do
    data = %{id: 12345, count: 100, flag: true, price: 99_99}
    do_encode(GridCodec.Profile.SimpleCodec, data, @iterations)
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
    do_encode(GridCodec.Profile.MixedCodec, data, @iterations)
  end

  # Unrolled loop to minimize iteration overhead
  defp do_encode(codec, data, n) when n > 0 do
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    codec.encode(data)
    do_encode(codec, data, n - 10)
  end

  defp do_encode(_codec, _data, _n), do: :ok
end

# Parse args and run
case System.argv() do
  ["--", "simple"] ->
    IO.puts("Profiling: SimpleCodec.encode/1 (#{50_000} iterations)")
    GridCodec.Profile.EncodeRunner.run_simple()

  ["--", "mixed"] ->
    IO.puts("Profiling: MixedCodec.encode/1 (#{50_000} iterations)")
    GridCodec.Profile.EncodeRunner.run_mixed()

  _ ->
    IO.puts("Profiling: SimpleCodec.encode/1 (default)")
    GridCodec.Profile.EncodeRunner.run_simple()
end
