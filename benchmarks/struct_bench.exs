# GridCodec.Struct Performance Benchmark
#
# Run with: mix run benchmarks/struct_bench.exs

defmodule Bench.StructPerf do
  @moduledoc """
  Performance verification for GridCodec.Struct vs hand-rolled code.

  Compares:
  1. Hand-rolled code (manual binary construction) - baseline
  2. GridCodec.Struct (struct-based codec)
  3. GridCodec.encode/decode (with dispatch)

  ## Expected Results (v0.6.0)

  ### Encode Performance

  | Implementation             | Time     | vs Hand-rolled |
  |----------------------------|----------|----------------|
  | Hand-rolled                | ~70ns    | baseline       |
  | StructCodec (no header)    | ~75ns    | ~same (1.1x)   |
  | StructCodec (w/header)     | ~280ns   | 4x slower      |
  | GridCodec.encode           | ~400ns   | 5.8x slower    |

  ### Decode Performance

  | Implementation             | Time     | vs Hand-rolled |
  |----------------------------|----------|----------------|
  | Hand-rolled                | ~93ns    | baseline       |
  | StructCodec (no header)    | ~78ns    | 1.2x FASTER    |
  | StructCodec (w/header)     | ~127ns   | 1.4x slower    |
  | GridCodec.decode           | ~156ns   | 1.7x slower    |

  ### Zero-Copy Get

  | Implementation             | Time     | vs Hand-rolled |
  |----------------------------|----------|----------------|
  | Hand-rolled get_price      | ~22ns    | baseline       |
  | StructCodec.get (no hdr)   | ~14ns    | 1.6x FASTER    |
  | StructCodec.get (w/header) | ~15ns    | 1.4x FASTER    |

  ### Dispatch Overhead

  | Operation | Overhead |
  |-----------|----------|
  | Encode    | ~140ns (63%) |
  | Decode    | ~11ns (6%)   |

  ## Key Findings

  1. **Payload-only operations** match or beat hand-rolled code
  2. **Header adds overhead** for encode (~250ns)
  3. **get macro is fastest** - inline pattern matching
  4. **Decode dispatch is efficient** (~6% overhead)

  ## Pass Criteria

  Struct codec should be within 15% of hand-rolled for:
  - Encode (payload-only)
  - Decode (payload-only)

  ## Usage

      mix run benchmarks/struct_bench.exs
  """
end

# ============================================================================
# Hand-rolled implementation (baseline)
# ============================================================================
defmodule Bench.HandRolled do
  @null_u64 18_446_744_073_709_551_615
  @null_u32 4_294_967_295

  defstruct [:id, :price, :quantity]

  def encode(%__MODULE__{id: id, price: price, quantity: quantity}) do
    id_val = id || @null_u64
    price_val = price || @null_u64
    qty_val = quantity || @null_u32

    <<id_val::little-64, price_val::little-64, qty_val::little-32>>
  end

  def decode(<<id::little-64, price::little-64, quantity::little-32>>) do
    {:ok, %__MODULE__{
      id: if(id == @null_u64, do: nil, else: id),
      price: if(price == @null_u64, do: nil, else: price),
      quantity: if(quantity == @null_u32, do: nil, else: quantity)
    }}
  end

  def get_price(<<_::64, price::little-64, _::binary>>) do
    if price == @null_u64, do: nil, else: price
  end
end

# ============================================================================
# GridCodec.Struct (struct-based)
# ============================================================================
defmodule Bench.StructCodec do
  use GridCodec.Struct, template_id: 1, schema_id: 100

  defcodec do
    field :id, :u64
    field :price, :u64
    field :quantity, :u32
  end
end

