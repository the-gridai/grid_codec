defmodule Bench.MapsVsCodec do
  @moduledoc """
  Benchmark comparing Elixir Maps vs GridCodec binary access methods.

  Inspired by: https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909
  Original gist: https://gist.github.com/akoutmos/6e965558fa8bb5771e90b1961762a7d0

  This benchmark compares:
  1. Map read performance (atom keys)
  2. GridCodec envelope-based get/2 (with struct dispatch overhead)
  3. GridCodec match macro (direct binary pattern match - fastest!)
  """

  alias ExampleApp.Bench.{SmallStruct, MediumStruct, LargeStruct}

  # Import match macros for direct binary pattern matching
  require SmallStruct
  require MediumStruct
  require LargeStruct

  def run do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║        Maps vs GridCodec Binary Access Benchmark                 ║
    ║                                                                  ║
    ║  Based on: https://elixirforum.com/t/big-maps-versus-small-maps  ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)

    run_direct_match_vs_map()
    run_envelope_comparison()
    run_batch_access_comparison()
    run_encode_decode_comparison()
  end

  # ============================================================================
  # Part 1: Direct Binary Match (match macro) vs Map Access
  # ============================================================================

  defp run_direct_match_vs_map do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 1: GridCodec get(binary, field) vs Map.get")
    IO.puts("Direct binary access with compile-time offsets")
    IO.puts(String.duplicate("═", 70) <> "\n")

    # Prepare codec binaries
    small_struct = build_small_struct()
    medium_struct = build_medium_struct()
    large_struct = build_large_struct()

    small_bin = SmallStruct.encode(small_struct)
    medium_bin = MediumStruct.encode(medium_struct)
    large_bin = LargeStruct.encode(large_struct)

    # Equivalent maps with atom keys
    small_map = struct_to_map(small_struct, 8)
    medium_map = struct_to_map(medium_struct, 32)
    large_map = struct_to_map(large_struct, 33)

    IO.puts("Binary sizes: Small=#{byte_size(small_bin)}B, Medium=#{byte_size(medium_bin)}B, Large=#{byte_size(large_bin)}B\n")

    IO.puts("── Small (8 fields) ──\n")

    Benchee.run(
      %{
        # Direct binary get - function API
        "get(bin, :field_1)" => fn -> SmallStruct.get(small_bin, :field_1) end,
        "get(bin, :field_4)" => fn -> SmallStruct.get(small_bin, :field_4) end,
        "get(bin, :field_8)" => fn -> SmallStruct.get(small_bin, :field_8) end,
        # Map access for comparison
        "Map.get field_1" => fn -> Map.get(small_map, :field_1) end,
        "Map.get field_4" => fn -> Map.get(small_map, :field_4) end,
        "Map.get field_8" => fn -> Map.get(small_map, :field_8) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )

    IO.puts("\n── Medium (32 fields - flat map limit) ──\n")

    Benchee.run(
      %{
        "get(bin, :field_1)" => fn -> MediumStruct.get(medium_bin, :field_1) end,
        "get(bin, :field_16)" => fn -> MediumStruct.get(medium_bin, :field_16) end,
        "get(bin, :field_32)" => fn -> MediumStruct.get(medium_bin, :field_32) end,
        "Map.get field_1" => fn -> Map.get(medium_map, :field_1) end,
        "Map.get field_16" => fn -> Map.get(medium_map, :field_16) end,
        "Map.get field_32" => fn -> Map.get(medium_map, :field_32) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )

    IO.puts("\n── Large (33 fields - triggers HAMT) ──\n")

    Benchee.run(
      %{
        "get(bin, :field_1)" => fn -> LargeStruct.get(large_bin, :field_1) end,
        "get(bin, :field_16)" => fn -> LargeStruct.get(large_bin, :field_16) end,
        "get(bin, :field_33)" => fn -> LargeStruct.get(large_bin, :field_33) end,
        "Map.get field_1" => fn -> Map.get(large_map, :field_1) end,
        "Map.get field_16" => fn -> Map.get(large_map, :field_16) end,
        "Map.get field_33" => fn -> Map.get(large_map, :field_33) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Part 2: Comparing all get methods
  # ============================================================================

  defp run_envelope_comparison do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 2: Comparing All Access Methods")
    IO.puts(String.duplicate("═", 70) <> "\n")

    small_struct = build_small_struct()
    small_bin = SmallStruct.encode(small_struct)
    small_env = SmallStruct.wrap(small_bin)
    small_map = struct_to_map(small_struct, 8)

    IO.puts("Comparing access methods on same data:\n")

    Benchee.run(
      %{
        "match macro" => fn ->
          case small_bin do
            SmallStruct.match(field_4: v) -> v
          end
        end,
        "get(binary, field) - direct" => fn ->
          SmallStruct.get(small_bin, :field_4)
        end,
        "get(envelope, field)" => fn ->
          SmallStruct.get(small_env, :field_4)
        end,
        "Map.get" => fn ->
          Map.get(small_map, :field_4)
        end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Part 3: Batch Access Comparison
  # ============================================================================

  defp run_batch_access_comparison do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 3: Batch Access - Multiple Field Reads")
    IO.puts(String.duplicate("═", 70) <> "\n")

    small_struct = build_small_struct()
    small_bin = SmallStruct.encode(small_struct)
    small_map = struct_to_map(small_struct, 8)

    Benchee.run(
      %{
        "get(bin, field) x3" => fn ->
          {SmallStruct.get(small_bin, :field_1),
           SmallStruct.get(small_bin, :field_4),
           SmallStruct.get(small_bin, :field_8)}
        end,
        "match 3 fields" => fn ->
          case small_bin do
            SmallStruct.match(field_1: f1, field_4: f4, field_8: f8) -> {f1, f4, f8}
          end
        end,
        "Map.get x3" => fn ->
          {Map.get(small_map, :field_1),
           Map.get(small_map, :field_4),
           Map.get(small_map, :field_8)}
        end,
        "full decode" => fn ->
          SmallStruct.decode(small_bin)
        end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )

    IO.puts("\n── Extracting all 8 fields ──\n")

    Benchee.run(
      %{
        "get(bin, field) x8" => fn ->
          {SmallStruct.get(small_bin, :field_1),
           SmallStruct.get(small_bin, :field_2),
           SmallStruct.get(small_bin, :field_3),
           SmallStruct.get(small_bin, :field_4),
           SmallStruct.get(small_bin, :field_5),
           SmallStruct.get(small_bin, :field_6),
           SmallStruct.get(small_bin, :field_7),
           SmallStruct.get(small_bin, :field_8)}
        end,
        "match all 8 fields" => fn ->
          case small_bin do
            SmallStruct.match(
              field_1: f1,
              field_2: f2,
              field_3: f3,
              field_4: f4,
              field_5: f5,
              field_6: f6,
              field_7: f7,
              field_8: f8
            ) ->
              {f1, f2, f3, f4, f5, f6, f7, f8}
          end
        end,
        "Map.get x8" => fn ->
          {Map.get(small_map, :field_1),
           Map.get(small_map, :field_2),
           Map.get(small_map, :field_3),
           Map.get(small_map, :field_4),
           Map.get(small_map, :field_5),
           Map.get(small_map, :field_6),
           Map.get(small_map, :field_7),
           Map.get(small_map, :field_8)}
        end,
        "full decode" => fn ->
          SmallStruct.decode(small_bin)
        end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Part 4: Encode/Decode Comparison
  # ============================================================================

  defp run_encode_decode_comparison do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 4: Serialization - GridCodec vs term_to_binary")
    IO.puts(String.duplicate("═", 70) <> "\n")

    small_struct = build_small_struct()
    medium_struct = build_medium_struct()
    large_struct = build_large_struct()

    small_map = struct_to_map(small_struct, 8)
    medium_map = struct_to_map(medium_struct, 32)
    large_map = struct_to_map(large_struct, 33)

    small_codec_bin = SmallStruct.encode(small_struct)
    medium_codec_bin = MediumStruct.encode(medium_struct)
    large_codec_bin = LargeStruct.encode(large_struct)

    small_term_bin = :erlang.term_to_binary(small_map)
    medium_term_bin = :erlang.term_to_binary(medium_map)
    large_term_bin = :erlang.term_to_binary(large_map)

    IO.puts("Binary sizes:")
    IO.puts("  Small (8):   Codec=#{byte_size(small_codec_bin)}B, ETF=#{byte_size(small_term_bin)}B (#{trunc((1 - byte_size(small_codec_bin) / byte_size(small_term_bin)) * 100)}% smaller)")
    IO.puts("  Medium (32): Codec=#{byte_size(medium_codec_bin)}B, ETF=#{byte_size(medium_term_bin)}B (#{trunc((1 - byte_size(medium_codec_bin) / byte_size(medium_term_bin)) * 100)}% smaller)")
    IO.puts("  Large (33):  Codec=#{byte_size(large_codec_bin)}B, ETF=#{byte_size(large_term_bin)}B (#{trunc((1 - byte_size(large_codec_bin) / byte_size(large_term_bin)) * 100)}% smaller)")
    IO.puts("")

    IO.puts("── Encode ──\n")

    Benchee.run(
      %{
        "Codec Small (8)" => fn -> SmallStruct.encode(small_struct) end,
        "Codec Medium (32)" => fn -> MediumStruct.encode(medium_struct) end,
        "Codec Large (33)" => fn -> LargeStruct.encode(large_struct) end,
        "ETF Small (8)" => fn -> :erlang.term_to_binary(small_map) end,
        "ETF Medium (32)" => fn -> :erlang.term_to_binary(medium_map) end,
        "ETF Large (33)" => fn -> :erlang.term_to_binary(large_map) end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      print: [configuration: false, fast_warning: false]
    )

    IO.puts("\n── Decode ──\n")

    Benchee.run(
      %{
        "Codec Small (8)" => fn -> SmallStruct.decode(small_codec_bin) end,
        "Codec Medium (32)" => fn -> MediumStruct.decode(medium_codec_bin) end,
        "Codec Large (33)" => fn -> LargeStruct.decode(large_codec_bin) end,
        "ETF Small (8)" => fn -> :erlang.binary_to_term(small_term_bin) end,
        "ETF Medium (32)" => fn -> :erlang.binary_to_term(medium_term_bin) end,
        "ETF Large (33)" => fn -> :erlang.binary_to_term(large_term_bin) end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp build_small_struct do
    %SmallStruct{
      field_1: 1, field_2: 2, field_3: 3, field_4: 4,
      field_5: 5, field_6: 6, field_7: 7, field_8: 8
    }
  end

  defp build_medium_struct do
    %MediumStruct{
      field_1: 1, field_2: 2, field_3: 3, field_4: 4,
      field_5: 5, field_6: 6, field_7: 7, field_8: 8,
      field_9: 9, field_10: 10, field_11: 11, field_12: 12,
      field_13: 13, field_14: 14, field_15: 15, field_16: 16,
      field_17: 17, field_18: 18, field_19: 19, field_20: 20,
      field_21: 21, field_22: 22, field_23: 23, field_24: 24,
      field_25: 25, field_26: 26, field_27: 27, field_28: 28,
      field_29: 29, field_30: 30, field_31: 31, field_32: 32
    }
  end

  defp build_large_struct do
    %LargeStruct{
      field_1: 1, field_2: 2, field_3: 3, field_4: 4,
      field_5: 5, field_6: 6, field_7: 7, field_8: 8,
      field_9: 9, field_10: 10, field_11: 11, field_12: 12,
      field_13: 13, field_14: 14, field_15: 15, field_16: 16,
      field_17: 17, field_18: 18, field_19: 19, field_20: 20,
      field_21: 21, field_22: 22, field_23: 23, field_24: 24,
      field_25: 25, field_26: 26, field_27: 27, field_28: 28,
      field_29: 29, field_30: 30, field_31: 31, field_32: 32,
      field_33: 33
    }
  end

  defp struct_to_map(_struct, field_count) do
    1..field_count
    |> Enum.map(fn i -> {String.to_atom("field_#{i}"), i} end)
    |> Map.new()
  end
end

# Run the benchmark
Bench.MapsVsCodec.run()
