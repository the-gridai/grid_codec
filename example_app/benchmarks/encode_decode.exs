defmodule Bench.EncodeDecode do
  @moduledoc """
  Benchmark encode/decode performance for example codecs.
  """

  def run do
    # Prepare test data
    order = %ExampleApp.Events.OrderCreated{
      order_id: :crypto.strong_rand_bytes(16),
      user_id: 12_345_678_901_234_567,
      symbol: "BTCUSD",
      side: 1,
      price: 15_000_000_000,
      quantity: 100_000,
      timestamp: DateTime.utc_now(),
      flags: 7
    }

    trade = %ExampleApp.Events.TradeExecuted{
      trade_id: :crypto.strong_rand_bytes(16),
      order_id: :crypto.strong_rand_bytes(16),
      price: 15_000_000_000,
      quantity: 50_000,
      timestamp: DateTime.utc_now()
    }

    order_bin = ExampleApp.Events.OrderCreated.encode(order)
    trade_bin = ExampleApp.Events.TradeExecuted.encode(trade)

    IO.puts("OrderCreated binary size: #{byte_size(order_bin)} bytes")
    IO.puts("TradeExecuted binary size: #{byte_size(trade_bin)} bytes\n")

    Benchee.run(
      %{
        "OrderCreated.encode" => fn -> ExampleApp.Events.OrderCreated.encode(order) end,
        "OrderCreated.decode" => fn -> ExampleApp.Events.OrderCreated.decode(order_bin) end,
        "TradeExecuted.encode" => fn -> ExampleApp.Events.TradeExecuted.encode(trade) end,
        "TradeExecuted.decode" => fn -> ExampleApp.Events.TradeExecuted.decode(trade_bin) end
      },
      time: 3,
      warmup: 1,
      memory_time: 1,
      print: [configuration: false]
    )
  end
end

# Run if executed directly
if System.argv() != [] or true do
  Bench.EncodeDecode.run()
end
