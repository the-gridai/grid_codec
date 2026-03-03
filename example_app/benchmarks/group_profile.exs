# Group Profiling — tprof time + memory analysis
#
# Run with: mix run benchmarks/group_profile.exs

defmodule GroupProfile do
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

  defmodule TradingPeriodSettled do
    use GridCodec.Struct, template_id: 950, schema_id: 99, version: 1

    alias GroupProfile.OrderSide
    alias GroupProfile.OrderType

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
        field :currency_available, :decimal
        field :currency_locked, :decimal
        field :instrument_available, :decimal
        field :instrument_locked, :decimal
      end

      group :open_orders do
        field :order_id, :uuid
        field :trader_id, :uuid
        field :side, OrderSide
        field :order_type, OrderType
        field :price, :decimal
        field :remaining_quantity, :decimal
        field :fee, :decimal
        field :submitted_at, :timestamp_us
      end
    end
  end

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
    event = %TradingPeriodSettled{
      market_id: <<1::128>>,
      period_id: <<2::128>>,
      instrument_id: <<3::128>>,
      settled_at: System.system_time(:microsecond),
      period_seq: 42,
      trade_sequence: 9999,
      last_trade_price: Decimal.new("51234.56"),
      total_volume: Decimal.new("123456789.99"),
      balances: make_balances(500),
      open_orders: make_orders(2_000)
    }

    binary = TradingPeriodSettled.encode(event)
    IO.puts("Wire size: #{div(byte_size(binary), 1024)} KB (500 balances + 2000 orders)")

    # Warmup
    for _ <- 1..50 do
      TradingPeriodSettled.encode(event)
      {:ok, d} = TradingPeriodSettled.decode(binary)
      GridCodec.Group.to_list(d.balances)
      GridCodec.Group.to_list(d.open_orders)
    end

    iterations = 200

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("ENCODE TIME PROFILE (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 70))

    Mix.Tasks.Profile.Tprof.profile(
      fn ->
        for _ <- 1..iterations, do: TradingPeriodSettled.encode(event)
        :ok
      end,
      type: :time,
      sort: :time,
      report: :total,
      set_on_spawn: false
    )

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("ENCODE MEMORY PROFILE (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 70))

    Mix.Tasks.Profile.Tprof.profile(
      fn ->
        for _ <- 1..iterations, do: TradingPeriodSettled.encode(event)
        :ok
      end,
      type: :memory,
      sort: :memory,
      report: :total,
      set_on_spawn: false
    )

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("DECODE + TO_LIST TIME PROFILE (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 70))

    Mix.Tasks.Profile.Tprof.profile(
      fn ->
        for _ <- 1..iterations do
          {:ok, d} = TradingPeriodSettled.decode(binary)
          GridCodec.Group.to_list(d.balances)
          GridCodec.Group.to_list(d.open_orders)
        end
        :ok
      end,
      type: :time,
      sort: :time,
      report: :total,
      set_on_spawn: false
    )

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("DECODE + TO_LIST MEMORY PROFILE (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 70))

    Mix.Tasks.Profile.Tprof.profile(
      fn ->
        for _ <- 1..iterations do
          {:ok, d} = TradingPeriodSettled.decode(binary)
          GridCodec.Group.to_list(d.balances)
          GridCodec.Group.to_list(d.open_orders)
        end
        :ok
      end,
      type: :memory,
      sort: :memory,
      report: :total,
      set_on_spawn: false
    )
  end
end

GroupProfile.run()
