defmodule Bench.MapsVsCodec do
  @moduledoc """
  Benchmark comparing Elixir Maps vs GridCodec binary access.

  Inspired by: https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909

  Focus:
  - Small (8 fields), Medium (32 fields - flat map limit), Large (33 fields - HAMT)
  - Field positions: start, middle, end
  - Access methods: Map.get, match macro, get! macro
  """

  alias ExampleApp.Bench.{SmallStruct, MediumStruct, LargeStruct}

  require SmallStruct
  require MediumStruct
  require LargeStruct

  def run do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║           Maps vs GridCodec Binary Access Benchmark              ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  match  = raw binary pattern (no null check)                     ║
    ║  get!   = inline binary pattern (with null check)                ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)

    run_small()
    run_medium()
    run_large()
  end

  # ============================================================================
  # Small (8 fields) - Flat map, fast access
  # ============================================================================

  defp run_small do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("SMALL (8 fields) - Flat map")
    IO.puts(String.duplicate("═", 70) <> "\n")

    struct = build_small_struct()
    binary = SmallStruct.encode(struct)
    map = struct_to_map(struct, 8)

    IO.puts("Binary size: #{byte_size(binary)} bytes\n")

    Benchee.run(
      %{
        # Map access
        "Map.get (start)" => fn -> Map.get(map, :field_1) end,
        "Map.get (mid)" => fn -> Map.get(map, :field_4) end,
        "Map.get (end)" => fn -> Map.get(map, :field_8) end,
        # match macro - raw binary pattern (no null check)
        "match (start)" => fn -> case binary do SmallStruct.match(field_1: v) -> v end end,
        "match (mid)" => fn -> case binary do SmallStruct.match(field_4: v) -> v end end,
        "match (end)" => fn -> case binary do SmallStruct.match(field_8: v) -> v end end,
        # get! macro - inline binary pattern (with null check)
        "get! (start)" => fn -> SmallStruct.get!(binary, :field_1) end,
        "get! (mid)" => fn -> SmallStruct.get!(binary, :field_4) end,
        "get! (end)" => fn -> SmallStruct.get!(binary, :field_8) end
      },
      warmup: 2,
      time: 5,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Medium (32 fields) - At flat map limit
  # ============================================================================

  defp run_medium do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("MEDIUM (32 fields) - Flat map limit")
    IO.puts(String.duplicate("═", 70) <> "\n")

    struct = build_medium_struct()
    binary = MediumStruct.encode(struct)
    map = struct_to_map(struct, 32)

    IO.puts("Binary size: #{byte_size(binary)} bytes\n")

    Benchee.run(
      %{
        "Map.get (start)" => fn -> Map.get(map, :field_1) end,
        "Map.get (mid)" => fn -> Map.get(map, :field_16) end,
        "Map.get (end)" => fn -> Map.get(map, :field_32) end,
        "match (start)" => fn -> case binary do MediumStruct.match(field_1: v) -> v end end,
        "match (mid)" => fn -> case binary do MediumStruct.match(field_16: v) -> v end end,
        "match (end)" => fn -> case binary do MediumStruct.match(field_32: v) -> v end end,
        "get! (start)" => fn -> MediumStruct.get!(binary, :field_1) end,
        "get! (mid)" => fn -> MediumStruct.get!(binary, :field_16) end,
        "get! (end)" => fn -> MediumStruct.get!(binary, :field_32) end
      },
      warmup: 2,
      time: 5,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Large (33 fields) - HAMT triggered
  # ============================================================================

  defp run_large do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("LARGE (33 fields) - HAMT map")
    IO.puts(String.duplicate("═", 70) <> "\n")

    struct = build_large_struct()
    binary = LargeStruct.encode(struct)
    map = struct_to_map(struct, 33)

    IO.puts("Binary size: #{byte_size(binary)} bytes\n")

    Benchee.run(
      %{
        "Map.get (start)" => fn -> Map.get(map, :field_1) end,
        "Map.get (mid)" => fn -> Map.get(map, :field_16) end,
        "Map.get (end)" => fn -> Map.get(map, :field_33) end,
        "match (start)" => fn -> case binary do LargeStruct.match(field_1: v) -> v end end,
        "match (mid)" => fn -> case binary do LargeStruct.match(field_16: v) -> v end end,
        "match (end)" => fn -> case binary do LargeStruct.match(field_33: v) -> v end end,
        "get! (start)" => fn -> LargeStruct.get!(binary, :field_1) end,
        "get! (mid)" => fn -> LargeStruct.get!(binary, :field_16) end,
        "get! (end)" => fn -> LargeStruct.get!(binary, :field_33) end
      },
      warmup: 2,
      time: 5,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Helpers
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

Bench.MapsVsCodec.run()
