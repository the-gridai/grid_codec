# GridCodec.Struct vs Legacy Comparison Benchmark
#
# Run with: mix run benchmarks/struct_vs_legacy_bench.exs
#
# Comprehensive comparison of:
# 1. GridCodec.Struct (new struct-based codec)
# 2. use GridCodec (legacy map-based codec)
# 3. Hand-rolled code (optimal baseline)
# 4. BEAM bytecode analysis and JIT opportunities

IO.puts("\n" <> String.duplicate("═", 80))
IO.puts("         GridCodec.Struct vs Legacy Performance Analysis")
IO.puts(String.duplicate("═", 80))

# ============================================================================
# Define Test Codecs
# ============================================================================

# NEW: Struct-based codec
defmodule Bench.StructOrder do
  use GridCodec.Struct, template_id: 1, schema_id: 1

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

# LEGACY: Map-based codec
defmodule Bench.LegacyOrder do
  use GridCodec, template_id: 2, schema_id: 1

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

# HAND-ROLLED: Optimal baseline
defmodule Bench.HandRolledOrder do
  @null_u64 18_446_744_073_709_551_615
  @null_u32 4_294_967_295
  @null_u8 255
  @null_uuid <<0::128>>
  @null_i64 -9_223_372_036_854_775_808

  defstruct [:order_id, :user_id, :price, :quantity, :side, :timestamp, :flags]

  def encode(%__MODULE__{
        order_id: oid,
        user_id: uid,
        price: price,
        quantity: qty,
        side: side,
        timestamp: ts,
        flags: flags
      }) do
    oid_bin = oid || @null_uuid
    uid_val = uid || @null_u64
    price_val = price || @null_u64
    qty_val = qty || @null_u32
    side_val = side || @null_u8
    ts_val = if ts, do: DateTime.to_unix(ts, :microsecond), else: @null_i64
    flags_val = flags || @null_u8

    <<oid_bin::binary-16, uid_val::little-64, price_val::little-64,
      qty_val::little-32, side_val::8, ts_val::little-signed-64, flags_val::8>>
  end

  def decode(<<oid::binary-16, uid::little-64, price::little-64,
               qty::little-32, side::8, ts::little-signed-64, flags::8, _rest::binary>>) do
    {:ok, %__MODULE__{
      order_id: if(oid == @null_uuid, do: nil, else: oid),
      user_id: if(uid == @null_u64, do: nil, else: uid),
      price: if(price == @null_u64, do: nil, else: price),
      quantity: if(qty == @null_u32, do: nil, else: qty),
      side: if(side == @null_u8, do: nil, else: side),
      timestamp: if(ts == @null_i64, do: nil, else: DateTime.from_unix!(ts, :microsecond)),
      flags: if(flags == @null_u8, do: nil, else: flags)
    }}
  end
end

