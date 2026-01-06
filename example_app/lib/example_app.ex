defmodule ExampleApp do
  @moduledoc """
  Example application demonstrating GridCodec.Struct usage.

  This app shows real-world usage patterns for high-performance
  binary encoding/decoding with struct codecs.

  ## Usage

      cd example_app
      mix deps.get
      mix compile
      mix bench.quick    # Quick development benchmark
      mix bench          # Full benchmark suite

  ## Example Codecs

  See `lib/example_app/events/` for example event codecs:
  - `ExampleApp.Events.OrderCreated` - Order creation event
  - `ExampleApp.Events.TradeExecuted` - Trade execution event

  Both codecs use `GridCodec.Struct` for optimal performance:
  - Direct struct pattern matching (no Map.from_struct)
  - Inline binary construction
  - Zero-copy field access via wrap/get
  """

  @doc """
  Example usage of GridCodec.Struct.
  """
  def example_usage do
    # Create an order event
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

    # Encode
    binary = ExampleApp.Events.OrderCreated.encode(order)
    IO.puts("Encoded to #{byte_size(binary)} bytes")

    # Decode
    {:ok, decoded} = ExampleApp.Events.OrderCreated.decode(binary)
    IO.puts("Decoded: #{inspect(decoded.symbol)}")

    # Dispatch (with consolidated registry)
    framed = GridCodec.encode(order)
    {:ok, decoded} = GridCodec.decode(framed)
    IO.puts("Dispatched and decoded: #{inspect(decoded.symbol)}")

    :ok
  end
end
