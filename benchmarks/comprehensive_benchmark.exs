# Comprehensive Benchmark: GridCodec vs ElixirProto vs ETF vs JSON vs Protobuf
#
# Run with: mix run benchmarks/comprehensive_benchmark.exs
#
# This benchmark covers:
# 1. Standard encoding/decoding (7 fields)
# 2. Sparse data (many nil fields)
# 3. Large structs (20+ fields)
# 4. Batch encoding (100 messages)
# 5. Roundtrip (encode → decode → access)
# 6. Zero-copy field access (GridCodec unique feature)

IO.puts("""
╔══════════════════════════════════════════════════════════════════════════════╗
║           COMPREHENSIVE CODEC BENCHMARK                                       ║
║                                                                               ║
║  GridCodec vs ElixirProto vs ETF vs JSON vs Protobuf vs MessagePack          ║
╚══════════════════════════════════════════════════════════════════════════════╝
""")

# ==============================================================================
# GridCodec Definitions
# ==============================================================================

defmodule Bench.GridCodec.Order do
  use GridCodec

  defcodec do
    field(:order_id, :uuid)
    field(:user_id, :u64)
    field(:price, :u64)
    field(:quantity, :u32)
    field(:side, :u8)
    field(:timestamp, :timestamp_us)
    field(:flags, :u8)
  end
end

defmodule Bench.GridCodec.SparseOrder do
  @moduledoc "Order with many optional fields - tests sparse data handling"
  use GridCodec

  defcodec do
    field(:order_id, :uuid)
    field(:user_id, :u64)
    field(:price, :u64, presence: :optional)
    field(:quantity, :u32, presence: :optional)
    field(:side, :u8)
    field(:stop_price, :u64, presence: :optional)
    field(:limit_price, :u64, presence: :optional)
    field(:trigger_price, :u64, presence: :optional)
    field(:trail_amount, :u64, presence: :optional)
    field(:trail_percent, :u32, presence: :optional)
    field(:display_qty, :u32, presence: :optional)
    field(:min_qty, :u32, presence: :optional)
    field(:flags, :u16)
  end
end

defmodule Bench.GridCodec.LargeOrder do
  @moduledoc "Full order with 20 fields - tests large message handling"
  use GridCodec

  defcodec do
    field(:order_id, :uuid)
    field(:client_order_id, :u64)
    field(:parent_order_id, :u64)
    field(:user_id, :u64)
    field(:account_id, :u64)
    field(:instrument_id, :u64)
    field(:price, :u64)
    field(:stop_price, :u64)
    field(:quantity, :u64)
    field(:filled_qty, :u64)
    field(:remaining_qty, :u64)
    field(:side, :u8)
    field(:order_type, :u8)
    field(:time_in_force, :u8)
    field(:status, :u8)
    field(:exec_inst, :u16)
    field(:flags, :u16)
    field(:created_at, :timestamp_us)
    field(:updated_at, :timestamp_us)
    field(:version, :u32)
  end
end

# ==============================================================================
# ElixirProto Definitions
# ==============================================================================

defmodule Bench.ElixirProto.Order do
  use ElixirProto.Schema, name: "bench.order"
  defschema([:order_id, :user_id, :price, :quantity, :side, :timestamp, :flags])
end

defmodule Bench.ElixirProto.SparseOrder do
  use ElixirProto.Schema, name: "bench.sparse_order"

  defschema([
    :order_id,
    :user_id,
    :price,
    :quantity,
    :side,
    :stop_price,
    :limit_price,
    :trigger_price,
    :trail_amount,
    :trail_percent,
    :display_qty,
    :min_qty,
    :flags
  ])
end

defmodule Bench.ElixirProto.LargeOrder do
  use ElixirProto.Schema, name: "bench.large_order"

  defschema([
    :order_id,
    :client_order_id,
    :parent_order_id,
    :user_id,
    :account_id,
    :instrument_id,
    :price,
    :stop_price,
    :quantity,
    :filled_qty,
    :remaining_qty,
    :side,
    :order_type,
    :time_in_force,
    :status,
    :exec_inst,
    :flags,
    :created_at,
    :updated_at,
    :version
  ])
end

defmodule Bench.ElixirProto.Converter do
  use ElixirProto.PayloadConverter,
    mapping: [
      {1, "bench.order"},
      {2, "bench.sparse_order"},
      {3, "bench.large_order"}
    ]
end

# ==============================================================================
# Protobuf Definitions
# ==============================================================================

