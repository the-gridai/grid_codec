# Parallel Decode Benchmark
#
# Tests whether decoding groups in parallel (raw spawn/receive) beats sequential.
#
# Run with: mix run benchmarks/parallel_decode_bench.exs

defmodule ParallelDecodeBench do
  defmodule OrderSide do
    use GridCodec.Types.Enum, encoding: :u8
    defenum do
      value(:buy)
      value(:sell)
    end
  end

  defmodule OrderType do
    use GridCodec.Types.Enum, encoding: :u8
    defenum do
      value(:limit)
      value(:market)
    end
  end

  defmodule TPS do
    use GridCodec.Struct, template_id: 970, schema_id: 99, version: 1
    alias ParallelDecodeBench.OrderSide
    alias ParallelDecodeBench.OrderType

    defcodec do
      field :market_id, :uuid
      field :period_id, :uuid
      field :settled_at, :timestamp_us

      group :balances do
        field :user_id, :uuid
        field :currency_available, :positive_decimal
        field :currency_locked, :positive_decimal
        field :instrument_available, :positive_decimal
        field :instrument_locked, :positive_decimal
      end

      group :open_orders do
        field :order_id, :uuid
        field :trader_id, :uuid
        field :side, OrderSide
        field :order_type, OrderType
        field :price, :positive_decimal
        field :remaining_quantity, :positive_decimal
        field :fee, :positive_decimal
        field :submitted_at, :timestamp_us
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Parallel helpers
  # ---------------------------------------------------------------------------

  @doc """
  Decode two groups in parallel — one process per group.
  Binary is shared (zero-copy), results are sent back.
  """
  def decode_groups_parallel(decoded) do
    parent = self()
    ref1 = make_ref()
    ref2 = make_ref()

    bal_group = decoded.balances
    ord_group = decoded.open_orders

    bal_heap = GridCodec.Group.count(bal_group) * 100 + 1000
    ord_heap = GridCodec.Group.count(ord_group) * 100 + 1000

    :erlang.spawn_opt(
      fn -> send(parent, {ref1, GridCodec.Group.to_list(bal_group)}) end,
      [{:min_heap_size, bal_heap}, {:fullsweep_after, 0}, {:priority, :high}]
    )

    :erlang.spawn_opt(
      fn -> send(parent, {ref2, GridCodec.Group.to_list(ord_group)}) end,
      [{:min_heap_size, ord_heap}, {:fullsweep_after, 0}, {:priority, :high}]
    )

    balances = receive do {^ref1, result} -> result end
    orders = receive do {^ref2, result} -> result end
    {balances, orders}
  end

  @doc """
  Decode a single group by splitting into N chunks across N processes.
  Uses zero-copy binary_part for chunk extraction.
  """
  def to_list_chunked(group, num_workers) do
    n = GridCodec.Group.count(group)
    bl = GridCodec.Group.block_length(group)

    if n < 200 do
      GridCodec.Group.to_list(group)
    else
      %{binary: bin, entries_offset: offset, batch_decoder: batch_fn} = group
      data = binary_part(bin, offset, n * bl)
      parent = self()
      chunk_size = div(n, num_workers)

      refs =
        for i <- 0..(num_workers - 1) do
          start_entry = i * chunk_size
          count = if i == num_workers - 1, do: n - start_entry, else: chunk_size
          chunk = binary_part(data, start_entry * bl, count * bl)
          ref = make_ref()
          est_heap = count * 100 + 1000

          :erlang.spawn_opt(
            fn -> send(parent, {ref, batch_fn.(chunk, [])}) end,
            [{:min_heap_size, est_heap}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          ref
        end

      refs
      |> Enum.map(fn ref -> receive do {^ref, result} -> result end end)
      |> :lists.append()
    end
  end

  @doc """
  Sequential decode of both groups (current approach).
  """
  def decode_groups_sequential(decoded) do
    balances = GridCodec.Group.to_list(decoded.balances)
    orders = GridCodec.Group.to_list(decoded.open_orders)
    {balances, orders}
  end

  # ---------------------------------------------------------------------------
  # Data generators
  # ---------------------------------------------------------------------------

  defp make_balances(n) do
    for i <- 1..n do
      %{
        user_id: <<i::128>>,
        currency_available: Decimal.new("10000.#{rem(i, 100)}"),
        currency_locked: Decimal.new("500.#{rem(i, 50)}"),
        instrument_available: Decimal.new("50.#{rem(i, 99)}"),
        instrument_locked: Decimal.new("5.#{rem(i, 20)}")
      }
    end
  end

  defp make_orders(n) do
    for i <- 1..n do
      %{
        order_id: <<(i + 1_000_000)::128>>,
        trader_id: <<rem(i, 500)::128>>,
        side: if(rem(i, 2) == 0, do: :buy, else: :sell),
        order_type: if(rem(i, 5) == 0, do: :market, else: :limit),
        price: Decimal.new("#{50_000 + rem(i, 2000)}.#{rem(i, 100)}"),
        remaining_quantity: Decimal.new("#{1 + rem(i, 100)}.#{rem(i, 10)}"),
        fee: Decimal.new("0.#{rem(i, 30)}"),
        submitted_at: 1_700_000_000_000_000 + i
      }
    end
  end

  def run do
    schedulers = System.schedulers_online()
    IO.puts("Schedulers: #{schedulers}")
    IO.puts("")

    # -----------------------------------------------------------------------
    # Measure raw spawn/send/receive overhead
    # -----------------------------------------------------------------------
    IO.puts("--- Raw overhead: spawn + send + receive ---")
    Benchee.run(
      %{
        "spawn+send+receive (no work)" => fn ->
          parent = self()
          ref = make_ref()
          :erlang.spawn_opt(fn -> send(parent, {ref, :ok}) end, [{:min_heap_size, 100}])
          receive do {^ref, :ok} -> :ok end
        end,
        "spawn+send+receive x2 parallel" => fn ->
          parent = self()
          r1 = make_ref()
          r2 = make_ref()
          :erlang.spawn_opt(fn -> send(parent, {r1, :ok}) end, [{:min_heap_size, 100}])
          :erlang.spawn_opt(fn -> send(parent, {r2, :ok}) end, [{:min_heap_size, 100}])
          receive do {^r1, :ok} -> :ok end
          receive do {^r2, :ok} -> :ok end
        end
      },
      warmup: 2, time: 3
    )

    # -----------------------------------------------------------------------
    # Medium market: 500 balances + 2k orders
    # -----------------------------------------------------------------------
    IO.puts("\n--- Medium market: 500 balances + 2k orders ---")

    med_event = %TPS{
      market_id: <<1::128>>, period_id: <<2::128>>,
      settled_at: System.system_time(:microsecond),
      balances: make_balances(500),
      open_orders: make_orders(2_000)
    }
    med_bin = TPS.encode(med_event)
    {:ok, med_dec} = TPS.decode(med_bin)

    Benchee.run(
      %{
        "sequential" => fn -> decode_groups_sequential(med_dec) end,
        "parallel (2 groups)" => fn -> decode_groups_parallel(med_dec) end
      },
      warmup: 2, time: 5, memory_time: 1
    )

    # -----------------------------------------------------------------------
    # Large market: 2k balances + 10k orders
    # -----------------------------------------------------------------------
    IO.puts("\n--- Large market: 2k balances + 10k orders ---")

    large_event = %TPS{
      market_id: <<1::128>>, period_id: <<2::128>>,
      settled_at: System.system_time(:microsecond),
      balances: make_balances(2_000),
      open_orders: make_orders(10_000)
    }
    large_bin = TPS.encode(large_event)
    {:ok, large_dec} = TPS.decode(large_bin)

    Benchee.run(
      %{
        "sequential" => fn -> decode_groups_sequential(large_dec) end,
        "parallel (2 groups)" => fn -> decode_groups_parallel(large_dec) end,
        "parallel (2 groups + 4-way chunk orders)" => fn ->
          parent = self()
          ref_b = make_ref()
          ref_o = make_ref()

          bal_group = large_dec.balances
          ord_group = large_dec.open_orders
          bal_heap = GridCodec.Group.count(bal_group) * 100 + 1000

          :erlang.spawn_opt(
            fn -> send(parent, {ref_b, GridCodec.Group.to_list(bal_group)}) end,
            [{:min_heap_size, bal_heap}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          :erlang.spawn_opt(
            fn -> send(parent, {ref_o, to_list_chunked(ord_group, 4)}) end,
            [{:min_heap_size, 1000}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          balances = receive do {^ref_b, r} -> r end
          orders = receive do {^ref_o, r} -> r end
          {balances, orders}
        end
      },
      warmup: 2, time: 5, memory_time: 1
    )

    # -----------------------------------------------------------------------
    # Huge market: 5k balances + 50k orders
    # -----------------------------------------------------------------------
    IO.puts("\n--- Huge market: 5k balances + 50k orders ---")

    huge_event = %TPS{
      market_id: <<1::128>>, period_id: <<2::128>>,
      settled_at: System.system_time(:microsecond),
      balances: make_balances(5_000),
      open_orders: make_orders(50_000)
    }
    huge_bin = TPS.encode(huge_event)
    {:ok, huge_dec} = TPS.decode(huge_bin)

    Benchee.run(
      %{
        "sequential" => fn -> decode_groups_sequential(huge_dec) end,
        "parallel (2 groups)" => fn -> decode_groups_parallel(huge_dec) end,
        "parallel (2g + 4-way chunk orders)" => fn ->
          parent = self()
          ref_b = make_ref()
          ref_o = make_ref()

          bal_group = huge_dec.balances
          ord_group = huge_dec.open_orders
          bal_heap = GridCodec.Group.count(bal_group) * 100 + 1000

          :erlang.spawn_opt(
            fn -> send(parent, {ref_b, GridCodec.Group.to_list(bal_group)}) end,
            [{:min_heap_size, bal_heap}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          :erlang.spawn_opt(
            fn -> send(parent, {ref_o, to_list_chunked(ord_group, 4)}) end,
            [{:min_heap_size, 1000}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          balances = receive do {^ref_b, r} -> r end
          orders = receive do {^ref_o, r} -> r end
          {balances, orders}
        end,
        "parallel (2g + 8-way chunk orders)" => fn ->
          parent = self()
          ref_b = make_ref()
          ref_o = make_ref()

          bal_group = huge_dec.balances
          ord_group = huge_dec.open_orders
          bal_heap = GridCodec.Group.count(bal_group) * 100 + 1000

          :erlang.spawn_opt(
            fn -> send(parent, {ref_b, GridCodec.Group.to_list(bal_group)}) end,
            [{:min_heap_size, bal_heap}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          :erlang.spawn_opt(
            fn -> send(parent, {ref_o, to_list_chunked(ord_group, 8)}) end,
            [{:min_heap_size, 1000}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          balances = receive do {^ref_b, r} -> r end
          orders = receive do {^ref_o, r} -> r end
          {balances, orders}
        end
      },
      warmup: 2, time: 5, memory_time: 1
    )

    # -----------------------------------------------------------------------
    # Isolated: chunk a single 50k-entry group
    # -----------------------------------------------------------------------
    IO.puts("\n--- Isolated: to_list on 50k orders only ---")

    Benchee.run(
      %{
        "sequential" => fn -> GridCodec.Group.to_list(huge_dec.open_orders) end,
        "2-way chunk" => fn -> to_list_chunked(huge_dec.open_orders, 2) end,
        "4-way chunk" => fn -> to_list_chunked(huge_dec.open_orders, 4) end,
        "8-way chunk" => fn -> to_list_chunked(huge_dec.open_orders, 8) end
      },
      warmup: 2, time: 5, memory_time: 1
    )
  end
end

ParallelDecodeBench.run()
