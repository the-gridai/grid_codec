# Batch Architecture Comparison Benchmark
#
# Compares three heterogeneous batch approaches:
#   A) PaddedUnion   — fixed-size padded entries, O(1) random access
#   B) TypedFrames   — length-prefixed frames, offset index on decode
#   C) PerTypeGroups — per-type homogeneous groups, k-way merge for ordering
#
# Run with: mix run benchmarks/batch_arch_bench.exs

alias GridCodec.Batch.PaddedUnion
alias GridCodec.Batch.TypedFrames
alias GridCodec.Batch.PerTypeGroups

# ---------------------------------------------------------------------------
# Inline codec definitions (same shapes as test codecs)
# ---------------------------------------------------------------------------

defmodule BatchBench.SmallCommand do
  use GridCodec.Struct, template_id: 800, schema_id: 80, version: 1

  defcodec do
    field :order_id, :u64
    field :timestamp, :u64
  end
end

defmodule BatchBench.MediumCommand do
  use GridCodec.Struct, template_id: 801, schema_id: 80, version: 1

  defcodec do
    field :order_id, :u64
    field :user_id, :u64
    field :symbol, :uuid
    field :price, :u64
    field :quantity, :u32
    field :flags, :u32
  end
end

defmodule BatchBench.LargeCommand do
  use GridCodec.Struct, template_id: 802, schema_id: 80, version: 1

  defcodec do
    field :order_id, :u64
    field :user_id, :u64
    field :symbol, :uuid
    field :price, :u64
    field :quantity, :u64
    field :limit_price, :u64
    field :stop_price, :u64
    field :flags, :u32
    field :side, :u8
    field :order_type, :u8
    field :time_in_force, :u8
    field :reserved, :u8
    field :timestamp, :u64
  end
end

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

type_specs = [
  {0, BatchBench.SmallCommand, BatchBench.SmallCommand.block_length()},
  {1, BatchBench.MediumCommand, BatchBench.MediumCommand.block_length()},
  {2, BatchBench.LargeCommand, BatchBench.LargeCommand.block_length()}
]

IO.puts("Block lengths: Small=#{BatchBench.SmallCommand.block_length()}, " <>
  "Medium=#{BatchBench.MediumCommand.block_length()}, " <>
  "Large=#{BatchBench.LargeCommand.block_length()}")

make_entry = fn i ->
  case rem(i, 20) do
    n when n in 0..11 ->
      struct!(BatchBench.LargeCommand,
        order_id: i, user_id: 42, symbol: <<i::128>>,
        price: 10_000 + rem(i, 100), quantity: 500 + rem(i, 50),
        limit_price: 10_050, stop_price: 9_950, flags: 1,
        side: 0, order_type: 1, time_in_force: 2, reserved: 0,
        timestamp: System.system_time(:microsecond)
      )
    n when n in 12..16 ->
      struct!(BatchBench.MediumCommand,
        order_id: i, user_id: 42, symbol: <<i::128>>,
        price: 10_000 + rem(i, 100), quantity: 100 + rem(i, 50), flags: 0
      )
    _ ->
      struct!(BatchBench.SmallCommand,
        order_id: i, timestamp: System.system_time(:microsecond)
      )
  end
end

sizes = [50, 500, 2_000, 8_189]
architectures = [
  {"A_PaddedUnion", PaddedUnion},
  {"B_TypedFrames", TypedFrames},
  {"C_PerTypeGroups", PerTypeGroups}
]

# ---------------------------------------------------------------------------
# Wire size report
# ---------------------------------------------------------------------------

IO.puts("\n=== Wire Size Report ===")
IO.puts(String.pad_trailing("Size", 8) <>
  Enum.map_join(architectures, "", fn {name, _} ->
    String.pad_trailing(name, 18)
  end))

for size <- sizes do
  entries = Enum.map(0..(size - 1), make_entry)

  row = String.pad_trailing("#{size}", 8) <>
    Enum.map_join(architectures, "", fn {_name, mod} ->
      {:ok, bin} = mod.encode(entries, type_specs)
      bytes = byte_size(bin)
      kb = Float.round(bytes / 1024, 1)
      String.pad_trailing("#{bytes} (#{kb} KB)", 18)
    end)

  IO.puts(row)
