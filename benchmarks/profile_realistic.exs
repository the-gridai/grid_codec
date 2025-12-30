# Profiling Realistic Codecs
#
# Run with: mix run benchmarks/profile_realistic.exs
#
# This script profiles encode/decode operations for production-scale codecs.

# Define enum types
defmodule ProfileEnums do
  defmodule Side do
    use GridCodec.Types.Enum, encoding: :u8
    defenum do
      value :buy, 0
      value :sell, 1
    end
  end

  defmodule OrderType do
    use GridCodec.Types.Enum, encoding: :u8
    defenum do
      value :limit, 0
      value :market, 1
      value :stop, 2
      value :stop_limit, 3
    end
  end

  defmodule TimeInForce do
    use GridCodec.Types.Enum, encoding: :u8
    defenum do
      value :gtc, 0
      value :ioc, 1
      value :fok, 2
      value :day, 3
    end
  end
end

# Production-scale codec (18 fields)
defmodule ProfileOrderCodec do
  use GridCodec,
    types: [
      side: ProfileEnums.Side,
      order_type: ProfileEnums.OrderType,
      time_in_force: ProfileEnums.TimeInForce
    ]

  defcodec do
    field(:order_id, :uuid)
    field(:market_id, :uuid)
    field(:trader_id, :uuid)
    field(:trading_account_id, :uuid)
    field(:instrument_id, :uuid)
    field(:client_order_id, :uuid)
    field(:side, :side)
    field(:order_type, :order_type)
    field(:time_in_force, :time_in_force)
    field(:quantity, :u64)
    field(:price, :decimal)
    field(:stop_price, :decimal)
    field(:fee, :decimal)
    field(:max_spend, :decimal)
    field(:max_price, :decimal)
    field(:max_slippage, :decimal)
    field(:expires_at, :timestamp_us)
    field(:submitted_at, :timestamp_us)
  end
end

# Generate test data
test_data = %{
  order_id: :crypto.strong_rand_bytes(16),
  market_id: :crypto.strong_rand_bytes(16),
  trader_id: :crypto.strong_rand_bytes(16),
  trading_account_id: :crypto.strong_rand_bytes(16),
  instrument_id: :crypto.strong_rand_bytes(16),
  client_order_id: :crypto.strong_rand_bytes(16),
  side: :buy,
  order_type: :limit,
  time_in_force: :gtc,
  quantity: 1000,
  price: Decimal.new("123.45"),
  stop_price: nil,
  fee: Decimal.new("0.001"),
  max_spend: nil,
  max_price: nil,
  max_slippage: nil,
  expires_at: System.system_time(:microsecond),
  submitted_at: System.system_time(:microsecond)
}

binary = ProfileOrderCodec.encode(test_data)

IO.puts("""
================================================================================
PROFILING REALISTIC CODEC (ProfileOrderCodec - 18 fields)
================================================================================
  Block Length: #{ProfileOrderCodec.block_length()} bytes
  Binary Size:  #{byte_size(binary)} bytes
  Fields:       18 (including 6 UUIDs, 6 Decimals, 3 Enums)
""")

iterations = 100_000

# Warm up
for _ <- 1..1000 do
  ProfileOrderCodec.encode(test_data)
  ProfileOrderCodec.decode(binary)
end

# Note: Detailed profiling with :tprof/:eprof requires full OTP build
# Using timing-based profiling instead

IO.puts("\n--- TIMING SUMMARY ---\n")

# Time encode
{encode_time, _} = :timer.tc(fn ->
  for _ <- 1..iterations, do: ProfileOrderCodec.encode(test_data)
end)

# Time decode
{decode_time, _} = :timer.tc(fn ->
  for _ <- 1..iterations, do: ProfileOrderCodec.decode(binary)
end)

# Time get (zero-copy)
env = ProfileOrderCodec.wrap(binary)
{get_time, _} = :timer.tc(fn ->
  for _ <- 1..iterations, do: ProfileOrderCodec.get(env, :quantity)
end)

IO.puts("  Encode: #{encode_time / iterations} us/op (#{iterations * 1_000_000 / encode_time |> round()} ops/sec)")
IO.puts("  Decode: #{decode_time / iterations} us/op (#{iterations * 1_000_000 / decode_time |> round()} ops/sec)")
IO.puts("  Get:    #{get_time / iterations} us/op (#{iterations * 1_000_000 / get_time |> round()} ops/sec)")
IO.puts("")
IO.puts("  Throughput (encode): #{iterations * byte_size(binary) / encode_time} MB/s")
IO.puts("  Throughput (decode): #{iterations * byte_size(binary) / decode_time} MB/s")

# Memory profiling
IO.puts("\n--- MEMORY ANALYSIS ---\n")

Process.put(:gc_count, 0)
:erlang.trace(self(), true, [:garbage_collection])

for _ <- 1..10_000, do: ProfileOrderCodec.encode(test_data)

# Count GC events
gc_count =
  Stream.repeatedly(fn ->
    receive do
      {:trace, _, :gc_minor_start, _} -> :gc
      {:trace, _, :gc_major_start, _} -> :gc
    after
      0 -> nil
    end
  end)
  |> Enum.take_while(&(&1 != nil))
  |> length()

:erlang.trace(self(), false, [:garbage_collection])

IO.puts("  GC events during 10k encodes: #{gc_count}")
IO.puts("  Est. GC per encode: #{gc_count / 10_000}")

# Final summary
IO.puts("""

================================================================================
SUMMARY
================================================================================
Profile completed. Key metrics:
- Block length: #{ProfileOrderCodec.block_length()} bytes
- Encode time:  #{Float.round(encode_time / iterations * 1000, 2)} ns/op
- Decode time:  #{Float.round(decode_time / iterations * 1000, 2)} ns/op
- Get time:     #{Float.round(get_time / iterations * 1000, 2)} ns/op
- Encode throughput: #{Float.round(iterations * byte_size(binary) / encode_time, 1)} MB/s
================================================================================
""")