# ============================================================================
# Benchmark helpers
# ============================================================================
defmodule Bench.Runner do
  def run(name, iterations, fun) do
    # Warmup
    for _ <- 1..1000, do: fun.()

    {time, _} = :timer.tc(fn ->
      for _ <- 1..iterations, do: fun.()
    end)

    ns_per_op = time / iterations * 1000
    ops_per_sec = iterations / time * 1_000_000

    {name, ns_per_op, ops_per_sec}
  end

  def print_results(results) do
    # Find baseline (hand-rolled)
    {_, baseline_ns, _} = Enum.find(results, fn {name, _, _} -> String.contains?(name, "Hand") end)

    IO.puts("")
    IO.puts(String.pad_trailing("Implementation", 35) <>
            String.pad_leading("ns/op", 12) <>
            String.pad_leading("ops/sec", 15) <>
            String.pad_leading("vs Hand", 12))
    IO.puts(String.duplicate("-", 74))

    for {name, ns, ops} <- results do
      ratio = ns / baseline_ns
      ratio_str = if ratio > 1.0, do: "#{Float.round(ratio, 2)}x slower", else: "#{Float.round(1/ratio, 2)}x faster"
      ratio_str = if abs(ratio - 1.0) < 0.05, do: "~same", else: ratio_str

      IO.puts(
        String.pad_trailing(name, 35) <>
        String.pad_leading("#{Float.round(ns, 1)}", 12) <>
        String.pad_leading("#{trunc(ops)}", 15) <>
        String.pad_leading(ratio_str, 12)
      )
    end
  end
end

