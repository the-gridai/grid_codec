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
  - `ExampleApp.Views.CurrencyAccount` — typed-group example with generated lookups
  - `ExampleApp.Views.CommandEnvelope` — batch example with per-type keyed lookups
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
      MIX_ENV=prod mix run benchmarks/lookup_bench.exs
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

  @doc """
  Example usage of typed groups and generated lookups.
  """
  def lookup_usage do
    alias ExampleApp.Views.{CommandEnvelope, CurrencyAccount, Fixtures}

    account = Fixtures.account(3)
    {:ok, account_binary} = CurrencyAccount.encode(account)
    {:ok, decoded_account} = CurrencyAccount.decode(account_binary)

    {:ok, reservations_by_id} = CurrencyAccount.reservations_by_id(decoded_account)
    {:ok, active_reservations} = CurrencyAccount.active_reservations(decoded_account)

    IO.puts("Reservation keys: #{inspect(Map.keys(reservations_by_id))}")
    IO.puts("Active reservations: #{length(active_reservations)}")

    envelope = Fixtures.command_envelope(4)
    {:ok, envelope_binary} = CommandEnvelope.encode(envelope)
    {:ok, decoded_envelope} = CommandEnvelope.decode(envelope_binary)
    {:ok, commands_by_id} = CommandEnvelope.commands_by_reservation_id(decoded_envelope)

    IO.puts("Command keys: #{inspect(Map.keys(commands_by_id))}")
    :ok
  end

  @doc false
  def view_usage, do: lookup_usage()
end
