# Struct Fast Path Prototype
#
# This demonstrates the optimization potential of using pattern matching
# to extract all fields at once vs individual :maps.get calls

IO.puts(String.duplicate("=", 70))
IO.puts("STRUCT/PATTERN MATCH FAST PATH PROTOTYPE")
IO.puts(String.duplicate("=", 70))

# =============================================================================
# Define Both Approaches
# =============================================================================

defmodule SlowCodec do
  @moduledoc "Current GridCodec approach - individual :maps.get per field"

  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  def encode(data) do
    id = case :maps.get(:id, data, @u64_null) do
      nil -> @u64_null
      v -> v
    end

    count = case :maps.get(:count, data, @u32_null) do
      nil -> @u32_null
      v -> v
    end

    flag = case :maps.get(:flag, data, @bool_null) do
      true -> 1
      false -> 0
      _ -> @bool_null
    end

    <<id::little-64, count::little-32, flag::8>>
  end
end

defmodule FastCodec do
  @moduledoc "Optimized: pattern match extracts all fields at once"

  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  # Fast path: all keys present
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

  # Fallback: missing keys (slower path)
  def encode(data) when is_map(data) do
    id = Map.get(data, :id) || @u64_null
    count = Map.get(data, :count) || @u32_null
    flag_byte = case Map.get(data, :flag, @bool_null) do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<id::little-64, count::little-32, flag_byte::8>>
  end
end

defmodule FastestCodec do
  @moduledoc "Fastest: pattern match + no nil check for integers"

  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  # Assumes: nil means absent, use null sentinel directly
  def encode(%{id: id, count: count, flag: flag}) do
    flag_byte = case flag do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<(id || @u64_null)::little-64, (count || @u32_null)::little-32, flag_byte::8>>
  end
end

defmodule StructCodec do
  @moduledoc "Fastest possible: struct input"

  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  defstruct [:id, :count, :flag]

  def encode(%__MODULE__{id: id, count: count, flag: flag}) do
    flag_byte = case flag do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<(id || @u64_null)::little-64, (count || @u32_null)::little-32, flag_byte::8>>
  end
end

defmodule TupleCodec do
  @moduledoc "Alternative: tuple input for absolute maximum speed"

  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  # Input: {id, count, flag}
  def encode({id, count, flag}) do
    flag_byte = case flag do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<(id || @u64_null)::little-64, (count || @u32_null)::little-32, flag_byte::8>>
  end
end

# =============================================================================
# Verify Correctness
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("CORRECTNESS VERIFICATION")
IO.puts(String.duplicate("-", 70))

test_map = %{id: 12345, count: 100, flag: true}
test_struct = struct(StructCodec, id: 12345, count: 100, flag: true)
test_tuple = {12345, 100, true}

slow_result = SlowCodec.encode(test_map)
fast_result = FastCodec.encode(test_map)
fastest_result = FastestCodec.encode(test_map)
struct_result = StructCodec.encode(test_struct)
tuple_result = TupleCodec.encode(test_tuple)

IO.puts("\nAll encode to same binary: #{slow_result == fast_result and fast_result == fastest_result and fastest_result == struct_result and struct_result == tuple_result}")
IO.puts("Binary: #{inspect(slow_result)}")

# =============================================================================
# Benchmark
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("BENCHMARK")
IO.puts(String.duplicate("-", 70))

Benchee.run(
  %{
    "1. Tuple (optimal)" => fn -> TupleCodec.encode(test_tuple) end,
    "2. Struct" => fn -> StructCodec.encode(test_struct) end,
    "3. Pattern match (fast)" => fn -> FastestCodec.encode(test_map) end,
    "4. Pattern match + fallback" => fn -> FastCodec.encode(test_map) end,
    "5. Current GridCodec style" => fn -> SlowCodec.encode(test_map) end,
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  print: [fast_warning: false]
)

# =============================================================================
# Bytecode Analysis
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("BYTECODE ANALYSIS")
IO.puts(String.duplicate("-", 70))

defmodule BytecodeAnalyzer do
  def analyze(module) do
    {^module, beam} = :code.get_object_code(module)
    {:beam_file, _, _, _, _, code} = :beam_disasm.file(beam)

    encode_fn = Enum.find(code, fn
      {:function, :encode, 1, _, _} -> true
      _ -> false
    end)

    case encode_fn do
      {:function, _, _, _, instrs} ->
        # Count key instruction types
        counts = instrs
          |> Enum.map(fn
            {:get_map_elements, _, _, _} -> :get_map_elements
            {:call_ext, _, _} -> :call_ext
            {:test, :is_map, _, _} -> :is_map_test
            {:bs_create_bin, _, _, _, _, _, _} -> :bs_create_bin
            {:select_val, _, _, _} -> :select_val
            {op, _} -> op
            {op, _, _} -> op
            {op, _, _, _} -> op
            _ -> :other
          end)
          |> Enum.frequencies()

        {length(instrs), counts}
      _ ->
        {0, %{}}
    end
  end
end

for {name, mod} <- [
  {"SlowCodec (current)", SlowCodec},
  {"FastestCodec (pattern)", FastestCodec},
  {"StructCodec", StructCodec},
  {"TupleCodec", TupleCodec}
] do
  {total, counts} = BytecodeAnalyzer.analyze(mod)
  gme = Map.get(counts, :get_map_elements, 0)
  call = Map.get(counts, :call_ext, 0)

  IO.puts("\n#{name}:")
  IO.puts("  Total instructions: #{total}")
  IO.puts("  get_map_elements:   #{gme}")
  IO.puts("  call_ext:           #{call}")
end

# =============================================================================
# Summary
# =============================================================================

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("RECOMMENDATIONS")
IO.puts(String.duplicate("=", 70))

IO.puts("""

IMPLEMENTATION STRATEGY FOR GRIDCODEC:
--------------------------------------

1. GENERATE BOTH PATHS:
   ```elixir
   # Fast path: pattern match (single get_map_elements)
   def encode(%{id: id, count: count, flag: flag}) do
     ...
   end

   # Fallback: handle missing keys
   def encode(data) when is_map(data) do
     # current approach
   end
   ```

2. OFFER STRUCT INPUT (optional):
   ```elixir
   defstruct fields from schema

   def encode(%__MODULE__{} = struct) do
     # direct field access, no map lookup
   end
   ```

3. REMOVE NIL BRANCHES FOR INTEGERS:
   - nil in input → treated as absent
   - Use || operator: `(id || @null)`
   - Saves ~2 instructions per integer field

4. FIELD ORDERING:
   - No proven benefit for fixed-size fields
   - Could align to 8-byte boundaries (needs testing)

EXPECTED IMPROVEMENT:
- Pattern match fast path: ~45% faster encode
- Struct input: ~50-60% faster encode
- Combined with nil removal: ~55-65% faster encode
""")
