# Encode/Decode Benchmark
#
# Compares GridCodec with Jason, OTP JSON, MessagePack (msgpax), and ETF
#
# Run with: mix run benchmarks/encode_decode_benchmark.exs
#
# Results saved to: artifacts/benchmarks/
#
# What this measures:
# - Encoding speed (map -> binary)
# - Decoding speed (binary -> map)
# - Binary size (wire format efficiency)
# - Zero-copy field access (GridCodec only)

# ==============================================================================
# Test Data Setup
# ==============================================================================

# Define the GridCodec codec
defmodule BenchmarkCodecs.OrderEvent do
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

# For JSON and MessagePack, we'll use helper modules
defmodule BenchmarkCodecs.JsonOrder do
  def encode(data) do
    Jason.encode!(data)
  end

  def decode(binary) do
    Jason.decode!(binary)
  end
end

# OTP 27+ native JSON (uses :json module from stdlib)
defmodule BenchmarkCodecs.OtpJsonOrder do
  @moduledoc """
  Uses the native :json module from OTP 27+ stdlib.
  This is a NIF-based JSON encoder/decoder.
  """

  def encode(data) do
    :json.encode(data) |> IO.iodata_to_binary()
  end

  def decode(binary) do
    :json.decode(binary)
  end
end

defmodule BenchmarkCodecs.MsgpackOrder do
  def encode(data) do
    # Msgpax expects certain types
    data_for_msgpack =
      data
      |> Map.update(:order_id, nil, fn
        nil -> nil
        uuid -> Base.encode64(uuid)
      end)
      |> Map.update(:timestamp, nil, &(&1 || 0))

    # Msgpax.pack! returns an iolist, convert to binary
    Msgpax.pack!(data_for_msgpack) |> IO.iodata_to_binary()
  end

  def decode(binary) do
    Msgpax.unpack!(binary)
  end
end

# ETF (Erlang Term Format) - BEAM's native serialization
defmodule BenchmarkCodecs.EtfOrder do
  @moduledoc """
  Uses :erlang.term_to_binary/1 and :erlang.binary_to_term/1.
  This is the BEAM's native serialization format, extremely well optimized.
  """

  def encode(data) do
    :erlang.term_to_binary(data)
  end

  def encode_compressed(data) do
    :erlang.term_to_binary(data, [:compressed])
  end

  def decode(binary) do
    :erlang.binary_to_term(binary)
  end
end

# Protobuf - Pure Elixir implementation (no protoc required)
defmodule BenchmarkCodecs.ProtobufOrder do
  @moduledoc """
  Uses the pure Elixir `protobuf` library from hex.pm/packages/protobuf.
  No external protoc compiler required.
  """
  use Protobuf, syntax: :proto3

  # Define fields matching our test data
  # Note: Protobuf doesn't have native UUID, so we use bytes
  field(:order_id, 1, type: :bytes)
  field(:user_id, 2, type: :uint64)
  field(:price, 3, type: :uint64)
  field(:quantity, 4, type: :uint32)
  field(:side, 5, type: :uint32)
  field(:timestamp, 6, type: :int64)
  field(:flags, 7, type: :uint32)
end

defmodule BenchmarkCodecs.ProtobufHelper do
  @moduledoc false

  def from_map(data) do
    struct!(BenchmarkCodecs.ProtobufOrder, data)
  end
end

# ==============================================================================
# Test Data
# ==============================================================================

IO.puts("Setting up test data...")

# Generate test data
order_id = :crypto.strong_rand_bytes(16)

sample_data = %{
  order_id: order_id,
  user_id: 12_345_678_901_234_567,
  price: 15_000_000_000,
  quantity: 100_000,
  side: 1,
  timestamp: System.system_time(:microsecond),
  flags: 7
}

# For JSON, we need string keys and Base64 UUID
sample_data_json = %{
  "order_id" => Base.encode64(order_id),
  "user_id" => 12_345_678_901_234_567,
  "price" => 15_000_000_000,
  "quantity" => 100_000,
  "side" => 1,
  "timestamp" => System.system_time(:microsecond),
  "flags" => 7
}

# Pre-encode for decode benchmarks
grid_binary = BenchmarkCodecs.OrderEvent.encode(sample_data)
json_binary = BenchmarkCodecs.JsonOrder.encode(sample_data_json)
otp_json_binary = BenchmarkCodecs.OtpJsonOrder.encode(sample_data_json)
msgpack_binary = BenchmarkCodecs.MsgpackOrder.encode(sample_data)
etf_binary = BenchmarkCodecs.EtfOrder.encode(sample_data)
etf_compressed = BenchmarkCodecs.EtfOrder.encode_compressed(sample_data)
protobuf_struct = BenchmarkCodecs.ProtobufHelper.from_map(sample_data)
protobuf_binary = Protobuf.encode(protobuf_struct)

