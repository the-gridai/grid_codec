# Group Benchmark — integer-only types vs Decimal-heavy types
#
# Run with: mix run benchmarks/group_bench_int.exs

defmodule GroupBenchInt do
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

  # -------------------------------------------------------------------------
  # "Real" codec: UUIDs + Decimals (current exchange shape)
  # -------------------------------------------------------------------------

  defmodule SettledDecimal do
    use GridCodec.Struct, template_id: 960, schema_id: 99, version: 1

    alias GroupBenchInt.OrderSide
    alias GroupBenchInt.OrderType

    defcodec do
      field :market_id, :uuid
      field :period_id, :uuid
      field :instrument_id, :uuid
      field :settled_at, :timestamp_us
      field :period_seq, :u32
      field :trade_sequence, :u32
      field :last_trade_price, :positive_decimal
      field :total_volume, :positive_decimal

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

  # -------------------------------------------------------------------------
  # "Fast" codec: u64 IDs + {mantissa, exp} tuples stored as i64 + i8
  # -------------------------------------------------------------------------

  defmodule SettledInt do
    use GridCodec.Struct, template_id: 961, schema_id: 99, version: 1

    alias GroupBenchInt.OrderSide
    alias GroupBenchInt.OrderType

    defcodec do
      field :market_id, :u64
      field :period_id, :u64
      field :instrument_id, :u64
      field :settled_at, :timestamp_us
      field :period_seq, :u32
      field :trade_sequence, :u32
      field :last_trade_price, :i64
      field :total_volume, :i64

      group :balances do
        field :user_id, :u64
        field :currency_available, :i64
        field :currency_locked, :i64
        field :instrument_available, :i64
        field :instrument_locked, :i64
      end

      group :open_orders do
        field :order_id, :u64
        field :trader_id, :u64
        field :side, OrderSide
        field :order_type, OrderType
        field :price, :i64
        field :remaining_quantity, :i64
        field :fee, :i64
        field :submitted_at, :timestamp_us
      end
    end
  end

  # -------------------------------------------------------------------------
  # Data generators
  # -------------------------------------------------------------------------

  defp make_decimal_balances(n) do
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

  defp make_decimal_orders(n) do
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

  defp make_int_balances(n) do
    for i <- 1..n do
      %{
        user_id: i,
        currency_available: 10_000_00 + rem(i, 100),
        currency_locked: 500_00 + rem(i, 50),
        instrument_available: 50_00 + rem(i, 99),
        instrument_locked: 5_00 + rem(i, 20)
      }
    end
  end

  defp make_int_orders(n) do
    for i <- 1..n do
      %{
        order_id: i + 1_000_000,
        trader_id: rem(i, 500),
        side: if(rem(i, 2) == 0, do: :buy, else: :sell),
        order_type: if(rem(i, 5) == 0, do: :market, else: :limit),
        price: (50_000 + rem(i, 2000)) * 100 + rem(i, 100),
        remaining_quantity: (1 + rem(i, 100)) * 10 + rem(i, 10),
        fee: rem(i, 30),
        submitted_at: 1_700_000_000_000_000 + i
      }
    end
  end

  def run do
    nb = 2_000
    no = 10_000

    dec_event = %SettledDecimal{
      market_id: <<1::128>>, period_id: <<2::128>>, instrument_id: <<3::128>>,
      settled_at: System.system_time(:microsecond),
      period_seq: 42, trade_sequence: 9999,
      last_trade_price: Decimal.new("51234.56"),
      total_volume: Decimal.new("123456789.99"),
      balances: make_decimal_balances(nb),
      open_orders: make_decimal_orders(no)
    }

    int_event = %SettledInt{
      market_id: 1, period_id: 2, instrument_id: 3,
      settled_at: System.system_time(:microsecond),
      period_seq: 42, trade_sequence: 9999,
      last_trade_price: 51_234_56,
      total_volume: 123_456_789_99,
      balances: make_int_balances(nb),
      open_orders: make_int_orders(no)
    }

    dec_bin = SettledDecimal.encode(dec_event)
    int_bin = SettledInt.encode(int_event)

    IO.puts("Large market: #{nb} users, #{no} orders (#{nb + no} total entries)")
    IO.puts("Decimal codec: #{div(byte_size(dec_bin), 1024)} KB wire")
    IO.puts("Integer codec: #{div(byte_size(int_bin), 1024)} KB wire")
    IO.puts("")

    Benchee.run(
      %{
        "encode DECIMAL (uuid + Decimal)" => fn -> SettledDecimal.encode(dec_event) end,
        "encode INTEGER (u64 + i64)" => fn -> SettledInt.encode(int_event) end
      },
      warmup: 2, time: 5, memory_time: 1,
      title: "Encode — 2k users + 10k orders"
    )

    Benchee.run(
      %{
        "decode+list DECIMAL" => fn ->
          {:ok, d} = SettledDecimal.decode(dec_bin)
          GridCodec.Group.to_list(d.balances)
          GridCodec.Group.to_list(d.open_orders)
        end,
        "decode+list INTEGER" => fn ->
          {:ok, d} = SettledInt.decode(int_bin)
          GridCodec.Group.to_list(d.balances)
          GridCodec.Group.to_list(d.open_orders)
        end
      },
      warmup: 2, time: 5, memory_time: 1,
      title: "Decode+list — 2k users + 10k orders"
    )

    Benchee.run(
      %{
        "roundtrip DECIMAL" => fn ->
          bin = SettledDecimal.encode(dec_event)
          {:ok, d} = SettledDecimal.decode(bin)
          GridCodec.Group.to_list(d.balances)
          GridCodec.Group.to_list(d.open_orders)
        end,
        "roundtrip INTEGER" => fn ->
          bin = SettledInt.encode(int_event)
          {:ok, d} = SettledInt.decode(bin)
          GridCodec.Group.to_list(d.balances)
          GridCodec.Group.to_list(d.open_orders)
        end
      },
      warmup: 2, time: 5, memory_time: 1,
      title: "Full roundtrip — 2k users + 10k orders"
    )
  end
end

GroupBenchInt.run()
