# Benchee comparison of encode strategies
# Compare pattern match vs :maps.get vs GridCodec generated code

defmodule Manual.PatternMatch do
  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  # Pattern match extracts all fields in one get_map_elements
  def encode(%{id: id, count: count, flag: flag}) do
    id_val = id || @u64_null
    count_val = count || @u32_null
    flag_byte = case flag do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<id_val::little-64, count_val::little-32, flag_byte::8>>
  end
end

defmodule Manual.MapsGet do
  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  # Same as GridCodec - uses :maps.get for each field
  def encode(data) do
    id_val = case :maps.get(:id, data, @u64_null) do
      nil -> @u64_null
      v -> v
    end
    count_val = case :maps.get(:count, data, @u32_null) do
      nil -> @u32_null
      v -> v
    end
    flag_byte = case :maps.get(:flag, data, @bool_null) do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<id_val::little-64, count_val::little-32, flag_byte::8>>
  end
end

defmodule Manual.MapsGetNoNilCheck do
  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  # Skip nil check - treat nil as absent (use default)
  def encode(data) do
    id_val = :maps.get(:id, data, @u64_null)
    count_val = :maps.get(:count, data, @u32_null)

    # Bool still needs conversion
    flag_byte = case :maps.get(:flag, data, @bool_null) do
      true -> 1
      false -> 0
      _ -> @bool_null
    end

    # nil values will be encoded as-is which is wrong...
    # This only works if caller never passes nil
    <<(id_val || @u64_null)::little-64, (count_val || @u32_null)::little-32, flag_byte::8>>
  end
end

defmodule Manual.TupleInput do
  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  # Fastest possible: tuple input
  def encode({id, count, flag}) do
    id_val = id || @u64_null
    count_val = count || @u32_null
    flag_byte = case flag do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<id_val::little-64, count_val::little-32, flag_byte::8>>
  end
end

defmodule Generated.SimpleCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

# Verify all produce the same output
test_data_map = %{id: 12345, count: 100, flag: true}
test_data_tuple = {12345, 100, true}

IO.puts("Verifying correctness...")
pattern_result = Manual.PatternMatch.encode(test_data_map)
maps_get_result = Manual.MapsGet.encode(test_data_map)
no_nil_result = Manual.MapsGetNoNilCheck.encode(test_data_map)
tuple_result = Manual.TupleInput.encode(test_data_tuple)
gridcodec_result = Generated.SimpleCodec.encode(test_data_map)

IO.puts("  Pattern match:   #{inspect(pattern_result)}")
IO.puts("  :maps.get:       #{inspect(maps_get_result)}")
IO.puts("  No nil check:    #{inspect(no_nil_result)}")
IO.puts("  Tuple input:     #{inspect(tuple_result)}")
IO.puts("  GridCodec:       #{inspect(gridcodec_result)}")

all_match = pattern_result == maps_get_result and
            maps_get_result == no_nil_result and
            no_nil_result == tuple_result and
            tuple_result == gridcodec_result

IO.puts("  All match: #{all_match}")

if not all_match do
  IO.puts("ERROR: Outputs don't match!")
  System.halt(1)
end

IO.puts("\nRunning Benchee comparison...")

Benchee.run(
  %{
    "1. Tuple input (optimal)" => fn -> Manual.TupleInput.encode(test_data_tuple) end,
    "2. Pattern match" => fn -> Manual.PatternMatch.encode(test_data_map) end,
    "3. :maps.get + nil check" => fn -> Manual.MapsGet.encode(test_data_map) end,
    "4. GridCodec generated" => fn -> Generated.SimpleCodec.encode(test_data_map) end,
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)