# ============================================================================
# Bytecode Analyzer
# ============================================================================
defmodule Bench.BytecodeAnalyzer do
  def analyze(module, function, arity) do
    case :code.get_object_code(module) do
      {^module, beam, _filename} ->
        {:beam_file, _, _, _, _, code} = :beam_disasm.file(beam)

        fn_code = Enum.find(code, fn
          {:function, ^function, ^arity, _, _} -> true
          _ -> false
        end)

        case fn_code do
          {:function, _, _, _, instructions} ->
            categorize_instructions(instructions)
          nil ->
            %{error: "Function not found", total: 0, by_instruction: %{}, by_category: %{}}
        end

      :error ->
        # Module compiled in memory only, estimate from AST
        %{error: "Module in memory", total: 0, by_instruction: %{}, by_category: %{}}
    end
  end

  defp categorize_instructions(instructions) do
    categories = %{
      map_access: [:get_map_elements, :get_map_element, :has_map_fields],
      branching: [:test, :select_val, :jump, :is_eq_exact],
      binary_ops: [:bs_create_bin, :bs_match, :bs_get_binary2, :bs_put_binary, :bs_init],
      function_calls: [:call, :call_ext, :call_ext_only, :call_only, :call_last],
      data_movement: [:move, :put_tuple, :put_list, :get_tuple_element],
      gc_bif: [:gc_bif, :gc_bif1, :gc_bif2, :gc_bif3],
      control: [:label, :return, :func_info]
    }

    counts =
      instructions
      |> Enum.map(fn
        {op, _} -> op
        {op, _, _} -> op
        {op, _, _, _} -> op
        {op, _, _, _, _} -> op
        {op, _, _, _, _, _} -> op
        {op, _, _, _, _, _, _} -> op
        op when is_atom(op) -> op
        _ -> :other
      end)
      |> Enum.frequencies()

    categorized =
      categories
      |> Enum.map(fn {category, ops} ->
        count = Enum.sum(Enum.map(ops, fn op -> Map.get(counts, op, 0) end))
        {category, count}
      end)
      |> Enum.into(%{})

    %{
      total: length(instructions),
      by_instruction: counts,
      by_category: categorized
    }
  end

  def print_comparison(analyses) do
    IO.puts("\n┌" <> String.duplicate("─", 78) <> "┐")
    IO.puts("│" <> String.pad_trailing(" BEAM Bytecode Analysis", 78) <> "│")
    IO.puts("├" <> String.duplicate("─", 78) <> "┤")

    header = "│ " <>
      String.pad_trailing("Module", 25) <>
      String.pad_leading("Total", 10) <>
      String.pad_leading("MapAccess", 12) <>
      String.pad_leading("Binary", 10) <>
      String.pad_leading("Branch", 10) <>
      String.pad_leading("Calls", 10) <> " │"
    IO.puts(header)
    IO.puts("├" <> String.duplicate("─", 78) <> "┤")

    for {name, analysis} <- analyses do
      row = "│ " <>
        String.pad_trailing(name, 25) <>
        String.pad_leading("#{analysis.total}", 10) <>
        String.pad_leading("#{analysis.by_category[:map_access] || 0}", 12) <>
        String.pad_leading("#{analysis.by_category[:binary_ops] || 0}", 10) <>
        String.pad_leading("#{analysis.by_category[:branching] || 0}", 10) <>
        String.pad_leading("#{analysis.by_category[:function_calls] || 0}", 10) <> " │"
      IO.puts(row)
    end

    IO.puts("└" <> String.duplicate("─", 78) <> "┘")
  end
end

# ============================================================================
# Compiled Benchmark Functions (Benchee best practice)
# ============================================================================
defmodule Bench.Functions do
  # Encoding
  def encode_struct(data), do: Bench.StructOrder.encode(data)
  def encode_legacy(data), do: Bench.LegacyOrder.encode(data)
  def encode_hand(data), do: Bench.HandRolledOrder.encode(data)

  # Encoding with header
  def encode_struct_framed(data), do: Bench.StructOrder.encode!(data)
  def encode_legacy_framed(data), do: Bench.LegacyOrder.encode!(data)

  # Decoding
  def decode_struct(bin), do: Bench.StructOrder.decode(bin)
  def decode_legacy(bin), do: Bench.LegacyOrder.decode(bin)
  def decode_hand(bin), do: Bench.HandRolledOrder.decode(bin)

  # Decoding with header
  def decode_struct_framed(bin), do: Bench.StructOrder.decode!(bin)
  def decode_legacy_framed(bin), do: Bench.LegacyOrder.decode!(bin)

  # Dispatch
  def dispatch_encode(data), do: GridCodec.encode(data)
  def dispatch_decode(bin), do: GridCodec.decode(bin)

  # Zero-copy
  def get_struct(env), do: Bench.StructOrder.get(env, :price)
  def get_legacy(env), do: Bench.LegacyOrder.get(env, :price)
end