defmodule Bench.Protobuf.Order do
  use Protobuf, syntax: :proto3

  field(:order_id, 1, type: :bytes)
  field(:user_id, 2, type: :uint64)
  field(:price, 3, type: :uint64)
  field(:quantity, 4, type: :uint32)
  field(:side, 5, type: :uint32)
  field(:timestamp, 6, type: :int64)
  field(:flags, 7, type: :uint32)
end

defmodule Bench.Protobuf.LargeOrder do
  use Protobuf, syntax: :proto3

  field(:order_id, 1, type: :bytes)
  field(:client_order_id, 2, type: :uint64)
  field(:parent_order_id, 3, type: :uint64)
  field(:user_id, 4, type: :uint64)
  field(:account_id, 5, type: :uint64)
  field(:instrument_id, 6, type: :uint64)
  field(:price, 7, type: :uint64)
  field(:stop_price, 8, type: :uint64)
  field(:quantity, 9, type: :uint64)
  field(:filled_qty, 10, type: :uint64)
  field(:remaining_qty, 11, type: :uint64)
  field(:side, 12, type: :uint32)
  field(:order_type, 13, type: :uint32)
  field(:time_in_force, 14, type: :uint32)
  field(:status, 15, type: :uint32)
  field(:exec_inst, 16, type: :uint32)
  field(:flags, 17, type: :uint32)
  field(:created_at, 18, type: :int64)
  field(:updated_at, 19, type: :int64)
  field(:version, 20, type: :uint32)
end

# ==============================================================================
# Helper Modules
# ==============================================================================

defmodule Bench.ETF do
  def encode(data), do: :erlang.term_to_binary(data)
  def encode_compressed(data), do: :erlang.term_to_binary(data, [:compressed])
  def decode(binary), do: :erlang.binary_to_term(binary)
end

defmodule Bench.JSON do
  def encode(data), do: Jason.encode!(data)
  def decode(binary), do: Jason.decode!(binary)
end

defmodule Bench.OtpJSON do
  def encode(data), do: :json.encode(data) |> IO.iodata_to_binary()
  def decode(binary), do: :json.decode(binary)
end

defmodule Bench.Msgpack do
  def encode(data) do
    # Convert binary UUID to base64 for msgpack
    data =
      if Map.has_key?(data, :order_id) and is_binary(data.order_id) do
        Map.update!(data, :order_id, &Base.encode64/1)
      else
        data
      end

    Msgpax.pack!(data) |> IO.iodata_to_binary()
  end

  def decode(binary), do: Msgpax.unpack!(binary)
end

# ==============================================================================
# Test Data Generation
# ==============================================================================

IO.puts("Setting up test data...\n")

order_id = :crypto.strong_rand_bytes(16)
timestamp = System.system_time(:microsecond)

# Standard order (7 fields)
standard_data = %{
  order_id: order_id,
  user_id: 12_345_678_901_234_567,
  price: 15_000_000_000,
  quantity: 100_000,
  side: 1,
  timestamp: timestamp,
  flags: 7
}

standard_json = %{
  "order_id" => Base.encode64(order_id),
  "user_id" => 12_345_678_901_234_567,
  "price" => 15_000_000_000,
  "quantity" => 100_000,
  "side" => 1,
  "timestamp" => timestamp,
  "flags" => 7
}

# Sparse order - only 5 of 13 fields populated (like ElixirProto's sparse test)
sparse_data = %{
  order_id: order_id,
  user_id: 12_345_678_901_234_567,
  price: nil,
  quantity: nil,
  side: 1,
  stop_price: nil,
  limit_price: nil,
  trigger_price: nil,
  trail_amount: nil,
  trail_percent: nil,
  display_qty: nil,
  min_qty: nil,
  flags: 0
}

sparse_json = %{
  "order_id" => Base.encode64(order_id),
  "user_id" => 12_345_678_901_234_567,
  "side" => 1,
  "flags" => 0
}

# Large order (20 fields)
large_data = %{
  order_id: order_id,
  client_order_id: 999_999_999,
  parent_order_id: 888_888_888,
  user_id: 12_345_678_901_234_567,
  account_id: 77_777_777,
  instrument_id: 1001,
  price: 15_000_000_000,
  stop_price: 14_500_000_000,
  quantity: 100_000,
  filled_qty: 50_000,
  remaining_qty: 50_000,
  side: 1,
  order_type: 2,
  time_in_force: 1,
  status: 3,
  exec_inst: 256,
  flags: 7,
  created_at: timestamp,
  updated_at: timestamp,
  version: 5
}

