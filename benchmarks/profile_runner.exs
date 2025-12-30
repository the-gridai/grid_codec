# GridCodec Profiling Runner
#
# Usage:
#   mix profile.tprof benchmarks/profile_runner.exs
#   mix profile.eprof benchmarks/profile_runner.exs
#   mix profile.cprof benchmarks/profile_runner.exs
#
# For detailed output, redirect to file:
#   mix profile.tprof benchmarks/profile_runner.exs > artifacts/tprof_$(date +%Y%m%d_%H%M%S).txt
#
# For isolated workloads with less noise, use:
#   benchmarks/profile_encode.exs
#   benchmarks/profile_decode.exs
#
# See artifacts/ for saved profile outputs.

defmodule GridCodec.Profiling.SimpleCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
    field(:price, :u64)
  end
end

defmodule GridCodec.Profiling.MixedCodec do
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

defmodule GridCodec.Profiling.GroupHelper do
  def encode_entry(%{id: id, value: v}), do: <<id::little-64, v::little-32>>
  def decode_entry(<<id::little-64, v::little-32>>), do: {:ok, %{id: id, value: v}}
end

defmodule GridCodec.Profiling.GroupCodec do
  use GridCodec

  defcodec do
    field(:batch_id, :uuid)
    field(:timestamp, :timestamp_us)

    group :items,
      entry_encoder: &GridCodec.Profiling.GroupHelper.encode_entry/1,
      entry_decoder: &GridCodec.Profiling.GroupHelper.decode_entry/1 do
      field(:id, :u64)
      field(:value, :u32)
    end
  end
end

defmodule GridCodec.Profiling.Runner do
  @iterations 10_000

  # Generate test data
  def simple_data, do: %{id: 12345, count: 100, flag: true, price: 99_99}

  def mixed_data do
    %{
      id: :crypto.strong_rand_bytes(16),
      count: 42,
      score: -1000,
      active: true,
      name: "Test User",
      description: "A test description for profiling purposes"
    }
  end

  def group_data do
    entries = for i <- 1..100, do: %{id: i, value: i * 10}

    %{
      batch_id: :crypto.strong_rand_bytes(16),
      timestamp: System.system_time(:microsecond),
      items: entries
    }
  end

  # Unrolled loops to minimize iteration overhead
  def run_encode(codec, data, n) when n >= 10 do
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
    run_encode(codec, data, n - 10)
  end

  def run_encode(_codec, _data, _n), do: :ok

  def run_decode(codec, binary, n) when n >= 10 do
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
    run_decode(codec, binary, n - 10)
  end

  def run_decode(_codec, _binary, _n), do: :ok

  def run_getter(codec, envelope, field, n) when n >= 10 do
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    codec.get(envelope, field)
    run_getter(codec, envelope, field, n - 10)
  end

  def run_getter(_codec, _envelope, _field, _n), do: :ok

  def run do
    simple = simple_data()
    mixed = mixed_data()
    group = group_data()

    simple_bin = GridCodec.Profiling.SimpleCodec.encode(simple)
    mixed_bin = GridCodec.Profiling.MixedCodec.encode(mixed)
    group_bin = GridCodec.Profiling.GroupCodec.encode(group)

    IO.puts("=== GridCodec Profiling ===\n")
    IO.puts("Simple codec binary size: #{byte_size(simple_bin)} bytes")
    IO.puts("Mixed codec binary size: #{byte_size(mixed_bin)} bytes")
    IO.puts("Group codec binary size: #{byte_size(group_bin)} bytes")
    IO.puts("Running #{@iterations} iterations of each operation...\n")

    IO.puts("--- Encoding ---")
    run_encode(GridCodec.Profiling.SimpleCodec, simple, @iterations)
    run_encode(GridCodec.Profiling.MixedCodec, mixed, @iterations)
    run_encode(GridCodec.Profiling.GroupCodec, group, @iterations)

    IO.puts("--- Decoding ---")
    run_decode(GridCodec.Profiling.SimpleCodec, simple_bin, @iterations)
    run_decode(GridCodec.Profiling.MixedCodec, mixed_bin, @iterations)
    run_decode(GridCodec.Profiling.GroupCodec, group_bin, @iterations)

    IO.puts("--- Zero-copy field access ---")
    simple_env = GridCodec.Profiling.SimpleCodec.wrap(simple_bin)
    mixed_env = GridCodec.Profiling.MixedCodec.wrap(mixed_bin)

    run_getter(GridCodec.Profiling.SimpleCodec, simple_env, :id, @iterations)
    run_getter(GridCodec.Profiling.SimpleCodec, simple_env, :flag, @iterations)
    run_getter(GridCodec.Profiling.MixedCodec, mixed_env, :id, @iterations)
    run_getter(GridCodec.Profiling.MixedCodec, mixed_env, :active, @iterations)

    IO.puts("\n=== Profiling complete ===")
  end
end

GridCodec.Profiling.Runner.run()