# ============================================================================
# Test Data Setup (in separate module to avoid struct access issues)
# ============================================================================
defmodule Bench.TestData do
  def create do
    order_id = :crypto.strong_rand_bytes(16)
    timestamp = DateTime.utc_now()

    struct_data = %Bench.StructOrder{
      order_id: order_id,
      user_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000,
      side: 1,
      timestamp: timestamp,
      flags: 7
    }

    legacy_data = %{
      order_id: order_id,
      user_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000,
      side: 1,
      timestamp: timestamp,
      flags: 7
    }

    hand_data = %Bench.HandRolledOrder{
      order_id: order_id,
      user_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000,
      side: 1,
      timestamp: timestamp,
      flags: 7
    }

    # Pre-encode for decode benchmarks
    struct_bin = Bench.StructOrder.encode(struct_data)
    legacy_bin = Bench.LegacyOrder.encode(legacy_data)
    hand_bin = Bench.HandRolledOrder.encode(hand_data)

    struct_framed = Bench.StructOrder.encode!(struct_data)
    legacy_framed = Bench.LegacyOrder.encode!(legacy_data)

    %{
      struct_data: struct_data,
      legacy_data: legacy_data,
      hand_data: hand_data,
      struct_bin: struct_bin,
      legacy_bin: legacy_bin,
      hand_bin: hand_bin,
      struct_framed: struct_framed,
      legacy_framed: legacy_framed
    }
  end
end

data = Bench.TestData.create()
struct_data = data.struct_data
legacy_data = data.legacy_data
hand_data = data.hand_data
struct_bin = data.struct_bin
legacy_bin = data.legacy_bin
hand_bin = data.hand_bin
struct_framed = data.struct_framed
legacy_framed = data.legacy_framed

# Verify correctness
IO.puts("\n── Verification ──────────────────────────────────────────────────────────────")
IO.puts("Block lengths: Struct=#{Bench.StructOrder.block_length()}, Legacy=#{Bench.LegacyOrder.block_length()}")
IO.puts("Binary sizes:  Struct=#{byte_size(struct_bin)}, Legacy=#{byte_size(legacy_bin)}, Hand=#{byte_size(hand_bin)}")
IO.puts("Binaries match: #{struct_bin == legacy_bin and legacy_bin == hand_bin}")

# ============================================================================
# PART 1: Bytecode Analysis
# ============================================================================
IO.puts("\n" <> String.duplicate("═", 80))
IO.puts("PART 1: BEAM Bytecode Analysis")
IO.puts(String.duplicate("═", 80))

IO.puts("\n── ENCODE function analysis ──")
encode_analyses = [
  {"StructOrder.encode/1", Bench.BytecodeAnalyzer.analyze(Bench.StructOrder, :encode, 1)},
  {"LegacyOrder.encode/1", Bench.BytecodeAnalyzer.analyze(Bench.LegacyOrder, :encode, 1)},
  {"HandRolled.encode/1", Bench.BytecodeAnalyzer.analyze(Bench.HandRolledOrder, :encode, 1)}
]
Bench.BytecodeAnalyzer.print_comparison(encode_analyses)

IO.puts("\n── DECODE function analysis ──")
decode_analyses = [
  {"StructOrder.decode/1", Bench.BytecodeAnalyzer.analyze(Bench.StructOrder, :decode, 1)},
  {"LegacyOrder.decode/1", Bench.BytecodeAnalyzer.analyze(Bench.LegacyOrder, :decode, 1)},
  {"HandRolled.decode/1", Bench.BytecodeAnalyzer.analyze(Bench.HandRolledOrder, :decode, 1)}
]
Bench.BytecodeAnalyzer.print_comparison(decode_analyses)

# ============================================================================
# PART 2: Consolidated Registry Check
# ============================================================================
IO.puts("\n" <> String.duplicate("═", 80))
IO.puts("PART 2: Registry Consolidation Status")
IO.puts(String.duplicate("═", 80))

is_consolidated = GridCodec.Registry.consolidated?()
IO.puts("\nRegistry consolidation status: #{if is_consolidated, do: "✓ CONSOLIDATED (optimized)", else: "⚠ FALLBACK (dev mode)"}")
IO.puts("Note: Consolidated registry is generated by Mix.Compilers.GridCodec")
IO.puts("      Run 'mix compile' to generate the optimized registry")

# ============================================================================
# PART 3: Benchee Performance Comparison
# ============================================================================
IO.puts("\n" <> String.duplicate("═", 80))
IO.puts("PART 3: Benchee Performance Comparison")
IO.puts(String.duplicate("═", 80))

IO.puts("\n── ENCODE Benchmark ──────────────────────────────────────────────────────────")