IO.puts("")
IO.puts("╔══════════════════════════════════════════════════════════════════════════════╗")
IO.puts("║                              BINARY SIZES                                      ║")
IO.puts("╠══════════════════════════════════════════════════════════════════════════════╣")
IO.puts("║  Format          │ Size (bytes) │ vs GridCodec                                ║")
IO.puts("╠══════════════════════════════════════════════════════════════════════════════╣")

grid_size = byte_size(grid_binary)
json_size = byte_size(json_binary)
otp_json_size = byte_size(otp_json_binary)
msgpack_size = byte_size(msgpack_binary)
etf_size = byte_size(etf_binary)
etf_comp_size = byte_size(etf_compressed)
protobuf_size = byte_size(protobuf_binary)

IO.puts(
  "║  GridCodec       │ #{String.pad_leading(to_string(grid_size), 5)} bytes │ baseline                                     ║"
)

IO.puts(
  "║  Protobuf        │ #{String.pad_leading(to_string(protobuf_size), 5)} bytes │ #{Float.round(protobuf_size / grid_size, 2)}x                                        ║"
)

IO.puts(
  "║  ETF             │ #{String.pad_leading(to_string(etf_size), 5)} bytes │ #{Float.round(etf_size / grid_size, 2)}x                                        ║"
)

IO.puts(
  "║  ETF (compress)  │ #{String.pad_leading(to_string(etf_comp_size), 5)} bytes │ #{Float.round(etf_comp_size / grid_size, 2)}x                                        ║"
)

IO.puts(
  "║  MessagePack     │ #{String.pad_leading(to_string(msgpack_size), 5)} bytes │ #{Float.round(msgpack_size / grid_size, 2)}x                                        ║"
)

IO.puts(
  "║  JSON (Jason)    │ #{String.pad_leading(to_string(json_size), 5)} bytes │ #{Float.round(json_size / grid_size, 2)}x                                        ║"
)

IO.puts(
  "║  JSON (OTP)      │ #{String.pad_leading(to_string(otp_json_size), 5)} bytes │ #{Float.round(otp_json_size / grid_size, 2)}x                                        ║"
)

IO.puts("╚══════════════════════════════════════════════════════════════════════════════╝")
IO.puts("")

# ==============================================================================
# Encoding Benchmark (Map → Binary) - FAIR COMPARISON
# ==============================================================================
# All methods start from a map and produce a binary.
# This ensures we're comparing the full encode path.

IO.puts("Running encoding benchmark (map → binary)...\n")

Benchee.run(
  %{
    "GridCodec (map→bin)" => fn -> BenchmarkCodecs.OrderEvent.encode(sample_data) end,
    # Protobuf: include struct creation for fair comparison
    "Protobuf (map→struct→bin)" => fn ->
      struct = struct!(BenchmarkCodecs.ProtobufOrder, sample_data)
      Protobuf.encode(struct)
    end,
    "ETF (map→bin)" => fn -> BenchmarkCodecs.EtfOrder.encode(sample_data) end,
    "ETF compressed (map→bin)" => fn ->
      BenchmarkCodecs.EtfOrder.encode_compressed(sample_data)
    end,
    "JSON Jason (map→bin)" => fn -> BenchmarkCodecs.JsonOrder.encode(sample_data_json) end,
    "JSON OTP (map→bin)" => fn -> BenchmarkCodecs.OtpJsonOrder.encode(sample_data_json) end,
    "MessagePack (map→bin)" => fn -> BenchmarkCodecs.MsgpackOrder.encode(sample_data) end
  },
  title: "📤 ENCODING (map → binary)",
  memory_time: 2,
  time: 5,
  warmup: 1,
  formatters: [
    Benchee.Formatters.Console
  ],
  print: [fast_warning: false]
)

# Also show Protobuf struct-only encode for reference
IO.puts("\n📝 Note: Protobuf struct→binary only (if you already have a struct):\n")

Benchee.run(
  %{
    "Protobuf (struct→bin only)" => fn -> Protobuf.encode(protobuf_struct) end
  },
  title: "Protobuf struct-only encode",
  memory_time: 1,
  time: 2,
  warmup: 0.5,
  formatters: [
    Benchee.Formatters.Console
  ],
  print: [fast_warning: false]
)

IO.puts("\n")

# ==============================================================================
# Decoding Benchmark (Binary → Map) - FAIR COMPARISON
# ==============================================================================
# All methods produce a map as output.
# Note: GridCodec returns {:ok, map}, others return map directly.
# We show both variants for GridCodec.

IO.puts("Running decoding benchmark (binary → map)...\n")

