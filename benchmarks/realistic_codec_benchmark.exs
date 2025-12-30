# Realistic Codec Benchmark
#
# Tests GridCodec with production-scale message structures from production workloads.
# Based on actual trading events: OrderSubmitted (18 fields), TradeExecuted (15 fields)

IO.puts(String.duplicate("=", 80))
IO.puts("REALISTIC CODEC BENCHMARK - Production Message Structures")
IO.puts(String.duplicate("=", 80))

# =============================================================================
# Enum Definitions
# =============================================================================

defmodule BenchmarkEnums.Side do
  use GridCodec.Types.Enum, encoding: :u8
  defenum do
    value :buy, 0
    value :sell, 1
  end
end

defmodule BenchmarkEnums.OrderType do
  use GridCodec.Types.Enum, encoding: :u8
  defenum do
    value :limit, 0
    value :market, 1
    value :stop, 2
    value :stop_limit, 3
  end
end

defmodule BenchmarkEnums.TimeInForce do
  use GridCodec.Types.Enum, encoding: :u8
  defenum do
    value :gtc, 0
    value :ioc, 1
    value :fok, 2
    value :day, 3
  end
end

defmodule BenchmarkEnums.AccountType do
  use GridCodec.Types.Enum, encoding: :u8
  defenum do
    value :currency, 0
    value :trading, 1
  end
end

# =============================================================================
# OrderSubmitted - 18 fields, mixed types
# =============================================================================

defmodule OrderSubmittedCodec do
  @moduledoc """
  Codec for OrderSubmitted event.

  18 fields including:
  - 6 UUIDs (16 bytes each = 96 bytes)
  - 3 enums (1 byte each = 3 bytes)
  - 1 integer quantity (8 bytes)
  - 5 decimals as i64 (8 bytes each = 40 bytes)
  - 2 timestamps (8 bytes each = 16 bytes)

  Total fixed: ~163 bytes
  """
  use GridCodec,
    types: [
      side: BenchmarkEnums.Side,
      order_type: BenchmarkEnums.OrderType,
      time_in_force: BenchmarkEnums.TimeInForce
    ]

  defcodec do
    # UUIDs (16 bytes each)
    field(:order_id, :uuid)
    field(:market_id, :uuid)
    field(:trader_id, :uuid)
    field(:trading_account_id, :uuid)
    field(:instrument_id, :uuid)
    field(:client_order_id, :uuid)  # nullable

    # Enums (registered in types: option)
    field(:side, :side)
    field(:order_type, :order_type)
    field(:time_in_force, :time_in_force)

    # Quantity (integer, u64)
    field(:quantity, :u64)

    # Prices as scaled integers (price * 10^8 for 8 decimal places)
    field(:price, :i64)           # nullable
    field(:stop_price, :i64)      # nullable
    field(:fee, :i64)
    field(:max_spend, :i64)       # nullable
    field(:max_price, :i64)       # nullable
    field(:max_slippage, :i64)    # nullable

    # Timestamps as microseconds since epoch
    field(:expires_at, :timestamp_us)  # nullable
    field(:submitted_at, :timestamp_us)
  end
end

# =============================================================================
# TradeExecuted - 15 fields
# =============================================================================

defmodule TradeExecutedCodec do
  @moduledoc """
  Codec for TradeExecuted event.

  16 fields:
  - 11 UUIDs (176 bytes)
  - 1 enum (1 byte)
  - 1 integer quantity (8 bytes)
  - 2 prices as i64 (16 bytes)
  - 1 timestamp (8 bytes)

  Total fixed: ~209 bytes
  """
  use GridCodec, types: [order_type: BenchmarkEnums.OrderType]

  defcodec do
    field(:trade_id, :uuid)
    field(:market_id, :uuid)
    field(:instrument_id, :uuid)
    field(:buyer_order_id, :uuid)
    field(:seller_order_id, :uuid)
    field(:triggering_order_id, :uuid)
    field(:triggering_order_type, :order_type)
    field(:buyer_user_id, :uuid)
    field(:seller_user_id, :uuid)
    field(:buyer_trading_account_id, :uuid)
    field(:seller_trading_account_id, :uuid)
    field(:quantity, :u64)
    field(:price, :i64)
    field(:fee, :i64)
    field(:total_value, :i64)
    field(:execution_timestamp, :timestamp_us)
  end
end