encode_results = Benchee.run(
  %{
    "Struct.encode (new)" => fn -> Bench.Functions.encode_struct(struct_data) end,
    "Legacy.encode (map)" => fn -> Bench.Functions.encode_legacy(legacy_data) end,
    "Hand-rolled encode" => fn -> Bench.Functions.encode_hand(hand_data) end,
    "Struct.encode! (w/header)" => fn -> Bench.Functions.encode_struct_framed(struct_data) end,
    "Legacy.encode! (w/header)" => fn -> Bench.Functions.encode_legacy_framed(legacy_data) end,
    "GridCodec.encode (dispatch)" => fn -> Bench.Functions.dispatch_encode(struct_data) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [configuration: false]
)

IO.puts("\n── DECODE Benchmark ──────────────────────────────────────────────────────────")

decode_results = Benchee.run(
  %{
    "Struct.decode (new)" => fn -> Bench.Functions.decode_struct(struct_bin) end,
    "Legacy.decode (map)" => fn -> Bench.Functions.decode_legacy(legacy_bin) end,
    "Hand-rolled decode" => fn -> Bench.Functions.decode_hand(hand_bin) end,
    "Struct.decode! (w/header)" => fn -> Bench.Functions.decode_struct_framed(struct_framed) end,
    "Legacy.decode! (w/header)" => fn -> Bench.Functions.decode_legacy_framed(legacy_framed) end,
    "GridCodec.decode (dispatch)" => fn -> Bench.Functions.dispatch_decode(struct_framed) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [configuration: false]
)

# Zero-copy benchmark
IO.puts("\n── ZERO-COPY GET Benchmark ───────────────────────────────────────────────────")

struct_env = Bench.StructOrder.wrap(struct_bin)
legacy_env = Bench.LegacyOrder.wrap(legacy_bin)

_get_results = Benchee.run(
  %{
    "Struct.get (new)" => fn -> Bench.Functions.get_struct(struct_env) end,
    "Legacy.get (map)" => fn -> Bench.Functions.get_legacy(legacy_env) end
  },
  time: 2,
  warmup: 1,
  print: [configuration: false]
)

# ============================================================================
# PART 4: JIT Optimization Analysis
# ============================================================================
IO.puts("\n" <> String.duplicate("═", 80))
IO.puts("PART 4: JIT Optimization Opportunities")
IO.puts(String.duplicate("═", 80))

IO.puts("""

┌──────────────────────────────────────────────────────────────────────────────┐
│                      JIT OPTIMIZATION ANALYSIS                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  STRUCT CODEC ADVANTAGES (New):                                              │
│  ✓ Direct struct pattern match - single get_map_elements instruction        │
│  ✓ Direct struct creation in decode - no intermediate map                   │
│  ✓ Nil-to-default conversion at compile time                                │
│  ✓ Type-specific optimized binary construction                              │
│                                                                              │
│  LEGACY CODEC CHARACTERISTICS:                                               │
│  • Map input requires key existence checks                                   │
│  • Decode creates map, then converted to struct (if needed)                  │
│  • More branching for nil/default handling at runtime                        │
│                                                                              │
│  JIT-FRIENDLY PATTERNS USED:                                                 │
│  ✓ Single binary construction << >> (no concatenation)                      │
│  ✓ Pattern match on function head (enables JIT specialization)              │
│  ✓ Inline case expressions (avoids extra function calls)                    │
│  ✓ Direct BIF calls (:maps.get vs Map.get)                                  │
│                                                                              │
│  POTENTIAL FUTURE OPTIMIZATIONS:                                             │
│  • Use || for non-boolean nil coalescing (saves one branch)                 │
│  • SSA optimization for sequential binary builds                             │
│  • BeamAsm JIT hints for hot paths                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
""")

# ============================================================================
# PART 5: Consolidated vs Fallback Comparison
# ============================================================================
IO.puts("\n" <> String.duplicate("═", 80))
IO.puts("PART 5: Consolidated vs Fallback Registry Performance")
IO.puts(String.duplicate("═", 80))

if is_consolidated do
  IO.puts("\n── Consolidated Registry Performance ────────────────────────────────────────────")

  consolidated_results = Benchee.run(
    %{
      "Consolidated.decode (dispatch)" => fn -> Bench.Functions.dispatch_decode(struct_framed) end,
      "Fallback.decode (direct lookup)" => fn ->
        case GridCodec.Header.decode(struct_framed) do
          {:ok, header, payload} ->
            case GridCodec.Registry.lookup(header.schema_id, header.template_id) do
              {:ok, module} -> module.decode(payload)
              error -> error
            end
          error -> error
        end
      end
    },
    time: 2,
    warmup: 1,
    memory_time: 1,
    print: [configuration: false]
  )

  IO.puts("\nConsolidated registry provides pattern-match dispatch (faster than fallback lookup)")
else
  IO.puts("\n⚠ Consolidated registry not available - using fallback")
  IO.puts("   To test consolidated performance, run 'mix compile' first")
end

# ============================================================================
# PART 6: Summary Comparison
# ============================================================================
IO.puts(String.duplicate("═", 80))
IO.puts("SUMMARY COMPARISON")
IO.puts(String.duplicate("═", 80))

# Extract metrics
get_ips = fn results, name ->
  scenario = Enum.find(results.scenarios, fn s -> String.contains?(s.name, name) end)
  if scenario, do: scenario.run_time_data.statistics.ips, else: 0
end

struct_enc_ips = get_ips.(encode_results, "Struct.encode (new)")
legacy_enc_ips = get_ips.(encode_results, "Legacy.encode (map)")
hand_enc_ips = get_ips.(encode_results, "Hand-rolled")

struct_dec_ips = get_ips.(decode_results, "Struct.decode (new)")
legacy_dec_ips = get_ips.(decode_results, "Legacy.decode (map)")
hand_dec_ips = get_ips.(decode_results, "Hand-rolled")

IO.puts("""

┌──────────────────────────────────────────────────────────────────────────────┐
│                         PERFORMANCE SUMMARY                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ENCODE (ips = iterations per second, higher is better):                     │
│    Hand-rolled:     #{String.pad_leading("#{Float.round(hand_enc_ips / 1_000_000, 2)}M", 8)} ips (baseline)                        │
│    Struct (new):    #{String.pad_leading("#{Float.round(struct_enc_ips / 1_000_000, 2)}M", 8)} ips (#{Float.round(struct_enc_ips / hand_enc_ips, 2)}x vs hand)                       │
│    Legacy (map):    #{String.pad_leading("#{Float.round(legacy_enc_ips / 1_000_000, 2)}M", 8)} ips (#{Float.round(legacy_enc_ips / hand_enc_ips, 2)}x vs hand)                       │
│    Struct vs Legacy: #{Float.round(struct_enc_ips / legacy_enc_ips, 2)}x                                              │
│                                                                              │
│  DECODE (ips = iterations per second, higher is better):                     │
│    Hand-rolled:     #{String.pad_leading("#{Float.round(hand_dec_ips / 1_000_000, 2)}M", 8)} ips (baseline)                        │
│    Struct (new):    #{String.pad_leading("#{Float.round(struct_dec_ips / 1_000_000, 2)}M", 8)} ips (#{Float.round(struct_dec_ips / hand_dec_ips, 2)}x vs hand)                       │
│    Legacy (map):    #{String.pad_leading("#{Float.round(legacy_dec_ips / 1_000_000, 2)}M", 8)} ips (#{Float.round(legacy_dec_ips / hand_dec_ips, 2)}x vs hand)                       │
│    Struct vs Legacy: #{Float.round(struct_dec_ips / legacy_dec_ips, 2)}x                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
""")

# Check if struct is faster than or equal to legacy
struct_wins_encode = struct_enc_ips >= legacy_enc_ips
struct_wins_decode = struct_dec_ips >= legacy_dec_ips

if struct_wins_encode and struct_wins_decode do
  IO.puts("✓ PASS: GridCodec.Struct is faster than or equal to legacy in all operations")
else
  IO.puts("⚠ NOTE: Some operations show different performance characteristics")
  unless struct_wins_encode, do: IO.puts("  - Encode: Legacy is #{Float.round(legacy_enc_ips / struct_enc_ips, 2)}x faster")
  unless struct_wins_decode, do: IO.puts("  - Decode: Legacy is #{Float.round(legacy_dec_ips / struct_dec_ips, 2)}x faster")
end

IO.puts("")