large_json = %{
  "order_id" => Base.encode64(order_id),
  "client_order_id" => 999_999_999,
  "parent_order_id" => 888_888_888,
  "user_id" => 12_345_678_901_234_567,
  "account_id" => 77_777_777,
  "instrument_id" => 1001,
  "price" => 15_000_000_000,
  "stop_price" => 14_500_000_000,
  "quantity" => 100_000,
  "filled_qty" => 50_000,
  "remaining_qty" => 50_000,
  "side" => 1,
  "order_type" => 2,
  "time_in_force" => 1,
  "status" => 3,
  "exec_inst" => 256,
  "flags" => 7,
  "created_at" => timestamp,
  "updated_at" => timestamp,
  "version" => 5
}

# ElixirProto structs
elixir_proto_standard = struct!(Bench.ElixirProto.Order, standard_data)
elixir_proto_sparse = struct!(Bench.ElixirProto.SparseOrder, sparse_data)
elixir_proto_large = struct!(Bench.ElixirProto.LargeOrder, large_data)

# Protobuf structs
protobuf_standard = struct!(Bench.Protobuf.Order, standard_data)
protobuf_large = struct!(Bench.Protobuf.LargeOrder, large_data)

# Batch data - 100 orders with varying data
batch_data =
  for i <- 1..100 do
    %{
      order_id: :crypto.strong_rand_bytes(16),
      user_id: 12_345_678_901_234_567 + i,
      price: 15_000_000_000 + i * 100,
      quantity: 100_000 + i,
      side: rem(i, 2),
      timestamp: timestamp + i,
      flags: rem(i, 8)
    }
  end

batch_elixir_proto = Enum.map(batch_data, &struct!(Bench.ElixirProto.Order, &1))
batch_protobuf = Enum.map(batch_data, &struct!(Bench.Protobuf.Order, &1))

batch_json =
  Enum.map(batch_data, fn d ->
    %{
      "order_id" => Base.encode64(d.order_id),
      "user_id" => d.user_id,
      "price" => d.price,
      "quantity" => d.quantity,
      "side" => d.side,
      "timestamp" => d.timestamp,
      "flags" => d.flags
    }
  end)

# Pre-encode for decode benchmarks
grid_standard_bin = Bench.GridCodec.Order.encode(standard_data)
grid_sparse_bin = Bench.GridCodec.SparseOrder.encode(sparse_data)
grid_large_bin = Bench.GridCodec.LargeOrder.encode(large_data)

elixir_proto_standard_bin = Bench.ElixirProto.Converter.encode(elixir_proto_standard)
elixir_proto_sparse_bin = Bench.ElixirProto.Converter.encode(elixir_proto_sparse)
elixir_proto_large_bin = Bench.ElixirProto.Converter.encode(elixir_proto_large)

protobuf_standard_bin = Protobuf.encode(protobuf_standard)
protobuf_large_bin = Protobuf.encode(protobuf_large)

etf_standard_bin = Bench.ETF.encode(standard_data)
etf_large_bin = Bench.ETF.encode(large_data)

json_standard_bin = Bench.JSON.encode(standard_json)
json_large_bin = Bench.JSON.encode(large_json)

# ==============================================================================
# Binary Size Comparison
# ==============================================================================

IO.puts("╔══════════════════════════════════════════════════════════════════════════════╗")
IO.puts("║                           BINARY SIZE COMPARISON                             ║")
IO.puts("╠══════════════════════════════════════════════════════════════════════════════╣")

sizes = [
  {"Standard Order (7 fields)",
   [
     {"GridCodec", byte_size(grid_standard_bin)},
     {"ElixirProto", byte_size(elixir_proto_standard_bin)},
     {"Protobuf", byte_size(protobuf_standard_bin)},
     {"ETF", byte_size(etf_standard_bin)},
     {"JSON", byte_size(json_standard_bin)}
   ]},
  {"Sparse Order (5/13 fields)",
   [
     {"GridCodec", byte_size(grid_sparse_bin)},
     {"ElixirProto", byte_size(elixir_proto_sparse_bin)},
     {"ETF", byte_size(Bench.ETF.encode(sparse_data))},
     {"JSON", byte_size(Bench.JSON.encode(sparse_json))}
   ]},
  {"Large Order (20 fields)",
   [
     {"GridCodec", byte_size(grid_large_bin)},
     {"ElixirProto", byte_size(elixir_proto_large_bin)},
     {"Protobuf", byte_size(protobuf_large_bin)},
     {"ETF", byte_size(etf_large_bin)},
     {"JSON", byte_size(json_large_bin)}
   ]}
]

