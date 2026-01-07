defmodule Bench.MapsVsCodec do
  @moduledoc """
  Benchmark comparing Elixir Maps vs GridCodec zero-copy binary access.

  Inspired by: https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909
  Original gist: https://gist.github.com/akoutmos/6e965558fa8bb5771e90b1961762a7d0

  This benchmark compares:
  1. Map read performance (atom keys) at different sizes
  2. GridCodec zero-copy field access from encoded binary (no decode!)

  Key insight: GridCodec's `wrap/1` + `get/2` extracts fields directly from
  the binary using compile-time offsets - O(1) access without full decode.

  Erlang map thresholds:
  - <= 32 keys: flat map (linear search, cache-friendly)
  - > 32 keys: HAMT (hash array mapped trie)
  """

  alias ExampleApp.Bench.{SmallStruct, MediumStruct, LargeStruct}

  def run do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║        Maps vs GridCodec Zero-Copy Access Benchmark              ║
    ║                                                                  ║
    ║  Based on: https://elixirforum.com/t/big-maps-versus-small-maps  ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)

    run_zero_copy_vs_map_access()
    run_batch_access_comparison()
    run_map_read_benchmarks()
    run_encode_decode_comparison()
  end

  # ============================================================================
  # Part 1: Zero-Copy Binary Access vs Map Access (Main Comparison)
  # ============================================================================

  defp run_zero_copy_vs_map_access do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 1: Zero-Copy Binary Access vs Map Field Access")
    IO.puts("GridCodec.get(env, :field) vs Map.get(map, :field)")
    IO.puts(String.duplicate("═", 70) <> "\n")

    # Prepare codec binaries (wrap once, access many times)
    small_struct = build_small_struct()
    medium_struct = build_medium_struct()
    large_struct = build_large_struct()

    small_bin = SmallStruct.encode(small_struct)
    medium_bin = MediumStruct.encode(medium_struct)
    large_bin = LargeStruct.encode(large_struct)

    # Wrap for zero-copy access (this is the "hot path" usage)
    small_env = SmallStruct.wrap(small_bin)
    medium_env = MediumStruct.wrap(medium_bin)
    large_env = LargeStruct.wrap(large_bin)

    # Equivalent maps with atom keys
    small_map = struct_to_map(small_struct, 8)
    medium_map = struct_to_map(medium_struct, 32)
    large_map = struct_to_map(large_struct, 33)

    IO.puts("Binary sizes: Small=#{byte_size(small_bin)}B, Medium=#{byte_size(medium_bin)}B, Large=#{byte_size(large_bin)}B\n")

    IO.puts("── Small (8 fields) ──\n")

    Benchee.run(
      %{
        "Codec get (field_1)" => fn -> SmallStruct.get(small_env, :field_1) end,
        "Codec get (field_4)" => fn -> SmallStruct.get(small_env, :field_4) end,
        "Codec get (field_8)" => fn -> SmallStruct.get(small_env, :field_8) end,
        "Map.get (field_1)" => fn -> Map.get(small_map, :field_1) end,
        "Map.get (field_4)" => fn -> Map.get(small_map, :field_4) end,
        "Map.get (field_8)" => fn -> Map.get(small_map, :field_8) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )

    IO.puts("\n── Medium (32 fields - flat map limit) ──\n")

    Benchee.run(
      %{
        "Codec get (field_1)" => fn -> MediumStruct.get(medium_env, :field_1) end,
        "Codec get (field_16)" => fn -> MediumStruct.get(medium_env, :field_16) end,
        "Codec get (field_32)" => fn -> MediumStruct.get(medium_env, :field_32) end,
        "Map.get (field_1)" => fn -> Map.get(medium_map, :field_1) end,
        "Map.get (field_16)" => fn -> Map.get(medium_map, :field_16) end,
        "Map.get (field_32)" => fn -> Map.get(medium_map, :field_32) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )

    IO.puts("\n── Large (33 fields - triggers HAMT) ──\n")

    Benchee.run(
      %{
        "Codec get (field_1)" => fn -> LargeStruct.get(large_env, :field_1) end,
        "Codec get (field_16)" => fn -> LargeStruct.get(large_env, :field_16) end,
        "Codec get (field_33)" => fn -> LargeStruct.get(large_env, :field_33) end,
        "Map.get (field_1)" => fn -> Map.get(large_map, :field_1) end,
        "Map.get (field_16)" => fn -> Map.get(large_map, :field_16) end,
        "Map.get (field_33)" => fn -> Map.get(large_map, :field_33) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Part 2: Batch Access Comparison
  # ============================================================================

  defp run_batch_access_comparison do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 2: Batch Access - Multiple Field Reads")
    IO.puts(String.duplicate("═", 70) <> "\n")

    small_struct = build_small_struct()
    small_bin = SmallStruct.encode(small_struct)
    small_env = SmallStruct.wrap(small_bin)
    small_map = struct_to_map(small_struct, 8)

    Benchee.run(
      %{
        "Codec: get 3 fields" => fn ->
          {SmallStruct.get(small_env, :field_1),
           SmallStruct.get(small_env, :field_4),
           SmallStruct.get(small_env, :field_8)}
        end,
        "Codec: get_many/2 (3 fields)" => fn ->
          GridCodec.Envelope.get_many(small_env, [:field_1, :field_4, :field_8])
        end,
        "Map: get 3 fields" => fn ->
          {Map.get(small_map, :field_1),
           Map.get(small_map, :field_4),
           Map.get(small_map, :field_8)}
        end,
        "Map: Map.take/2 (3 fields)" => fn ->
          Map.take(small_map, [:field_1, :field_4, :field_8])
        end,
        "Codec: full decode (8 fields)" => fn ->
          SmallStruct.decode(small_bin)
        end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )

    IO.puts("\n── Crossover point: When is full decode better? ──\n")

    medium_struct = build_medium_struct()
    medium_bin = MediumStruct.encode(medium_struct)
    medium_env = MediumStruct.wrap(medium_bin)
    medium_map = struct_to_map(medium_struct, 32)

    Benchee.run(
      %{
        "Codec: get 8 fields" => fn ->
          {MediumStruct.get(medium_env, :field_1),
           MediumStruct.get(medium_env, :field_4),
           MediumStruct.get(medium_env, :field_8),
           MediumStruct.get(medium_env, :field_12),
           MediumStruct.get(medium_env, :field_16),
           MediumStruct.get(medium_env, :field_20),
           MediumStruct.get(medium_env, :field_24),
           MediumStruct.get(medium_env, :field_28)}
        end,
        "Map: get 8 fields" => fn ->
          {Map.get(medium_map, :field_1),
           Map.get(medium_map, :field_4),
           Map.get(medium_map, :field_8),
           Map.get(medium_map, :field_12),
           Map.get(medium_map, :field_16),
           Map.get(medium_map, :field_20),
           Map.get(medium_map, :field_24),
           Map.get(medium_map, :field_28)}
        end,
        "Codec: full decode (32 fields)" => fn ->
          MediumStruct.decode(medium_bin)
        end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Part 3: Original Map Read Benchmarks (Reference)
  # ============================================================================

  defp run_map_read_benchmarks do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 3: Map Read Performance Reference (Atom Keys)")
    IO.puts("(Original benchmark reproduction)")
    IO.puts(String.duplicate("═", 70) <> "\n")

    # Really small map (8 keys)
    atom_small =
      1..8
      |> Enum.map(fn val -> {String.to_atom("field_#{val}"), val} end)
      |> Map.new()

    # Small map (32 keys - flat map limit)
    atom_medium =
      1..32
      |> Enum.map(fn val -> {String.to_atom("field_#{val}"), val} end)
      |> Map.new()

    # Large map (33 keys - triggers HAMT)
    atom_large =
      1..33
      |> Enum.map(fn val -> {String.to_atom("field_#{val}"), val} end)
      |> Map.new()

    Benchee.run(
      %{
        "Small (8) - first" => fn -> Map.get(atom_small, :field_1) end,
        "Small (8) - middle" => fn -> Map.get(atom_small, :field_4) end,
        "Small (8) - last" => fn -> Map.get(atom_small, :field_8) end,
        "Small (8) - miss" => fn -> Map.get(atom_small, :field_error) end,
        "Medium (32) - first" => fn -> Map.get(atom_medium, :field_1) end,
        "Medium (32) - middle" => fn -> Map.get(atom_medium, :field_16) end,
        "Medium (32) - last" => fn -> Map.get(atom_medium, :field_32) end,
        "Medium (32) - miss" => fn -> Map.get(atom_medium, :field_error) end,
        "Large (33) - first" => fn -> Map.get(atom_large, :field_1) end,
        "Large (33) - middle" => fn -> Map.get(atom_large, :field_16) end,
        "Large (33) - last" => fn -> Map.get(atom_large, :field_33) end,
        "Large (33) - miss" => fn -> Map.get(atom_large, :field_error) end
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
