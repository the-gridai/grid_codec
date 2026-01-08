# Comprehensive GridCodec Performance Benchmark
#
# Run with: mix run benchmarks/comprehensive_bench.exs

defmodule Bench.Comprehensive do
  @moduledoc """
  Comprehensive performance analysis of GridCodec.Struct.

  Tests various codec configurations:
  - Fixed-only fields (most optimized path)
  - Fixed + variable-length fields
  - Multiple field types
  - Dispatch overhead

  ## Expected Results (v0.6.0)

  ### Encode Performance

  | Implementation          | Time       | vs Hand-rolled |
  |-------------------------|------------|----------------|
  | Hand-rolled             | ~70ns      | baseline       |
  | SimpleFixed (no header) | ~70ns      | ~same          |
  | MultiType (6 fields)    | ~70ns      | ~same          |
  | WithString (var-length) | ~300-350ns | 4-5x slower    |
  | SimpleFixed (w/header)  | ~300-350ns | 4-5x slower    |
  | GridCodec.encode        | ~300-400ns | 4-5x slower    |

  ### Decode Performance

  | Implementation          | Time       | vs Hand-rolled |
  |-------------------------|------------|----------------|
  | Hand-rolled             | ~100ns     | baseline       |
  | SimpleFixed (no header) | ~110ns     | ~same          |
  | MultiType (6 fields)    | ~190ns     | 1.9x slower    |
  | WithString (var-length) | ~400ns     | 4x slower      |
  | SimpleFixed (w/header)  | ~180ns     | 1.8x slower    |
  | GridCodec.decode        | ~250ns     | 2.5x slower    |

  ### Zero-Copy Get

  | Operation               | Time       |
  |-------------------------|------------|
  | get(:price) w/header    | ~70-130ns  |
  | get(:price) no header   | ~130ns     |

  ### Dispatch Overhead

  | Path     | Encode    | Decode    |
  |----------|-----------|-----------|
  | Direct   | ~300ns    | ~170ns    |
  | Protocol | ~400ns    | ~220ns    |
  | Overhead | ~10-30%   | ~30%      |

  ## Key Findings

  1. **Payload-only encode** matches hand-rolled performance
  2. **Header adds overhead** (~250ns for 8-byte header)
  3. **Variable-length fields** add significant overhead
  4. **get macro** is 2-10x faster than full decode

  ## Usage

      mix run benchmarks/comprehensive_bench.exs
  """
end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("GridCodec Comprehensive Performance Benchmark")
IO.puts(String.duplicate("=", 80))

# ============================================================================
# Test Codecs
# ============================================================================

# Simple fixed-only codec
defmodule Bench.SimpleFixed do
  use GridCodec.Struct, template_id: 1, schema_id: 1

  defcodec do
    field :id, :u64
    field :price, :u64
    field :quantity, :u32
  end
end

# Multiple field types
defmodule Bench.MultiType do
  use GridCodec.Struct, template_id: 2, schema_id: 1

  defcodec do
    field :id, :u64
    field :active, :bool
    field :price, :f64
    field :count, :i32
    field :flags, :u8
    field :balance, :i64
  end
end

# With variable-length string
defmodule Bench.WithString do
  use GridCodec.Struct, template_id: 3, schema_id: 1

  defcodec do
    field :id, :u64
    field :price, :u64
    field :name, :string16
  end
end

# Hand-rolled baseline for comparison
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
end

# ============================================================================
# Benchmark Runner
# ============================================================================
defmodule Bench.Runner do
  def run(name, iterations, fun) do
    # Warmup
    for _ <- 1..1000, do: fun.()

    # GC before measurement
    :erlang.garbage_collect()

    {time, _} = :timer.tc(fn ->
      for _ <- 1..iterations, do: fun.()
    end)

    ns_per_op = time / iterations * 1000
    ops_per_sec = iterations / time * 1_000_000

    {name, ns_per_op, ops_per_sec}
  end

  def print_results(results, baseline_name \\ "Hand-rolled") do
    baseline =
      Enum.find(results, fn {name, _, _} -> String.contains?(name, baseline_name) end)

    baseline_ns = if baseline, do: elem(baseline, 1), else: elem(hd(results), 1)

    IO.puts("")
    IO.puts(String.pad_trailing("Implementation", 40) <>
            String.pad_leading("ns/op", 12) <>
            String.pad_leading("ops/sec", 15) <>
            String.pad_leading("vs Baseline", 14))
    IO.puts(String.duplicate("-", 81))

    for {name, ns, ops} <- results do
      ratio = ns / baseline_ns
      ratio_str = cond do
        abs(ratio - 1.0) < 0.05 -> "~same"
        ratio < 1.0 -> "#{Float.round(1/ratio, 2)}x faster"
        true -> "#{Float.round(ratio, 2)}x slower"
      end

      IO.puts(
        String.pad_trailing(name, 40) <>
        String.pad_leading("#{Float.round(ns, 1)}", 12) <>
        String.pad_leading("#{trunc(ops)}", 15) <>
        String.pad_leading(ratio_str, 14)
      )
    end
  end