for {name, format_sizes} <- sizes do
  IO.puts("║                                                                               ║")
  IO.puts("║  #{String.pad_trailing(name, 73)}║")

  min_size = format_sizes |> Enum.map(&elem(&1, 1)) |> Enum.min()

  for {format, size} <- format_sizes do
    ratio = if min_size > 0, do: Float.round(size / min_size, 2), else: 1.0

    line =
      "║    #{String.pad_trailing(format, 12)} #{String.pad_leading(to_string(size), 5)} bytes  (#{ratio}x)"

    IO.puts(String.pad_trailing(line, 80) <> "║")
  end
end

IO.puts("╚══════════════════════════════════════════════════════════════════════════════╝")
IO.puts("")

# ==============================================================================
# Benchmark 1: Standard Order Encoding
# ==============================================================================

IO.puts("\n📤 BENCHMARK 1: STANDARD ORDER ENCODING (7 fields)\n")

Benchee.run(
  %{
    "GridCodec" => fn -> Bench.GridCodec.Order.encode(standard_data) end,
    "ElixirProto" => fn -> Bench.ElixirProto.Converter.encode(elixir_proto_standard) end,
    "Protobuf (struct→bin)" => fn -> Protobuf.encode(protobuf_standard) end,
    "Protobuf (map→struct→bin)" => fn ->
      Protobuf.encode(struct!(Bench.Protobuf.Order, standard_data))
    end,
    "ETF" => fn -> Bench.ETF.encode(standard_data) end,
    "ETF (compressed)" => fn -> Bench.ETF.encode_compressed(standard_data) end,
    "JSON (Jason)" => fn -> Bench.JSON.encode(standard_json) end,
    "JSON (OTP)" => fn -> Bench.OtpJSON.encode(standard_json) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

# ==============================================================================
# Benchmark 2: Standard Order Decoding
# ==============================================================================

IO.puts("\n📥 BENCHMARK 2: STANDARD ORDER DECODING (7 fields)\n")

Benchee.run(
  %{
    "GridCodec" => fn -> Bench.GridCodec.Order.decode(grid_standard_bin) end,
    "ElixirProto" => fn -> Bench.ElixirProto.Converter.decode(elixir_proto_standard_bin) end,
    "Protobuf" => fn -> Protobuf.decode(protobuf_standard_bin, Bench.Protobuf.Order) end,
    "ETF" => fn -> Bench.ETF.decode(etf_standard_bin) end,
    "JSON (Jason)" => fn -> Bench.JSON.decode(json_standard_bin) end,
    "JSON (OTP)" => fn -> Bench.OtpJSON.decode(json_standard_bin) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

# ==============================================================================
# Benchmark 3: Large Order Encoding (20 fields)
# ==============================================================================

IO.puts("\n📤 BENCHMARK 3: LARGE ORDER ENCODING (20 fields)\n")

Benchee.run(
  %{
    "GridCodec" => fn -> Bench.GridCodec.LargeOrder.encode(large_data) end,
    "ElixirProto" => fn -> Bench.ElixirProto.Converter.encode(elixir_proto_large) end,
    "Protobuf" => fn -> Protobuf.encode(protobuf_large) end,
    "ETF" => fn -> Bench.ETF.encode(large_data) end,
    "ETF (compressed)" => fn -> Bench.ETF.encode_compressed(large_data) end,
    "JSON (Jason)" => fn -> Bench.JSON.encode(large_json) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

# ==============================================================================
# Benchmark 4: Large Order Decoding (20 fields)
# ==============================================================================

IO.puts("\n📥 BENCHMARK 4: LARGE ORDER DECODING (20 fields)\n")

Benchee.run(
  %{
    "GridCodec" => fn -> Bench.GridCodec.LargeOrder.decode(grid_large_bin) end,
    "ElixirProto" => fn -> Bench.ElixirProto.Converter.decode(elixir_proto_large_bin) end,
    "Protobuf" => fn -> Protobuf.decode(protobuf_large_bin, Bench.Protobuf.LargeOrder) end,
    "ETF" => fn -> Bench.ETF.decode(etf_large_bin) end,
    "JSON (Jason)" => fn -> Bench.JSON.decode(json_large_bin) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

# ==============================================================================
# Benchmark 5: Sparse Order (tests nil handling)
# ==============================================================================

IO.puts("\n📤 BENCHMARK 5: SPARSE ORDER ENCODING (5/13 fields populated)\n")

Benchee.run(
  %{
    "GridCodec" => fn -> Bench.GridCodec.SparseOrder.encode(sparse_data) end,
    "ElixirProto" => fn -> Bench.ElixirProto.Converter.encode(elixir_proto_sparse) end,
    "ETF" => fn -> Bench.ETF.encode(sparse_data) end,
    "JSON (Jason)" => fn -> Bench.JSON.encode(sparse_json) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

# ==============================================================================
# Benchmark 6: Batch Encoding (100 messages)
# ==============================================================================

IO.puts("\n📦 BENCHMARK 6: BATCH ENCODING (100 messages)\n")

Benchee.run(
  %{
    "GridCodec" => fn ->
      Enum.map(batch_data, &Bench.GridCodec.Order.encode/1)
    end,
    "ElixirProto" => fn ->
      Enum.map(batch_elixir_proto, &Bench.ElixirProto.Converter.encode/1)
    end,
    "Protobuf" => fn ->
      Enum.map(batch_protobuf, &Protobuf.encode/1)
    end,
    "ETF" => fn ->
      Enum.map(batch_data, &Bench.ETF.encode/1)
    end,
    "JSON (Jason)" => fn ->
      Enum.map(batch_json, &Bench.JSON.encode/1)
    end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

# ==============================================================================
# Benchmark 7: Roundtrip (encode → decode → access field)
# ==============================================================================

IO.puts("\n🔄 BENCHMARK 7: ROUNDTRIP (encode → decode → access price field)\n")

Benchee.run(
  %{
    "GridCodec" => fn ->
      bin = Bench.GridCodec.Order.encode(standard_data)
      {:ok, decoded} = Bench.GridCodec.Order.decode(bin)
      decoded.price
    end,
    "GridCodec (zero-copy)" => fn ->
      bin = Bench.GridCodec.Order.encode(standard_data)
      env = Bench.GridCodec.Order.wrap(bin)
      Bench.GridCodec.Order.get(env, :price)
    end,
    "ElixirProto" => fn ->
      bin = Bench.ElixirProto.Converter.encode(elixir_proto_standard)
      decoded = Bench.ElixirProto.Converter.decode(bin)
      decoded.price
    end,
    "Protobuf" => fn ->
      bin = Protobuf.encode(protobuf_standard)
      decoded = Protobuf.decode(bin, Bench.Protobuf.Order)
      decoded.price
    end,
    "ETF" => fn ->
      bin = Bench.ETF.encode(standard_data)
      decoded = Bench.ETF.decode(bin)
      decoded.price
    end,
    "JSON (Jason)" => fn ->
      bin = Bench.JSON.encode(standard_json)
      decoded = Bench.JSON.decode(bin)
      decoded["price"]
    end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

# ==============================================================================
# Benchmark 8: Zero-Copy Field Access (GridCodec unique)
# ==============================================================================

IO.puts("\n🎯 BENCHMARK 8: FIELD ACCESS (pre-encoded binary → single field)\n")

grid_env = Bench.GridCodec.Order.wrap(grid_standard_bin)
grid_large_env = Bench.GridCodec.LargeOrder.wrap(grid_large_bin)

Benchee.run(
  %{
    "GridCodec zero-copy (7 fields)" => fn ->
      Bench.GridCodec.Order.get(grid_env, :price)
    end,
    "GridCodec zero-copy (20 fields)" => fn ->
      Bench.GridCodec.LargeOrder.get(grid_large_env, :price)
    end,
    "GridCodec full decode (7 fields)" => fn ->
      {:ok, decoded} = Bench.GridCodec.Order.decode(grid_standard_bin)
      decoded.price
    end,
    "GridCodec full decode (20 fields)" => fn ->
      {:ok, decoded} = Bench.GridCodec.LargeOrder.decode(grid_large_bin)
      decoded.price
    end,
    "ElixirProto decode (7 fields)" => fn ->
      decoded = Bench.ElixirProto.Converter.decode(elixir_proto_standard_bin)
      decoded.price
    end,
    "ETF decode (7 fields)" => fn ->
      decoded = Bench.ETF.decode(etf_standard_bin)
      decoded.price
    end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)

IO.puts("\n✅ Benchmarks completed.\n")