end

# ---------------------------------------------------------------------------
# Benchmarks per size
# ---------------------------------------------------------------------------

for size <- sizes do
  entries = Enum.map(0..(size - 1), make_entry)

  encoded = Map.new(architectures, fn {name, mod} ->
    {:ok, bin} = mod.encode(entries, type_specs)
    {name, bin}
  end)

  decoded = Map.new(architectures, fn {name, mod} ->
    {:ok, batch} = mod.decode(encoded[name], type_specs)
    {name, batch}
  end)

  mid = div(size, 2)

  IO.puts("\n\n========== #{size} entries ==========\n")

  Benchee.run(
    %{
      "A_PaddedUnion.encode" => fn -> PaddedUnion.encode(entries, type_specs) end,
      "B_TypedFrames.encode" => fn -> TypedFrames.encode(entries, type_specs) end,
      "C_PerTypeGroups.encode" => fn -> PerTypeGroups.encode(entries, type_specs) end
    },
    warmup: 1,
    time: 3,
    memory_time: 1,
    print: [configuration: false]
  )

  Benchee.run(
    %{
      "A_PaddedUnion.decode_all" => fn ->
        {:ok, b} = PaddedUnion.decode(encoded["A_PaddedUnion"], type_specs)
        PaddedUnion.to_list(b)
      end,
      "B_TypedFrames.decode_all" => fn ->
        {:ok, b} = TypedFrames.decode(encoded["B_TypedFrames"], type_specs)
        TypedFrames.to_list(b)
      end,
      "C_PerTypeGroups.decode_all" => fn ->
        {:ok, b} = PerTypeGroups.decode(encoded["C_PerTypeGroups"], type_specs)
        PerTypeGroups.to_list(b)
      end
    },
    warmup: 1,
    time: 3,
    memory_time: 1,
    print: [configuration: false]
  )

  Benchee.run(
    %{
      "A_PaddedUnion.stream_take_10" => fn ->
        decoded["A_PaddedUnion"] |> PaddedUnion.stream() |> Enum.take(10)
      end,
      "B_TypedFrames.stream_take_10" => fn ->
        decoded["B_TypedFrames"] |> TypedFrames.stream() |> Enum.take(10)
      end,
      "C_PerTypeGroups.stream_take_10" => fn ->
        decoded["C_PerTypeGroups"] |> PerTypeGroups.stream() |> Enum.take(10)
      end
    },
    warmup: 1,
    time: 3,
    memory_time: 1,
    print: [configuration: false]
  )

  Benchee.run(
    %{
      "A_PaddedUnion.get_middle" => fn ->
        PaddedUnion.get(decoded["A_PaddedUnion"], mid)
      end,
      "B_TypedFrames.get_middle" => fn ->
        TypedFrames.get(decoded["B_TypedFrames"], mid)
      end,
      "C_PerTypeGroups.get_middle" => fn ->
        PerTypeGroups.get(decoded["C_PerTypeGroups"], mid)
      end
    },
    warmup: 1,
    time: 3,
    memory_time: 1,
    print: [configuration: false]
  )

  Benchee.run(
    %{
      "A_PaddedUnion.by_type(2)" => fn ->
        PaddedUnion.by_type(decoded["A_PaddedUnion"], 2)
      end,
      "B_TypedFrames.by_type(2)" => fn ->
        TypedFrames.by_type(decoded["B_TypedFrames"], 2)
      end,
      "C_PerTypeGroups.by_type(2)" => fn ->
        PerTypeGroups.by_type(decoded["C_PerTypeGroups"], 2)
      end
    },
    warmup: 1,
    time: 3,
    memory_time: 1,
    print: [configuration: false]
  )

  Benchee.run(
    %{
      "A_PaddedUnion.count" => fn -> PaddedUnion.count(decoded["A_PaddedUnion"]) end,
      "B_TypedFrames.count" => fn -> TypedFrames.count(decoded["B_TypedFrames"]) end,
      "C_PerTypeGroups.count" => fn -> PerTypeGroups.count(decoded["C_PerTypeGroups"]) end
    },
    warmup: 1,
    time: 3,
    print: [configuration: false]
  )
end