end

# ============================================================================
# Main Benchmark
# ============================================================================
defmodule Bench.Main do
  alias Bench.{SimpleFixed, MultiType, WithString, HandRolled, Runner}

  require SimpleFixed
  require MultiType

  def run do
    iterations = 500_000

    # Test data
    simple_data = %SimpleFixed{id: 12_345_678_901_234, price: 15_000_000_000, quantity: 100_000}
    multi_data = %MultiType{
      id: 12_345_678_901_234,
      active: true,
      price: 123.456,
      count: -1000,
      flags: 255,
      balance: -9_000_000_000
    }
    string_data = %WithString{id: 12_345_678_901_234, price: 15_000_000_000, name: "Test Order"}
    hand_data = %HandRolled{id: 12_345_678_901_234, price: 15_000_000_000, quantity: 100_000}

    # Pre-encode (encode/1 includes header by default)
    simple_bin = SimpleFixed.encode(simple_data)
    multi_bin = MultiType.encode(multi_data)
    string_bin = WithString.encode(string_data)
    hand_bin = HandRolled.encode(hand_data)

    # Payload-only (no header) for comparison
    simple_bin_no_header = SimpleFixed.encode(simple_data, header: false)
    multi_bin_no_header = MultiType.encode(multi_data, header: false)

    # Verify
    IO.puts("\n--- Verification ---")
    {:ok, d1} = SimpleFixed.decode(simple_bin)
    {:ok, d2} = MultiType.decode(multi_bin)
    {:ok, d3} = WithString.decode(string_bin)
    IO.puts("SimpleFixed roundtrip: #{d1 == simple_data}")
    IO.puts("MultiType roundtrip: #{d2 == multi_data}")
    IO.puts("WithString roundtrip: #{d3 == string_data}")
    IO.puts("Binary sizes: SimpleFixed=#{byte_size(simple_bin)}, MultiType=#{byte_size(multi_bin)}, WithString=#{byte_size(string_bin)}")

    # ========================================================================
    # ENCODE BENCHMARKS
    # ========================================================================
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("ENCODE Benchmarks (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 80))

    encode_results = [
      Runner.run("Hand-rolled (baseline)", iterations, fn -> HandRolled.encode(hand_data) end),
      Runner.run("SimpleFixed.encode (no header)", iterations, fn -> SimpleFixed.encode(simple_data, header: false) end),
      Runner.run("MultiType.encode (6 fields, no hdr)", iterations, fn -> MultiType.encode(multi_data, header: false) end),
      Runner.run("WithString.encode (var-length)", iterations, fn -> WithString.encode(string_data, header: false) end),
      Runner.run("SimpleFixed.encode (w/header)", iterations, fn -> SimpleFixed.encode(simple_data) end),
      Runner.run("GridCodec.encode (dispatch)", iterations, fn -> GridCodec.encode(simple_data) end)
    ]

    Runner.print_results(encode_results)

    # ========================================================================
    # DECODE BENCHMARKS
    # ========================================================================
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("DECODE Benchmarks (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 80))

    decode_results = [
      Runner.run("Hand-rolled (baseline)", iterations, fn -> HandRolled.decode(hand_bin) end),
      Runner.run("SimpleFixed.decode (no header)", iterations, fn -> SimpleFixed.decode(simple_bin_no_header, header: false) end),
      Runner.run("MultiType.decode (6 fields, no hdr)", iterations, fn -> MultiType.decode(multi_bin_no_header, header: false) end),
      Runner.run("WithString.decode (var-length)", iterations, fn -> WithString.decode(string_bin) end),
      Runner.run("SimpleFixed.decode (w/header)", iterations, fn -> SimpleFixed.decode(simple_bin) end),
      Runner.run("GridCodec.decode (dispatch)", iterations, fn -> GridCodec.decode(simple_bin) end)
    ]

    Runner.print_results(decode_results)

    # ========================================================================
    # ZERO-COPY GET BENCHMARKS (using get/2 macro directly on binary)
    # ========================================================================
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("ZERO-COPY GET Benchmarks (#{iterations} iterations)")
    IO.puts(String.duplicate("=", 80))

    get_results = [
      # get/2 macro works directly on binary (with header by default)
      Runner.run("SimpleFixed.get(:price) [w/header]", iterations, fn -> SimpleFixed.get(simple_bin, :price) end),
      Runner.run("MultiType.get(:price) [w/header]", iterations, fn -> MultiType.get(multi_bin, :price) end),
      Runner.run("MultiType.get(:balance) [w/header]", iterations, fn -> MultiType.get(multi_bin, :balance) end),
      Runner.run("MultiType.get(:active) [w/header]", iterations, fn -> MultiType.get(multi_bin, :active) end),
      # With header: false for payload-only binaries
      Runner.run("SimpleFixed.get(:price) [no header]", iterations, fn -> SimpleFixed.get(simple_bin_no_header, :price, header: false) end)
    ]

    Runner.print_results(get_results, "SimpleFixed.get(:price) [w/header]")

    # ========================================================================
    # DISPATCH ANALYSIS
    # ========================================================================
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Protocol/Dispatch Analysis")
    IO.puts(String.duplicate("=", 80))

    direct_enc = Runner.run("Direct encode (w/header)", iterations, fn -> SimpleFixed.encode(simple_data) end)
    protocol_enc = Runner.run("Protocol encode", iterations, fn -> GridCodec.encode(simple_data) end)

    direct_dec = Runner.run("Direct decode (w/header)", iterations, fn -> SimpleFixed.decode(simple_bin) end)
    dispatch_dec = Runner.run("Dispatch decode", iterations, fn -> GridCodec.decode(simple_bin) end)

    {_, direct_enc_ns, _} = direct_enc
    {_, protocol_enc_ns, _} = protocol_enc
    {_, direct_dec_ns, _} = direct_dec
    {_, dispatch_dec_ns, _} = dispatch_dec

    IO.puts("\nEncode:")
    IO.puts("  Direct: #{Float.round(direct_enc_ns, 1)} ns")
    IO.puts("  Protocol: #{Float.round(protocol_enc_ns, 1)} ns")
    IO.puts("  Overhead: #{Float.round(protocol_enc_ns - direct_enc_ns, 1)} ns (#{Float.round((protocol_enc_ns - direct_enc_ns) / direct_enc_ns * 100, 1)}%)")

    IO.puts("\nDecode:")
    IO.puts("  Direct: #{Float.round(direct_dec_ns, 1)} ns")
    IO.puts("  Dispatch: #{Float.round(dispatch_dec_ns, 1)} ns")
    IO.puts("  Overhead: #{Float.round(dispatch_dec_ns - direct_dec_ns, 1)} ns (#{Float.round((dispatch_dec_ns - direct_dec_ns) / direct_dec_ns * 100, 1)}%)")

    # ========================================================================
    # SUMMARY
    # ========================================================================
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("PERFORMANCE SUMMARY")
    IO.puts(String.duplicate("=", 80))

    {_, hand_enc_ns, _} = Enum.find(encode_results, fn {n, _, _} -> String.contains?(n, "Hand-rolled") end)
    {_, simple_enc_ns, _} = Enum.find(encode_results, fn {n, _, _} -> String.contains?(n, "SimpleFixed.encode (no header)") end)
    {_, hand_dec_ns, _} = Enum.find(decode_results, fn {n, _, _} -> String.contains?(n, "Hand-rolled") end)
    {_, simple_dec_ns, _} = Enum.find(decode_results, fn {n, _, _} -> String.contains?(n, "SimpleFixed.decode (no header)") end)

    enc_ratio = simple_enc_ns / hand_enc_ns
    dec_ratio = simple_dec_ns / hand_dec_ns

    IO.puts("")
    IO.puts("GridCodec.Struct vs Hand-rolled:")
    IO.puts("  Encode: #{Float.round(enc_ratio, 2)}x (#{if enc_ratio < 1, do: "faster", else: "slower"})")
    IO.puts("  Decode: #{Float.round(dec_ratio, 2)}x (#{if dec_ratio < 1, do: "faster", else: "slower"})")

    threshold = 1.15
    all_pass = enc_ratio < threshold and dec_ratio < threshold

    if all_pass do
      IO.puts("\n✓ PASS: All performance targets met (< #{trunc((threshold - 1) * 100)}% overhead)")
    else
      IO.puts("\n✗ WARN: Some performance targets exceeded")
    end

    IO.puts("")

    all_pass
  end
end

result = Bench.Main.run()
if result, do: System.stop(0), else: System.stop(1)