# =============================================================================
# ReservationCreated - 17 fields with mixed optionality
# =============================================================================

defmodule ReservationCodec do
  @moduledoc """
  Codec for ReservationCreated event.

  16 fields with many optional fields (common in real events).
  """
  use GridCodec,
    types: [
      account_type: BenchmarkEnums.AccountType,
      side: BenchmarkEnums.Side,
      order_type: BenchmarkEnums.OrderType
    ]

  defcodec do
    field(:reservation_id, :uuid)
    field(:account_id, :uuid)
    field(:account_type, :account_type)
    field(:amount, :i64)
    field(:order_id, :uuid)
    field(:user_id, :uuid)
    field(:created_at, :timestamp_us)
    field(:market_id, :uuid)          # optional
    field(:instrument_id, :uuid)      # optional
    field(:side, :side)               # optional
    field(:order_type, :order_type)   # optional
    field(:quantity, :u64)            # optional
    field(:price, :i64)               # optional
    field(:fee, :i64)                 # optional
    field(:max_price, :i64)           # optional
    field(:trading_account_id, :uuid) # optional
  end
end

# =============================================================================
# Simple 3-field codec for comparison
# =============================================================================

defmodule SimpleCodec do
  use GridCodec
  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

# =============================================================================
# Test Data Generators
# =============================================================================

defmodule TestData do
  def uuid, do: :crypto.strong_rand_bytes(16)

  def order_submitted do
    %{
      order_id: uuid(),
      market_id: uuid(),
      trader_id: uuid(),
      trading_account_id: uuid(),
      instrument_id: uuid(),
      client_order_id: uuid(),
      side: :buy,
      order_type: :limit,
      time_in_force: :gtc,
      quantity: 1000,
      price: 15000_00000000,  # $150.00 scaled by 10^8
      stop_price: nil,
      fee: 10_00000000,       # $0.10
      max_spend: nil,
      max_price: nil,
      max_slippage: nil,
      expires_at: nil,
      submitted_at: System.system_time(:microsecond)
    }
  end

  def trade_executed do
    %{
      trade_id: uuid(),
      market_id: uuid(),
      instrument_id: uuid(),
      buyer_order_id: uuid(),
      seller_order_id: uuid(),
      triggering_order_id: uuid(),
      triggering_order_type: :limit,
      buyer_user_id: uuid(),
      seller_user_id: uuid(),
      buyer_trading_account_id: uuid(),
      seller_trading_account_id: uuid(),
      quantity: 100,
      price: 15000_00000000,
      fee: 10_00000000,
      total_value: 1500000_00000000,
      execution_timestamp: System.system_time(:microsecond)
    }
  end

  def reservation do
    %{
      reservation_id: uuid(),
      account_id: uuid(),
      account_type: :currency,
      amount: 150000_00000000,
      order_id: uuid(),
      user_id: uuid(),
      created_at: System.system_time(:microsecond),
      market_id: uuid(),
      instrument_id: uuid(),
      side: :buy,
      order_type: :limit,
      quantity: 1000,
      price: 15000_00000000,
      fee: 10_00000000,
      max_price: nil,
      trading_account_id: uuid()
    }
  end

  def simple do
    %{id: 12345678901234, count: 1000000, flag: true}
  end
end

# =============================================================================
# Verification
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("CODEC VERIFICATION")
IO.puts(String.duplicate("-", 80))

# Test each codec
for {name, codec, data_fn} <- [
  {"SimpleCodec (3 fields)", SimpleCodec, &TestData.simple/0},
  {"OrderSubmittedCodec (18 fields)", OrderSubmittedCodec, &TestData.order_submitted/0},
  {"TradeExecutedCodec (15 fields)", TradeExecutedCodec, &TestData.trade_executed/0},
  {"ReservationCodec (16 fields)", ReservationCodec, &TestData.reservation/0}
] do
  data = data_fn.()
  binary = codec.encode(data)
  {:ok, decoded} = codec.decode(binary)

  # Check roundtrip
  re_encoded = codec.encode(decoded)
  roundtrip_ok = binary == re_encoded

  IO.puts("\n#{name}:")
  IO.puts("  Block length: #{codec.block_length()} bytes")
  IO.puts("  Binary size:  #{byte_size(binary)} bytes")
  IO.puts("  Roundtrip:    #{if roundtrip_ok, do: "✓ OK", else: "✗ FAIL"}")
