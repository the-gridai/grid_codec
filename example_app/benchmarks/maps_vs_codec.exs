defmodule Bench.MapsVsCodec do
  @moduledoc """
  Benchmark comparing Elixir Maps vs GridCodec performance.

  Inspired by: https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909
  Original gist: https://gist.github.com/akoutmos/6e965558fa8bb5771e90b1961762a7d0

  This benchmark compares:
  1. Map read performance (atom, binary, integer keys) at different sizes
  2. GridCodec encode/decode performance
  3. Field access patterns on decoded structs
  4. Serialization alternatives (term_to_binary, JSON)

  Key size thresholds in Erlang/OTP:
  - <= 32 keys: flat map (linear search, but cache-friendly)
  - > 32 keys: HAMT (hash array mapped trie, O(log32 n))
  """

  alias ExampleApp.Bench.{SmallStruct, MediumStruct, LargeStruct}

  def run do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║           Maps vs GridCodec Benchmark Suite                      ║
    ║                                                                  ║
    ║  Based on: https://elixirforum.com/t/big-maps-versus-small-maps  ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)

    run_map_read_benchmarks()
    run_codec_vs_map_serialization()
    run_field_access_comparison()
  end

  # ============================================================================
  # Part 1: Original Map Read Benchmarks (Reproduced)
  # ============================================================================

  defp run_map_read_benchmarks do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 1: Map Read Performance by Key Type and Size")
    IO.puts("(Reproducing original benchmark)")
    IO.puts(String.duplicate("═", 70) <> "\n")

    run_atom_map_benchmarks()
    run_integer_map_benchmarks()
    run_binary_map_benchmarks()
  end

  defp run_atom_map_benchmarks do
    IO.puts("\n── Atom Keys ──\n")

    # Really small map (8 keys)
    atom_small =
      1..8
      |> Enum.map(fn val -> {String.to_atom("key_#{val}"), val} end)
      |> Map.new()

    # Small map (32 keys - flat map limit)
    atom_medium =
      1..32
      |> Enum.map(fn val -> {String.to_atom("key_#{val}"), val} end)
      |> Map.new()

    # Large map (33 keys - triggers HAMT)
    atom_large =
      1..33
      |> Enum.map(fn val -> {String.to_atom("key_#{val}"), val} end)
      |> Map.new()

    Benchee.run(
      %{
        "Atom Small (8) - first" => fn -> Map.get(atom_small, :key_1) end,
        "Atom Small (8) - middle" => fn -> Map.get(atom_small, :key_4) end,
        "Atom Small (8) - last" => fn -> Map.get(atom_small, :key_8) end,
        "Atom Small (8) - miss" => fn -> Map.get(atom_small, :key_error) end,
        "Atom Medium (32) - first" => fn -> Map.get(atom_medium, :key_1) end,
        "Atom Medium (32) - middle" => fn -> Map.get(atom_medium, :key_16) end,
        "Atom Medium (32) - last" => fn -> Map.get(atom_medium, :key_32) end,
        "Atom Medium (32) - miss" => fn -> Map.get(atom_medium, :key_error) end,
        "Atom Large (33) - first" => fn -> Map.get(atom_large, :key_1) end,
        "Atom Large (33) - middle" => fn -> Map.get(atom_large, :key_16) end,
        "Atom Large (33) - last" => fn -> Map.get(atom_large, :key_33) end,
        "Atom Large (33) - miss" => fn -> Map.get(atom_large, :key_error) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false]
    )
  end

  defp run_integer_map_benchmarks do
    IO.puts("\n── Integer Keys ──\n")

    int_small = 1..8 |> Enum.map(fn val -> {val, val} end) |> Map.new()
    int_medium = 1..32 |> Enum.map(fn val -> {val, val} end) |> Map.new()
    int_large = 1..33 |> Enum.map(fn val -> {val, val} end) |> Map.new()

    Benchee.run(
      %{
        "Int Small (8) - first" => fn -> Map.get(int_small, 1) end,
        "Int Small (8) - middle" => fn -> Map.get(int_small, 4) end,
        "Int Small (8) - last" => fn -> Map.get(int_small, 8) end,
        "Int Small (8) - miss" => fn -> Map.get(int_small, 100) end,
        "Int Medium (32) - first" => fn -> Map.get(int_medium, 1) end,
        "Int Medium (32) - middle" => fn -> Map.get(int_medium, 16) end,
        "Int Medium (32) - last" => fn -> Map.get(int_medium, 32) end,
        "Int Medium (32) - miss" => fn -> Map.get(int_medium, 100) end,
        "Int Large (33) - first" => fn -> Map.get(int_large, 1) end,
        "Int Large (33) - middle" => fn -> Map.get(int_large, 16) end,
        "Int Large (33) - last" => fn -> Map.get(int_large, 33) end,
        "Int Large (33) - miss" => fn -> Map.get(int_large, 100) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false]
    )
  end

  defp run_binary_map_benchmarks do
    IO.puts("\n── Binary (String) Keys ──\n")

    bin_small = 1..8 |> Enum.map(fn val -> {"key_#{val}", val} end) |> Map.new()
    bin_medium = 1..32 |> Enum.map(fn val -> {"key_#{val}", val} end) |> Map.new()
    bin_large = 1..33 |> Enum.map(fn val -> {"key_#{val}", val} end) |> Map.new()

    Benchee.run(
      %{
        "Binary Small (8) - first" => fn -> Map.get(bin_small, "key_1") end,
        "Binary Small (8) - middle" => fn -> Map.get(bin_small, "key_4") end,
        "Binary Small (8) - last" => fn -> Map.get(bin_small, "key_8") end,
        "Binary Small (8) - miss" => fn -> Map.get(bin_small, "key_error") end,
        "Binary Medium (32) - first" => fn -> Map.get(bin_medium, "key_1") end,
        "Binary Medium (32) - middle" => fn -> Map.get(bin_medium, "key_16") end,
        "Binary Medium (32) - last" => fn -> Map.get(bin_medium, "key_32") end,
        "Binary Medium (32) - miss" => fn -> Map.get(bin_medium, "key_error") end,
        "Binary Large (33) - first" => fn -> Map.get(bin_large, "key_1") end,
        "Binary Large (33) - middle" => fn -> Map.get(bin_large, "key_16") end,
        "Binary Large (33) - last" => fn -> Map.get(bin_large, "key_33") end,
        "Binary Large (33) - miss" => fn -> Map.get(bin_large, "key_error") end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false]
    )
  end

  # ============================================================================
  # Part 2: Codec vs Map Serialization
  # ============================================================================

  defp run_codec_vs_map_serialization do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 2: Serialization - GridCodec vs term_to_binary vs JSON")
    IO.puts(String.duplicate("═", 70) <> "\n")

    # Prepare codec structs
    small_struct = build_small_struct()
    medium_struct = build_medium_struct()
    large_struct = build_large_struct()

    # Prepare equivalent maps
    small_map = struct_to_map(small_struct, 8)
    medium_map = struct_to_map(medium_struct, 32)
    large_map = struct_to_map(large_struct, 33)

    # Pre-encode for decode benchmarks
    small_codec_bin = SmallStruct.encode(small_struct)
    medium_codec_bin = MediumStruct.encode(medium_struct)
    large_codec_bin = LargeStruct.encode(large_struct)

    small_term_bin = :erlang.term_to_binary(small_map)
    medium_term_bin = :erlang.term_to_binary(medium_map)
    large_term_bin = :erlang.term_to_binary(large_map)

    IO.puts("Binary sizes:")
    IO.puts("  Small (8 fields):  Codec=#{byte_size(small_codec_bin)}B, term_to_binary=#{byte_size(small_term_bin)}B")
    IO.puts("  Medium (32 fields): Codec=#{byte_size(medium_codec_bin)}B, term_to_binary=#{byte_size(medium_term_bin)}B")
    IO.puts("  Large (33 fields):  Codec=#{byte_size(large_codec_bin)}B, term_to_binary=#{byte_size(large_term_bin)}B")
    IO.puts("")

    IO.puts("── Encode Performance ──\n")

    Benchee.run(
      %{
        "GridCodec Small (8)" => fn -> SmallStruct.encode(small_struct) end,
        "GridCodec Medium (32)" => fn -> MediumStruct.encode(medium_struct) end,
        "GridCodec Large (33)" => fn -> LargeStruct.encode(large_struct) end,
        "term_to_binary Small (8)" => fn -> :erlang.term_to_binary(small_map) end,
        "term_to_binary Medium (32)" => fn -> :erlang.term_to_binary(medium_map) end,
        "term_to_binary Large (33)" => fn -> :erlang.term_to_binary(large_map) end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      print: [configuration: false]
    )

    IO.puts("\n── Decode Performance ──\n")

    Benchee.run(
      %{
        "GridCodec Small (8)" => fn -> SmallStruct.decode(small_codec_bin) end,
        "GridCodec Medium (32)" => fn -> MediumStruct.decode(medium_codec_bin) end,
        "GridCodec Large (33)" => fn -> LargeStruct.decode(large_codec_bin) end,
        "binary_to_term Small (8)" => fn -> :erlang.binary_to_term(small_term_bin) end,
        "binary_to_term Medium (32)" => fn -> :erlang.binary_to_term(medium_term_bin) end,
        "binary_to_term Large (33)" => fn -> :erlang.binary_to_term(large_term_bin) end
      },
      warmup: 1,
      time: 3,
      memory_time: 1,
      print: [configuration: false]
    )
  end

  # ============================================================================
  # Part 3: Field Access on Decoded Structs vs Maps
  # ============================================================================

  defp run_field_access_comparison do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("PART 3: Field Access - Struct vs Map After Decode")
    IO.puts(String.duplicate("═", 70) <> "\n")

    # Prepare codec structs (decoded)
    small_struct = build_small_struct()
    medium_struct = build_medium_struct()
    large_struct = build_large_struct()

    # Prepare equivalent maps
    small_map = struct_to_map(small_struct, 8)
    medium_map = struct_to_map(medium_struct, 32)
    large_map = struct_to_map(large_struct, 33)

    IO.puts("Comparing single field access on in-memory data structures.\n")

    Benchee.run(
      %{
        # Struct field access (compile-time optimized)
        "Struct Small - field_1" => fn -> small_struct.field_1 end,
        "Struct Small - field_4" => fn -> small_struct.field_4 end,
        "Struct Small - field_8" => fn -> small_struct.field_8 end,
        "Struct Medium - field_1" => fn -> medium_struct.field_1 end,
        "Struct Medium - field_16" => fn -> medium_struct.field_16 end,
        "Struct Medium - field_32" => fn -> medium_struct.field_32 end,
        "Struct Large - field_1" => fn -> large_struct.field_1 end,
        "Struct Large - field_16" => fn -> large_struct.field_16 end,
        "Struct Large - field_33" => fn -> large_struct.field_33 end,
        # Map access with atom keys
        "Map Small - field_1" => fn -> Map.get(small_map, :field_1) end,
        "Map Small - field_4" => fn -> Map.get(small_map, :field_4) end,
        "Map Small - field_8" => fn -> Map.get(small_map, :field_8) end,
        "Map Medium - field_1" => fn -> Map.get(medium_map, :field_1) end,
        "Map Medium - field_16" => fn -> Map.get(medium_map, :field_16) end,
        "Map Medium - field_32" => fn -> Map.get(medium_map, :field_32) end,
        "Map Large - field_1" => fn -> Map.get(large_map, :field_1) end,
        "Map Large - field_16" => fn -> Map.get(large_map, :field_16) end,
        "Map Large - field_33" => fn -> Map.get(large_map, :field_33) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false]
    )

    IO.puts("\n── Multiple Field Access (Batch Read) ──\n")

    Benchee.run(
      %{
        "Struct Small - read all 8" => fn ->
          {small_struct.field_1, small_struct.field_2, small_struct.field_3, small_struct.field_4,
           small_struct.field_5, small_struct.field_6, small_struct.field_7, small_struct.field_8}
        end,
        "Map Small - read all 8" => fn ->
          {Map.get(small_map, :field_1), Map.get(small_map, :field_2), Map.get(small_map, :field_3),
           Map.get(small_map, :field_4), Map.get(small_map, :field_5), Map.get(small_map, :field_6),
           Map.get(small_map, :field_7), Map.get(small_map, :field_8)}
        end,
        "Map Small - Map.take" => fn -> Map.take(small_map, [:field_1, :field_2, :field_3, :field_4, :field_5, :field_6, :field_7, :field_8]) end
      },
      warmup: 1,
      time: 3,
      print: [configuration: false]
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

