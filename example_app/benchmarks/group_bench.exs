# Group Performance Benchmark — realistic GridExchange shapes
#
# Run with: mix run benchmarks/group_bench.exs

defmodule GroupBench do
  # ---------------------------------------------------------------------------
  # Custom types mirroring the exchange domain
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Codec: TradingPeriodSettled — the real shape that crosses the wire
  #
  # Carries forward per-user balances and open orders at period transition.
  # This is the hot path: one big snapshot per settlement.
  # ---------------------------------------------------------------------------

  defmodule TradingPeriodSettled do
    use GridCodec.Struct, template_id: 950, schema_id: 99, version: 1

    alias GroupBench.OrderSide
    alias GroupBench.OrderType

    defcodec do
      field :market_id, :uuid
      field :period_id, :uuid
      field :instrument_id, :uuid
      field :settled_at, :timestamp_us
      field :period_seq, :u32
      field :trade_sequence, :u32
      field :last_trade_price, :decimal
      field :total_volume, :decimal

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
        order_id: <<i + 1_000_000::128>>,
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

  defp make_event(num_balances, num_orders) do
    %TradingPeriodSettled{
      market_id: <<1::128>>,
      period_id: <<2::128>>,
      instrument_id: <<3::128>>,
      settled_at: System.system_time(:microsecond),
      period_seq: 42,
      trade_sequence: 9999,
      last_trade_price: Decimal.new("51234.56"),
      total_volume: Decimal.new("123456789.99"),
      balances: make_balances(num_balances),
      open_orders: make_orders(num_orders)
    }
  end

  # ---------------------------------------------------------------------------
  # Benchmark
  # ---------------------------------------------------------------------------

  def run do
    # Scenarios: {balances, orders, label}
    scenarios = [
      {50, 200, "small market (50 users, 200 orders)"},
      {500, 2_000, "medium market (500 users, 2k orders)"},
      {2_000, 10_000, "large market (2k users, 10k orders)"},
      {5_000, 50_000, "huge market (5k users, 50k orders)"}
    ]

    events =
      for {nb, no, label} <- scenarios, into: %{} do
        ev = make_event(nb, no)
        {:ok, bin} = TradingPeriodSettled.encode(ev)

        IO.puts(
          "#{label}: #{div(byte_size(bin), 1024)} KB " <>
            "(#{nb + no} total group entries)"
        )

        {label, {ev, bin}}
      end

    IO.puts("")

    # -- Encode --
    Benchee.run(
      for {label, {ev, _bin}} <- events, into: %{} do
        {"encode #{label}", fn -> {:ok, _} = TradingPeriodSettled.encode(ev) end}
      end,
      warmup: 2,
      time: 5,
      memory_time: 1,
      title: "Encode"
    )

    # -- Decode (lazy) --
    Benchee.run(
      for {label, {_ev, bin}} <- events, into: %{} do
        {"decode #{label}", fn -> TradingPeriodSettled.decode(bin) end}
      end,
      warmup: 2,
      time: 5,
      memory_time: 1,
      title: "Decode (lazy — no entry materialization)"
    )

    # -- Decode + materialize all entries --
    Benchee.run(
      for {label, {_ev, bin}} <- events, into: %{} do
        {"decode+list #{label}",
         fn ->
           {:ok, dec} = TradingPeriodSettled.decode(bin)
           GridCodec.Group.to_list(dec.balances)
           GridCodec.Group.to_list(dec.open_orders)
         end}
      end,
      warmup: 2,
      time: 5,
      memory_time: 1,
      title: "Decode + to_list (full materialization)"
    )

    # -- Full roundtrip --
    Benchee.run(
      for {label, {ev, _bin}} <- events, into: %{} do
        {"roundtrip #{label}",
         fn ->
           {:ok, bin} = TradingPeriodSettled.encode(ev)
           {:ok, dec} = TradingPeriodSettled.decode(bin)
           GridCodec.Group.to_list(dec.balances)
           GridCodec.Group.to_list(dec.open_orders)
         end}
      end,
      warmup: 2,
      time: 5,
      memory_time: 1,
      title: "Full roundtrip (encode + decode + to_list)"
    )
  end
end

GroupBench.run()
