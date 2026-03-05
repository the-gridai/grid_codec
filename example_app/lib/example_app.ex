defmodule ExampleApp do
  @moduledoc """
  Example application demonstrating GridCodec features.

  ## Quick start

      cd example_app
      mix deps.get
      mix compile
      mix bench.quick

  ## Codecs

  - `ExampleApp.Events.OrderCreated` — order creation event
  - `ExampleApp.Events.TradeExecuted` — trade execution event
  - `ExampleApp.Bench.BinaryTraceContext` — OpenTelemetry-style span
  - `ExampleApp.Bench.BinaryEnvelope` — compact routing header

  ## Match predicates

  - `ExampleApp.SpanFilters` — filter spans by sampled bit, duration, kind
  - `ExampleApp.OrderFilters` — filter orders by side, price, flags

  ## Transcoders

  - `ExampleApp.SpanToEnvelope` — span → envelope without full decode

  ## Benchmarks

      mix bench.quick                                    # Quick encode/decode
      MIX_ENV=prod mix run benchmarks/ets_binary_bench.exs  # ETS patterns
      MIX_ENV=prod mix run benchmarks/trace_context_bench.exs
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

    # Encode with header (default)
    {:ok, binary} = ExampleApp.Events.OrderCreated.encode(order)
    IO.puts("Encoded to #{byte_size(binary)} bytes (with 8-byte header)")

    # Decode (expects header by default)
    {:ok, decoded} = ExampleApp.Events.OrderCreated.decode(binary)
    IO.puts("Decoded: #{inspect(decoded.symbol)}")

    # Payload only (no header)
    {:ok, payload} = ExampleApp.Events.OrderCreated.encode(order, header: false)
    IO.puts("Payload only: #{byte_size(payload)} bytes")
    {:ok, decoded2} = ExampleApp.Events.OrderCreated.decode(payload, header: false)
    IO.puts("Decoded payload: #{inspect(decoded2.symbol)}")

    # Dispatch via GridCodec (always uses header)
    {:ok, framed} = GridCodec.encode(order)
    {:ok, decoded3} = GridCodec.decode(framed)
    IO.puts("Dispatched and decoded: #{inspect(decoded3.symbol)}")

    :ok
  end
end
