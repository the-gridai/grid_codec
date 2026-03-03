# Find the parallel decode threshold
#
# Measures sequential vs parallel for varying group sizes to find the crossover.
#
# Run with: mix run benchmarks/parallel_threshold.exs

defmodule ParallelThreshold do
  defmodule OrderSide do
    use GridCodec.Types.Enum, encoding: :u8
    defenum do
      value(:buy)
      value(:sell)
    end
  end

  defmodule Heavy do
    @moduledoc "Heavy entry: uuid + enum + 3 decimals + timestamp (similar to open_orders)"
    use GridCodec.Struct, template_id: 980, schema_id: 99, version: 1
    alias ParallelThreshold.OrderSide

    defcodec do
      field :id, :uuid

      group :entries do
        field :a_id, :uuid
        field :b_id, :uuid
        field :side, OrderSide
        field :price, :positive_decimal
        field :qty, :positive_decimal
        field :fee, :positive_decimal
        field :ts, :timestamp_us
      end
    end
  end

  defmodule Light do
    @moduledoc "Light entry: all integers (cheapest possible)"
    use GridCodec.Struct, template_id: 981, schema_id: 99, version: 1

    defcodec do
      field :id, :u64

      group :entries do
        field :a, :u64
        field :b, :u64
        field :c, :u32
        field :d, :u32
      end
    end
  end

  defp make_heavy_entries(n) do
    for i <- 1..n do
      %{
        a_id: <<i::128>>,
        b_id: <<(i + 1)::128>>,
        side: if(rem(i, 2) == 0, do: :buy, else: :sell),
        price: Decimal.new("#{50_000 + rem(i, 2000)}.#{rem(i, 100)}"),
        qty: Decimal.new("#{1 + rem(i, 100)}.#{rem(i, 10)}"),
        fee: Decimal.new("0.#{rem(i, 30)}"),
        ts: 1_700_000_000_000_000 + i
      }
    end
  end

  defp make_light_entries(n) do
    for i <- 1..n do
      %{a: i, b: i + 1, c: rem(i, 1000), d: rem(i, 500)}
    end
  end

  defp decode_parallel(decoded) do
    parent = self()
    ref = make_ref()
    group = decoded.entries
    heap = GridCodec.Group.count(group) * 100 + 1000

    :erlang.spawn_opt(
      fn -> send(parent, {ref, GridCodec.Group.to_list(group)}) end,
      [{:min_heap_size, heap}, {:fullsweep_after, 0}, {:priority, :high}]
    )

    receive do {^ref, result} -> result end
  end

  def run do
    IO.puts("Finding parallel decode threshold")
    IO.puts("Schedulers: #{System.schedulers_online()}\n")

    sizes = [50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000]

    heavy_bl = 2*16 + 1 + 3*9 + 8  # 2 uuids + enum u8 + 3 decimals + timestamp = 68B
    IO.puts("=== HEAVY entries (uuid+enum+3×decimal+timestamp, #{heavy_bl}B/entry) ===\n")

    for n <- sizes do
      event = %Heavy{id: <<1::128>>, entries: make_heavy_entries(n)}
      bin = Heavy.encode(event)
      {:ok, dec} = Heavy.decode(bin)

      # Warmup
      for _ <- 1..100 do
        GridCodec.Group.to_list(dec.entries)
        decode_parallel(dec)
      end

      runs = max(div(50_000, n), 50)

      {seq_us, _} = :timer.tc(fn -> for _ <- 1..runs, do: GridCodec.Group.to_list(dec.entries) end)
      {par_us, _} = :timer.tc(fn -> for _ <- 1..runs, do: decode_parallel(dec) end)

      seq_per = Float.round(seq_us / runs, 1)
      par_per = Float.round(par_us / runs, 1)
      ratio = Float.round(seq_per / par_per, 2)
      winner = if ratio > 1.05, do: "PAR ✓", else: if(ratio < 0.95, do: "SEQ ✓", else: "  ≈  ")

      IO.puts(
        "  #{String.pad_leading("#{n}", 6)} entries: " <>
          "seq #{String.pad_leading("#{seq_per}", 9)} µs  " <>
          "par #{String.pad_leading("#{par_per}", 9)} µs  " <>
          "ratio #{String.pad_leading("#{ratio}", 5)}x  #{winner}"
      )
    end

    light_bl = 2*8 + 2*4  # 2 u64 + 2 u32 = 24B
    IO.puts("\n=== LIGHT entries (4×integer, #{light_bl}B/entry) ===\n")

    for n <- sizes do
      event = %Light{id: 1, entries: make_light_entries(n)}
      bin = Light.encode(event)
      {:ok, dec} = Light.decode(bin)

      for _ <- 1..100 do
        GridCodec.Group.to_list(dec.entries)
        decode_parallel(dec)
      end

      runs = max(div(50_000, n), 50)

      {seq_us, _} = :timer.tc(fn -> for _ <- 1..runs, do: GridCodec.Group.to_list(dec.entries) end)
      {par_us, _} = :timer.tc(fn -> for _ <- 1..runs, do: decode_parallel(dec) end)

      seq_per = Float.round(seq_us / runs, 1)
      par_per = Float.round(par_us / runs, 1)
      ratio = Float.round(seq_per / par_per, 2)
      winner = if ratio > 1.05, do: "PAR ✓", else: if(ratio < 0.95, do: "SEQ ✓", else: "  ≈  ")

      IO.puts(
        "  #{String.pad_leading("#{n}", 6)} entries: " <>
          "seq #{String.pad_leading("#{seq_per}", 9)} µs  " <>
          "par #{String.pad_leading("#{par_per}", 9)} µs  " <>
          "ratio #{String.pad_leading("#{ratio}", 5)}x  #{winner}"
      )
    end

    IO.puts("\n--- Threshold heuristic ---")
    IO.puts("parallel_worth? = num_entries * block_length > THRESHOLD_BYTES")
    IO.puts("Based on the data above, find the crossover point.")
  end
end

ParallelThreshold.run()
