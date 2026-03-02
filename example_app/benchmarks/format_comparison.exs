# Format Comparison Benchmark
#
# Compares GridCodec vs JSON (Jason), ETF (:erlang.term_to_binary), and Protobuf
# for encoding and decoding a realistic event struct.
#
# Run from example_app/:
#   mix run benchmarks/format_comparison.exs

alias ExampleApp.Events.OrderCreated
alias ExampleApp.Bench.OrderCreatedProto

# ---------------------------------------------------------------------------
# Test data
# ---------------------------------------------------------------------------

order_id = :crypto.strong_rand_bytes(16)
ts = System.system_time(:microsecond)

gridcodec_struct = %OrderCreated{
  order_id: order_id,
  user_id: 123_456_789,
  symbol: "BTC/USD",
  side: 1,
  price: 67_500_00,
  quantity: 1_000,
  timestamp: ts,
  flags: 3
}

json_map = %{
  "order_id" => Base.encode16(order_id, case: :lower),
  "user_id" => 123_456_789,
  "symbol" => "BTC/USD",
  "side" => 1,
  "price" => 67_500_00,
  "quantity" => 1_000,
  "timestamp" => ts,
  "flags" => 3
}

etf_map = %{
  order_id: order_id,
  user_id: 123_456_789,
  symbol: "BTC/USD",
  side: 1,
  price: 67_500_00,
  quantity: 1_000,
  timestamp: ts,
  flags: 3
}

proto_struct = %OrderCreatedProto{
  order_id: order_id,
  user_id: 123_456_789,
  symbol: "BTC/USD",
  side: 1,
  price: 67_500_00,
  quantity: 1_000,
  timestamp: ts,
  flags: 3
}

# ---------------------------------------------------------------------------
# Pre-encode for decode benchmarks
# ---------------------------------------------------------------------------

gridcodec_bin = OrderCreated.encode(gridcodec_struct)
json_bin = Jason.encode!(json_map)
etf_bin = :erlang.term_to_binary(etf_map)
proto_bin = OrderCreatedProto.encode(proto_struct)

# ---------------------------------------------------------------------------
# Print sizes
# ---------------------------------------------------------------------------

IO.puts("""

=== Binary Sizes ===
  GridCodec:  #{byte_size(gridcodec_bin)} bytes
  JSON:       #{byte_size(json_bin)} bytes
  ETF:        #{byte_size(etf_bin)} bytes
  Protobuf:   #{byte_size(proto_bin)} bytes
""")

# ---------------------------------------------------------------------------
# Encode benchmark
# ---------------------------------------------------------------------------

IO.puts("=== Encode Benchmark ===\n")

Benchee.run(
  %{
    "GridCodec" => fn -> OrderCreated.encode(gridcodec_struct) end,
    "JSON (Jason)" => fn -> Jason.encode!(json_map) end,
    "ETF (term_to_binary)" => fn -> :erlang.term_to_binary(etf_map) end,
    "Protobuf" => fn -> OrderCreatedProto.encode(proto_struct) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)

# ---------------------------------------------------------------------------
# Decode benchmark
# ---------------------------------------------------------------------------

IO.puts("\n=== Decode Benchmark ===\n")

Benchee.run(
  %{
    "GridCodec" => fn -> OrderCreated.decode(gridcodec_bin) end,
    "JSON (Jason)" => fn -> Jason.decode!(json_bin) end,
    "ETF (binary_to_term)" => fn -> :erlang.binary_to_term(etf_bin) end,
    "Protobuf" => fn -> OrderCreatedProto.decode(proto_bin) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)

# ---------------------------------------------------------------------------
# Single-field access (GridCodec zero-copy vs full decode)
# ---------------------------------------------------------------------------

IO.puts("\n=== Single Field Access (read :price) ===\n")

require OrderCreated

Benchee.run(
  %{
    "GridCodec get/2 (zero-copy)" => fn -> OrderCreated.get(gridcodec_bin, :price) end,
    "GridCodec full decode" => fn ->
      {:ok, d} = OrderCreated.decode(gridcodec_bin)
      d.price
    end,
    "JSON decode + access" => fn ->
      d = Jason.decode!(json_bin)
      d["price"]
    end,
    "ETF decode + access" => fn ->
      d = :erlang.binary_to_term(etf_bin)
      d.price
    end,
    "Protobuf decode + access" => fn ->
      d = OrderCreatedProto.decode(proto_bin)
      d.price
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)
