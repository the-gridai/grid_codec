defmodule Bench.EncodeDecode do
  @moduledoc """
  Benchmark encode/decode performance for example event codecs.

  Tests real-world event codecs (OrderCreated, TradeExecuted) to
  measure typical application performance.

  ## Expected Results (v0.6.0)

  On modern hardware (Apple M-series, Intel i7+):

  | Operation             | Time       | Throughput  | Memory |
  |-----------------------|------------|-------------|--------|
  | get(:price)           | 15-35ns    | 30-60M ips  | 40 B   |
  | decode (simple)       | 120-200ns  | 5-8M ips    | 400 B  |
  | encode (simple)       | 140-150ns  | 7M ips      | 180 B  |
  | encode (with string)  | 280-300ns  | 3.5M ips    | 280 B  |

  Notes:
  - `get` is fastest as it extracts a single field inline
  - Variable-length fields (string16) add ~100-150ns overhead
  - Memory is dominated by struct allocation during decode
  - Integer timestamps avoid DateTime overhead (~2.6% savings)

  ## Usage

      mix run benchmarks/encode_decode.exs
  """

  def run do
    # Prepare test data (use integer timestamps for optimal performance)
    order = %ExampleApp.Events.OrderCreated{
      order_id: :crypto.strong_rand_bytes(16),
      user_id: 12_345_678_901_234_567,
      symbol: "BTCUSD",
      side: 1,
      price: 15_000_000_000,
      quantity: 100_000,
      timestamp: System.system_time(:microsecond),
      flags: 7
    }

    trade = %ExampleApp.Events.TradeExecuted{
      trade_id: :crypto.strong_rand_bytes(16),
      order_id: :crypto.strong_rand_bytes(16),
      price: 15_000_000_000,
      quantity: 50_000,
      timestamp: System.system_time(:microsecond)
    }

    # encode/1 now includes header by default
    order_bin = ExampleApp.Events.OrderCreated.encode(order)
    trade_bin = ExampleApp.Events.TradeExecuted.encode(trade)

    IO.puts("OrderCreated binary size: #{byte_size(order_bin)} bytes (includes 8-byte header)")
    IO.puts("TradeExecuted binary size: #{byte_size(trade_bin)} bytes (includes 8-byte header)\n")

    require ExampleApp.Events.OrderCreated
    require ExampleApp.Events.TradeExecuted

    Benchee.run(
      %{
        "OrderCreated.encode" => fn -> ExampleApp.Events.OrderCreated.encode(order) end,
        "OrderCreated.decode" => fn -> ExampleApp.Events.OrderCreated.decode(order_bin) end,
        "OrderCreated.get(:price)" => fn -> ExampleApp.Events.OrderCreated.get(order_bin, :price) end,
        "TradeExecuted.encode" => fn -> ExampleApp.Events.TradeExecuted.encode(trade) end,
        "TradeExecuted.decode" => fn -> ExampleApp.Events.TradeExecuted.decode(trade_bin) end,
        "TradeExecuted.get(:price)" => fn -> ExampleApp.Events.TradeExecuted.get(trade_bin, :price) end
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
