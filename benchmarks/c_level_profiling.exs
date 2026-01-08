defmodule Bench.CLevelProfiling do
  @moduledoc """
  C-level profiling and tracing for GridCodec.Struct performance analysis.

  This script uses:
  - :fprof for Erlang-level profiling
  - :eprof for time profiling
  - System-level tools (perf/dtrace/instruments) for C-level analysis
  - JIT-specific analysis for BeamAsm optimizations

  Updated for GridCodec v0.5.0+ API:
  - encode/1 includes header by default
  - decode/1 expects header by default
  - get/2 macro works directly on binary (no wrap needed)
  """

  # Test data
  defmodule TestOrder do
    use GridCodec.Struct, template_id: 1, schema_id: 100

    defcodec do
      field :order_id, :uuid
      field :user_id, :u64
      field :price, :u64
      field :quantity, :u32
      field :side, :u8
      field :timestamp, :timestamp_us
      field :flags, :u8
    end
  end

  defmodule HandRolledOrder do
    defstruct [:order_id, :user_id, :price, :quantity, :side, :timestamp, :flags]

    def encode(%__MODULE__{} = order) do
      # Use integer timestamp directly for fair comparison
      ts = if is_integer(order.timestamp), do: order.timestamp, else: 0

      <<order.order_id::binary-16,
        order.user_id::little-64,
        order.price::little-64,
        order.quantity::little-32,
        order.side::little-8,
        ts::little-64,
        order.flags::little-8>>
    end

    def decode(binary) do
      case binary do
        <<order_id::binary-16,
          user_id::little-64,
          price::little-64,
          quantity::little-32,
          side::little-8,
          timestamp_us::little-64,
          flags::little-8>> ->
          {:ok, %__MODULE__{
            order_id: order_id,
            user_id: user_id,
            price: price,
            quantity: quantity,
            side: side,
            timestamp: timestamp_us,
            flags: flags
          }}

        _ ->
          {:error, :invalid_binary}
      end
    end
  end

  def run do
    IO.puts("""
    ════════════════════════════════════════════════════════════════════════════
    C-LEVEL PROFILING AND PERFORMANCE ANALYSIS
    ════════════════════════════════════════════════════════════════════════════
    """)

    # Prepare test data (use integer timestamp for fair comparison)
    order_id = :crypto.strong_rand_bytes(16)
    timestamp = System.system_time(:microsecond)

    struct_order = %TestOrder{
      order_id: order_id,
      user_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000,
      side: 1,
      timestamp: timestamp,
      flags: 7
    }

    hand_order = %HandRolledOrder{
      order_id: order_id,
      user_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000,
      side: 1,
      timestamp: timestamp,
      flags: 7
    }

    # encode(struct, header: false) for payload-only comparison
    struct_bin = TestOrder.encode(struct_order, header: false)
    hand_bin = HandRolledOrder.encode(hand_order)

    IO.puts("✓ Test data prepared")
    IO.puts("  Struct binary size: #{byte_size(struct_bin)} bytes")
    IO.puts("  Hand-rolled binary size: #{byte_size(hand_bin)} bytes")
    IO.puts("  Binaries match: #{struct_bin == hand_bin}\n")

    # Run profiling
    IO.puts("── Running :fprof profiling (Erlang-level) ──────────────────────────────")
    _fprof_results = profile_with_fprof(fn ->
      for _i <- 1..1_000_000 do
        TestOrder.encode(struct_order, header: false)
      end
    end, "encode_struct")

    IO.puts("\n── Running :fprof profiling (Hand-rolled) ───────────────────────────────")
    _fprof_hand = profile_with_fprof(fn ->
      for _i <- 1..1_000_000 do
        HandRolledOrder.encode(hand_order)
      end
    end, "encode_hand")

    IO.puts("\n── Running :eprof profiling (Time-based) ───────────────────────────────")
    _eprof_results = profile_with_eprof(fn ->
      for _i <- 1..1_000_000 do
        TestOrder.encode(struct_order, header: false)
      end
    end, "encode_struct")

    IO.puts("\n── Decode profiling ────────────────────────────────────────────────────")
    _decode_fprof = profile_with_fprof(fn ->
      for _i <- 1..1_000_000 do
        TestOrder.decode(struct_bin, header: false)
      end
    end, "decode_struct")

    _decode_hand_fprof = profile_with_fprof(fn ->
      for _i <- 1..1_000_000 do
        HandRolledOrder.decode(hand_bin)
      end
    end, "decode_hand")

    # Print summary
    IO.puts("\n" <> String.duplicate("═", 80))
    IO.puts("PROFILING SUMMARY")
    IO.puts(String.duplicate("═", 80))
    IO.puts("\n:fprof results saved to:")
    IO.puts("  - fprof_encode_struct.txt")
    IO.puts("  - fprof_encode_hand.txt")
    IO.puts("  - fprof_decode_struct.txt")
    IO.puts("  - fprof_decode_hand.txt")
    IO.puts("\n:eprof results saved to:")
    IO.puts("  - eprof_encode_struct.txt")
    IO.puts("\nNext steps:")
    IO.puts("  1. Review fprof output for function call counts and time")
    IO.puts("  2. Use 'perf record' or 'instruments' for C-level profiling")
    IO.puts("  3. Check JIT compilation with :recon or :observer")
    IO.puts("  4. Analyze hot paths and optimization opportunities")
  end

  defp profile_with_fprof(fun, name) do
    :fprof.trace(:start)
    :fprof.profile(:start)

    result = fun.()

    :fprof.profile(:stop)
    :fprof.trace(:stop)

    output_file = "fprof_#{name}.txt"
    :fprof.analyse(
      dest: String.to_charlist(output_file),
      totals: true,
      details: true,
      callers: true,
      sort: :own
    )

    IO.puts("  ✓ Profiling complete - results saved to #{output_file}")
    result
  end

  defp profile_with_eprof(fun, name) do
    :eprof.start()
    :eprof.start_profiling([self()])

    result = fun.()

    :eprof.stop_profiling()
    output_file = "eprof_#{name}.txt"

    # Capture eprof output
    output = capture_io(fn ->
      :eprof.log(String.to_charlist(output_file))
      :eprof.analyze()
    end)

    File.write!(output_file, output)
    :eprof.stop()

    IO.puts("  ✓ Profiling complete - results saved to #{output_file}")
    result
  end

  defp capture_io(fun) do
    # Simple capture using ExUnit's capture_io if available, otherwise just run
    try do
      ExUnit.CaptureIO.capture_io(fun)
    rescue
      _ ->
        fun.()
        ""
    end
  end
end

# Run if executed directly
if System.argv() != [] or true do
  Bench.CLevelProfiling.run()
end