# ============================================================================
# Main benchmark
# ============================================================================
defmodule Bench.Main do
  alias Bench.{HandRolled, StructCodec, Runner}

  require StructCodec

  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("GridCodec.Struct Performance Verification")
    IO.puts(String.duplicate("=", 70))

    # Test data
    hand_data = %HandRolled{id: 12_345_678_901_234, price: 15_000_000_000, quantity: 100_000}
    struct_data = %StructCodec{id: 12_345_678_901_234, price: 15_000_000_000, quantity: 100_000}

    # Pre-encode for decode benchmarks
    hand_binary = HandRolled.encode(hand_data)
    # encode(struct, header: false) for payload-only (comparable to hand-rolled)
    struct_binary = StructCodec.encode(struct_data, header: false)
    # encode(struct) now includes header by default
    struct_framed = StructCodec.encode(struct_data)

    # Verify correctness
    IO.puts("\n--- Verification ---")
    IO.puts("Hand-rolled binary size: #{byte_size(hand_binary)} bytes")
    IO.puts("Struct codec binary size: #{byte_size(struct_binary)} bytes (payload only)")
    IO.puts("Struct codec framed size: #{byte_size(struct_framed)} bytes (with header)")
    IO.puts("Payload binaries match: #{hand_binary == struct_binary}")

    {:ok, hand_decoded} = HandRolled.decode(hand_binary)
    {:ok, struct_decoded} = StructCodec.decode(struct_binary, header: false)

    IO.puts("Hand decode:   #{inspect(hand_decoded)}")
    IO.puts("Struct decode: #{inspect(struct_decoded)}")

    iterations = 500_000

    # ENCODE Benchmarks
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("ENCODE Benchmark (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 70))

    encode_results = [
      Runner.run("Hand-rolled encode", iterations, fn ->
        HandRolled.encode(hand_data)
      end),
      Runner.run("StructCodec.encode (no header)", iterations, fn ->
        StructCodec.encode(struct_data, header: false)
      end),
      Runner.run("StructCodec.encode (w/header)", iterations, fn ->
        StructCodec.encode(struct_data)
      end),
      Runner.run("GridCodec.encode (dispatch)", iterations, fn ->
        GridCodec.encode(struct_data)
      end)
    ]

    Runner.print_results(encode_results)

    # DECODE Benchmarks
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("DECODE Benchmark (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 70))

    decode_results = [
      Runner.run("Hand-rolled decode", iterations, fn ->
        HandRolled.decode(hand_binary)
      end),
      Runner.run("StructCodec.decode (no header)", iterations, fn ->
        StructCodec.decode(struct_binary, header: false)
      end),
      Runner.run("StructCodec.decode (w/header)", iterations, fn ->
        StructCodec.decode(struct_framed)
      end),
      Runner.run("GridCodec.decode (dispatch)", iterations, fn ->
        GridCodec.decode(struct_framed)
      end)
    ]

    Runner.print_results(decode_results)

    # ZERO-COPY GET Benchmarks (get/2 macro works directly on binary)
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("ZERO-COPY GET Benchmark (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 70))

    get_results = [
      Runner.run("Hand-rolled get_price", iterations, fn ->
        HandRolled.get_price(hand_binary)
      end),
      Runner.run("StructCodec.get (no header)", iterations, fn ->
        StructCodec.get(struct_binary, :price, header: false)
      end),
      Runner.run("StructCodec.get (w/header)", iterations, fn ->
        StructCodec.get(struct_framed, :price)
      end)
    ]

    Runner.print_results(get_results)

    # DISPATCH OVERHEAD
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("DISPATCH OVERHEAD Analysis")
    IO.puts(String.duplicate("=", 70))

    direct_encode = Runner.run("Direct encode (w/header)", iterations, fn -> StructCodec.encode(struct_data) end)
    dispatch_encode = Runner.run("Dispatch encode", iterations, fn -> GridCodec.encode(struct_data) end)

    {_, direct_ns, _} = direct_encode
    {_, dispatch_ns, _} = dispatch_encode
    overhead_encode = dispatch_ns - direct_ns

    IO.puts("\nEncode dispatch overhead: #{Float.round(overhead_encode, 1)} ns (#{Float.round(overhead_encode / direct_ns * 100, 1)}%)")

    direct_decode = Runner.run("Direct decode (w/header)", iterations, fn -> StructCodec.decode(struct_framed) end)
    dispatch_decode = Runner.run("Dispatch decode", iterations, fn -> GridCodec.decode(struct_framed) end)

    {_, direct_dec_ns, _} = direct_decode
    {_, dispatch_dec_ns, _} = dispatch_decode
    overhead_decode = dispatch_dec_ns - direct_dec_ns

    IO.puts("Decode dispatch overhead: #{Float.round(overhead_decode, 1)} ns (#{Float.round(overhead_decode / direct_dec_ns * 100, 1)}%)")

    # SUMMARY
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("SUMMARY")
    IO.puts(String.duplicate("=", 70))

    {_, hand_enc_ns, _} = Enum.find(encode_results, fn {n, _, _} -> String.contains?(n, "Hand") end)
    {_, struct_enc_ns, _} = Enum.find(encode_results, fn {n, _, _} -> String.contains?(n, "StructCodec.encode (no header)") end)
    {_, hand_dec_ns, _} = Enum.find(decode_results, fn {n, _, _} -> String.contains?(n, "Hand") end)
    {_, struct_dec_ns, _} = Enum.find(decode_results, fn {n, _, _} -> String.contains?(n, "StructCodec.decode (no header)") end)

    enc_ratio = struct_enc_ns / hand_enc_ns
    dec_ratio = struct_dec_ns / hand_dec_ns

    IO.puts("")
    IO.puts("Struct encode vs Hand-rolled: #{Float.round(enc_ratio, 2)}x")
    IO.puts("Struct decode vs Hand-rolled: #{Float.round(dec_ratio, 2)}x")

    threshold = 1.15  # Allow 15% overhead max

    if enc_ratio < threshold and dec_ratio < threshold do
      IO.puts("\n✓ PASS: Generated code is within #{trunc((threshold - 1) * 100)}% of hand-rolled performance")
    else
      IO.puts("\n✗ WARN: Generated code exceeds #{trunc((threshold - 1) * 100)}% overhead threshold")
      if enc_ratio >= threshold, do: IO.puts("  - Encode: #{Float.round((enc_ratio - 1) * 100, 1)}% slower")
      if dec_ratio >= threshold, do: IO.puts("  - Decode: #{Float.round((dec_ratio - 1) * 100, 1)}% slower")
    end

    IO.puts("")
  end
end

Bench.Main.run()