Benchee.run(
  %{
    # GridCodec returns {:ok, map} - include unwrap for fair comparison
    "GridCodec (bin→{:ok,map})" => fn -> BenchmarkCodecs.OrderEvent.decode(grid_binary) end,
    "GridCodec (bin→map unwrap)" => fn ->
      {:ok, map} = BenchmarkCodecs.OrderEvent.decode(grid_binary)
      map
    end,
    # Protobuf returns struct - convert to map for fair comparison
    "Protobuf (bin→struct→map)" => fn ->
      struct = Protobuf.decode(protobuf_binary, BenchmarkCodecs.ProtobufOrder)
      Map.from_struct(struct)
    end,
    "Protobuf (bin→struct only)" => fn ->
      Protobuf.decode(protobuf_binary, BenchmarkCodecs.ProtobufOrder)
    end,
    "ETF (bin→map)" => fn -> BenchmarkCodecs.EtfOrder.decode(etf_binary) end,
    "JSON Jason (bin→map)" => fn -> BenchmarkCodecs.JsonOrder.decode(json_binary) end,
    "JSON OTP (bin→map)" => fn -> BenchmarkCodecs.OtpJsonOrder.decode(otp_json_binary) end,
    "MessagePack (bin→map)" => fn -> BenchmarkCodecs.MsgpackOrder.decode(msgpack_binary) end
  },
  title: "📥 DECODING (binary → map)",
  memory_time: 2,
  time: 5,
  warmup: 1,
  formatters: [
    Benchee.Formatters.Console
  ],
  print: [fast_warning: false]
)

IO.puts("\n")

# ==============================================================================
# Zero-Copy Field Access Benchmark
# ==============================================================================

IO.puts("Running field access benchmark...\n")

# Pre-wrap for zero-copy access
env = BenchmarkCodecs.OrderEvent.wrap(grid_binary)

Benchee.run(
  %{
    # GridCodec zero-copy: just extract one field from wrapped binary
    "GridCodec zero-copy get" => fn ->
      BenchmarkCodecs.OrderEvent.get(env, :price)
    end,
    # Full decode path for each format, then access the field
    "GridCodec decode+access" => fn ->
      {:ok, decoded} = BenchmarkCodecs.OrderEvent.decode(grid_binary)
      decoded.price
    end,
    "Protobuf decode+access" => fn ->
      decoded = Protobuf.decode(protobuf_binary, BenchmarkCodecs.ProtobufOrder)
      decoded.price
    end,
    "ETF decode+access" => fn ->
      decoded = BenchmarkCodecs.EtfOrder.decode(etf_binary)
      decoded.price
    end,
    "JSON Jason decode+access" => fn ->
      decoded = BenchmarkCodecs.JsonOrder.decode(json_binary)
      decoded["price"]
    end,
    "JSON OTP decode+access" => fn ->
      decoded = BenchmarkCodecs.OtpJsonOrder.decode(otp_json_binary)
      decoded["price"]
    end,
    "MessagePack decode+access" => fn ->
      decoded = BenchmarkCodecs.MsgpackOrder.decode(msgpack_binary)
      decoded["price"]
    end
  },
  title: "🎯 SINGLE FIELD ACCESS (decode + get one field)",
  memory_time: 2,
  time: 5,
  warmup: 1,
  formatters: [
    Benchee.Formatters.Console
  ],
  print: [fast_warning: false]
)

# ==============================================================================
# Summary
# ==============================================================================

IO.puts("")
IO.puts("╔══════════════════════════════════════════════════════════════════════════════╗")
IO.puts("║                              SUMMARY                                          ║")
IO.puts("╠══════════════════════════════════════════════════════════════════════════════╣")
IO.puts("║  GridCodec provides:                                                          ║")
IO.puts("║    • O(1) zero-copy field access via wrap/get                                 ║")

IO.puts(
  "║    • Compact binary format (#{String.pad_leading(to_string(grid_size), 2)} bytes)                                     ║"
)

IO.puts("║    • Compile-time generated encode/decode                                     ║")
IO.puts("║    • BEAM sub-binary sharing for fan-out                                      ║")
IO.puts("║    • No external dependencies for core functionality                          ║")
IO.puts("╚══════════════════════════════════════════════════════════════════════════════╝")

# Save results to artifacts folder
timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0, 15)
output_file = "artifacts/benchmarks/encode_decode_#{timestamp}.md"
File.mkdir_p!("artifacts/benchmarks")

summary = """
# GridCodec Encode/Decode Benchmark Results

Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}

## Binary Sizes

| Format | Size (bytes) | vs GridCodec |
|--------|-------------|--------------|
| GridCodec | #{grid_size} | baseline |
| Protobuf | #{protobuf_size} | #{Float.round(protobuf_size / grid_size, 2)}x |
| ETF | #{etf_size} | #{Float.round(etf_size / grid_size, 2)}x |
| ETF (compressed) | #{etf_comp_size} | #{Float.round(etf_comp_size / grid_size, 2)}x |
| MessagePack | #{msgpack_size} | #{Float.round(msgpack_size / grid_size, 2)}x |
| JSON (Jason) | #{json_size} | #{Float.round(json_size / grid_size, 2)}x |
| JSON (OTP) | #{otp_json_size} | #{Float.round(otp_json_size / grid_size, 2)}x |

## Key Findings

GridCodec provides:
- Compact binary format (#{grid_size} bytes vs #{json_size} bytes JSON)
- O(1) zero-copy field access via wrap/get
- Compile-time generated encode/decode
- BEAM sub-binary sharing for fan-out
"""

File.write!(output_file, summary)
IO.puts("\nResults saved to: #{output_file}")