end

# =============================================================================
# Benchmark
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("ENCODE BENCHMARK")
IO.puts(String.duplicate("-", 80))

simple_data = TestData.simple()
order_data = TestData.order_submitted()
trade_data = TestData.trade_executed()
reservation_data = TestData.reservation()

Benchee.run(
  %{
    "Simple (3 fields, 13B)" => fn -> SimpleCodec.encode(simple_data) end,
    "OrderSubmitted (18 fields, ~170B)" => fn -> OrderSubmittedCodec.encode(order_data) end,
    "TradeExecuted (15 fields, ~190B)" => fn -> TradeExecutedCodec.encode(trade_data) end,
    "Reservation (16 fields, ~170B)" => fn -> ReservationCodec.encode(reservation_data) end,
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  print: [fast_warning: false]
)

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("DECODE BENCHMARK")
IO.puts(String.duplicate("-", 80))

simple_bin = SimpleCodec.encode(simple_data)
order_bin = OrderSubmittedCodec.encode(order_data)
trade_bin = TradeExecutedCodec.encode(trade_data)
reservation_bin = ReservationCodec.encode(reservation_data)

Benchee.run(
  %{
    "Simple (3 fields)" => fn -> SimpleCodec.decode(simple_bin) end,
    "OrderSubmitted (18 fields)" => fn -> OrderSubmittedCodec.decode(order_bin) end,
    "TradeExecuted (15 fields)" => fn -> TradeExecutedCodec.decode(trade_bin) end,
    "Reservation (16 fields)" => fn -> ReservationCodec.decode(reservation_bin) end,
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  print: [fast_warning: false]
)

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("ZERO-COPY GET BENCHMARK (Single Field Access)")
IO.puts(String.duplicate("-", 80))

# Wrap binaries for zero-copy access
simple_env = SimpleCodec.wrap(simple_bin)
order_env = OrderSubmittedCodec.wrap(order_bin)
trade_env = TradeExecutedCodec.wrap(trade_bin)

IO.puts("\nField names for reference:")
IO.puts("  OrderSubmitted fields: #{inspect(OrderSubmittedCodec.__schema__().fixed_fields)}")
IO.puts("  TradeExecuted fields: #{inspect(TradeExecutedCodec.__schema__().fixed_fields)}")

Benchee.run(
  %{
    "Simple.get(:id)" => fn -> SimpleCodec.get(simple_env, :id) end,
    "OrderSubmitted.get(:side)" => fn -> OrderSubmittedCodec.get(order_env, :side) end,
    "OrderSubmitted.get(:quantity)" => fn -> OrderSubmittedCodec.get(order_env, :quantity) end,
    "TradeExecuted.get(:quantity)" => fn -> TradeExecutedCodec.get(trade_env, :quantity) end,
    "TradeExecuted.get(:price)" => fn -> TradeExecutedCodec.get(trade_env, :price) end,
  },
  warmup: 2,
  time: 5,
  print: [fast_warning: false]
)

# =============================================================================
# Throughput Analysis
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("THROUGHPUT ANALYSIS")
IO.puts(String.duplicate("-", 80))

# Measure raw throughput
measure_throughput = fn codec, data, iterations ->
  {time_us, _} = :timer.tc(fn ->
    for _ <- 1..iterations, do: codec.encode(data)
  end)

  binary = codec.encode(data)
  bytes_per_sec = (iterations * byte_size(binary)) / (time_us / 1_000_000)
  msgs_per_sec = iterations / (time_us / 1_000_000)

  {msgs_per_sec, bytes_per_sec}
end

iterations = 100_000

for {name, codec, data_fn} <- [
  {"Simple", SimpleCodec, &TestData.simple/0},
  {"OrderSubmitted", OrderSubmittedCodec, &TestData.order_submitted/0},
  {"TradeExecuted", TradeExecutedCodec, &TestData.trade_executed/0},
  {"Reservation", ReservationCodec, &TestData.reservation/0}
] do
  data = data_fn.()
  {msgs, bytes} = measure_throughput.(codec, data, iterations)

  IO.puts("\n#{name}:")
  IO.puts("  Messages/sec: #{Float.round(msgs / 1_000_000, 2)} M")
  IO.puts("  Throughput:   #{Float.round(bytes / 1_000_000, 1)} MB/s")
  IO.puts("  Latency:      #{Float.round(1_000_000_000 / msgs, 1)} ns/msg")
end

# =============================================================================
# Memory Analysis
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("MEMORY ANALYSIS")
IO.puts(String.duplicate("-", 80))

analyze_memory = fn codec, data, iterations ->
  :erlang.garbage_collect()
  {_, mem_before} = Process.info(self(), :memory)
  gc_before = :erlang.statistics(:garbage_collection)

  binaries = for _ <- 1..iterations, do: codec.encode(data)

  {_, mem_after} = Process.info(self(), :memory)
  gc_after = :erlang.statistics(:garbage_collection)

  # Keep binaries alive for measurement
  _ = length(binaries)

  {gc_before_count, _, _} = gc_before
  {gc_after_count, _, _} = gc_after

  %{
    memory_delta: mem_after - mem_before,
    gc_count: gc_after_count - gc_before_count,
    binary_size: byte_size(hd(binaries))
  }
end

for {name, codec, data_fn} <- [
  {"Simple", SimpleCodec, &TestData.simple/0},
  {"OrderSubmitted", OrderSubmittedCodec, &TestData.order_submitted/0},
  {"TradeExecuted", TradeExecutedCodec, &TestData.trade_executed/0}
] do
  data = data_fn.()
  stats = analyze_memory.(codec, data, 10_000)

  IO.puts("\n#{name} (10k encodes):")
  IO.puts("  Memory delta: #{Float.round(stats.memory_delta / 1024, 1)} KB")
  IO.puts("  GC count:     #{stats.gc_count}")
  IO.puts("  Binary size:  #{stats.binary_size} bytes")
  IO.puts("  Binary type:  #{if stats.binary_size < 64, do: "heap", else: "refc"}")
end

# =============================================================================
# Bytecode Analysis for Realistic Codec
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("BYTECODE ANALYSIS - OrderSubmittedCodec")
IO.puts(String.duplicate("-", 80))

{OrderSubmittedCodec, beam, _} = :code.get_object_code(OrderSubmittedCodec)
{:beam_file, _, _, _, _, functions} = :beam_disasm.file(beam)

for {:function, name, arity, _label, instructions} <- functions do
  if name == :encode and arity == 1 do
    IO.puts("\nencode/1: #{length(instructions)} instructions")

    # Count key instruction types
    counts = instructions
      |> Enum.map(fn instr ->
        case instr do
          {:get_map_elements, _, _, _} -> :get_map_elements
          {:test, _, _, _} -> :test
          {:select_val, _, _, _} -> :select_val
          {:bs_create_bin, _, _, _, _, _, _} -> :bs_create_bin
          {:move, _, _} -> :move
          {:call_ext, _, _} -> :call_ext
          _ -> :other
        end
      end)
      |> Enum.frequencies()

    IO.puts("  get_map_elements: #{Map.get(counts, :get_map_elements, 0)}")
    IO.puts("  test (branches):  #{Map.get(counts, :test, 0)}")
    IO.puts("  select_val:       #{Map.get(counts, :select_val, 0)}")
    IO.puts("  bs_create_bin:    #{Map.get(counts, :bs_create_bin, 0)}")
    IO.puts("  move:             #{Map.get(counts, :move, 0)}")
    IO.puts("  call_ext:         #{Map.get(counts, :call_ext, 0)}")
  end
end

# =============================================================================
# Summary
# =============================================================================

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("SUMMARY")
IO.puts(String.duplicate("=", 80))

IO.puts("""

FINDINGS:
---------
This benchmark tests GridCodec with production-scale messages:

1. OrderSubmitted: 18 fields, ~170 bytes
   - UUIDs, enums, integers, timestamps, decimals
   - Mix of required and optional fields

2. TradeExecuted: 15 fields, ~190 bytes
   - 10 UUIDs, 1 enum, prices, timestamps

3. Reservation: 16 fields, ~170 bytes
   - Many optional fields (common in real events)

KEY METRICS TO WATCH:
- Encode latency should scale roughly linearly with field count
- Memory allocation should be minimal (heap binaries)
- Zero-copy get should be constant time regardless of message size

COMPARISON TO JSON:
- JSON OrderSubmitted: ~600-800 bytes
- GridCodec: ~170 bytes (4-5x smaller)
- JSON encode: ~500ns-1µs
- GridCodec encode: target <50ns

""")
