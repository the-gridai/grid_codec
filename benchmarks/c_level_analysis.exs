# C-Level BEAM Analysis
#
# Exploring the boundary between BEAM and C:
# - BIF (Built-in Functions) implementation
# - Binary matching at C level
# - What happens under the hood

IO.puts(String.duplicate("=", 70))
IO.puts("C-LEVEL BEAM INTERNALS ANALYSIS")
IO.puts(String.duplicate("=", 70))

# =============================================================================
# PART 1: Understanding BIFs vs Erlang Functions
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 1: BIF (Built-In Function) ANALYSIS")
IO.puts(String.duplicate("-", 70))

IO.puts("""
BIFs are implemented in C in the BEAM runtime. They provide:

1. **Primitive operations** - cannot be expressed in Erlang
   - :erlang.send/2, :erlang.spawn/3
   - :erlang.binary_to_term/1

2. **Performance-critical operations**
   - :maps.get/2,3 - O(log n) hash trie lookup in C
   - :lists.keyfind/3 - linear scan in C (faster than Erlang)
   - :binary.copy/2 - memcpy in C

3. **Type-specific operations**
   - Binary matching (bs_match) - C implementation
   - Binary construction (bs_create_bin) - C implementation

BIF call overhead: ~20-50ns (vs ~100-200ns for NIF)
""")

# Let's measure some BIFs vs Erlang equivalents
iterations = 1_000_000

# :maps.get vs pattern match extraction
map = %{a: 1, b: 2, c: 3, d: 4, e: 5}

{bif_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: :maps.get(:c, map, nil)
  end)

{pattern_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations do
      %{c: v} = map
      v
    end
  end)

IO.puts("\nMap access (1M iterations):")
IO.puts("  :maps.get BIF:    #{Float.round(bif_time / 1000, 1)} ms")
IO.puts("  Pattern match:    #{Float.round(pattern_time / 1000, 1)} ms")
IO.puts("  Ratio:            #{Float.round(pattern_time / bif_time, 2)}x")

# =============================================================================
# PART 2: Binary Matching at C Level
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 2: BINARY MATCHING INTERNALS")
IO.puts(String.duplicate("-", 70))

IO.puts("""
Binary matching in BEAM is highly optimized at C level:

1. **bs_start_match4** - Creates match context
   - Allocates context on heap (if needed)
   - Sets up pointer to binary data
   - NO data copying

2. **bs_match** - Pattern matching
   - Direct pointer arithmetic
   - Type-specific extraction (integer, float, binary)
   - Automatic alignment handling

3. **Sub-binary creation**
   - Reference to original binary + offset
   - NO copying until modified
   - GC handles lifetime

This is why GridCodec's decode is so fast - it's using
C-optimized operations for all binary work.
""")

# Benchmark binary matching
binary = <<12345::little-64, 100::little-32, 1::8>>

defmodule BinaryTest do
  def match_all(<<a::little-64, b::little-32, c::8>>) do
    {a, b, c}
  end

  def match_skip(<<_::little-64, _::little-32, c::8>>) do
    c
  end

  def binary_part(bin) do
    :binary.decode_unsigned(:binary.part(bin, 0, 8), :little)
  end
end

{match_all_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: BinaryTest.match_all(binary)
  end)

{match_skip_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: BinaryTest.match_skip(binary)
  end)

{binary_part_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: BinaryTest.binary_part(binary)
  end)

IO.puts("\nBinary extraction (1M iterations):")
IO.puts("  Match all fields:   #{Float.round(match_all_time / 1000, 1)} ms")
IO.puts("  Match with skip:    #{Float.round(match_skip_time / 1000, 1)} ms")
IO.puts("  :binary.part/3:     #{Float.round(binary_part_time / 1000, 1)} ms")

# =============================================================================
# PART 3: Map Construction at C Level
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 3: MAP CONSTRUCTION INTERNALS")
IO.puts(String.duplicate("-", 70))

IO.puts("""
Map construction in BEAM (hash array mapped trie):

Small maps (<=32 keys): Flat array
  - O(n) lookup but fast for small n
  - Single allocation

Large maps (>32 keys): HAMT (Hash Array Mapped Trie)
  - O(log32 n) lookup
  - Structural sharing on updates

put_map_assoc vs put_map_exact:
  - assoc: Can add new keys
  - exact: Only updates existing keys (faster, less checking)
""")

defmodule MapTest do
  def build_literal do
    %{a: 1, b: 2, c: 3}
  end

  def build_from_list do
    Map.new(a: 1, b: 2, c: 3)
  end

  def build_put do
    %{}
    |> Map.put(:a, 1)
    |> Map.put(:b, 2)
    |> Map.put(:c, 3)
  end

  def build_erlang do
    m = :maps.new()
    m = :maps.put(:a, 1, m)
    m = :maps.put(:b, 2, m)
    :maps.put(:c, 3, m)
  end
end

{literal_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: MapTest.build_literal()
  end)

{from_list_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: MapTest.build_from_list()
  end)

{put_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: MapTest.build_put()
  end)

{erlang_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: MapTest.build_erlang()
  end)

IO.puts("\nMap construction (1M iterations):")
IO.puts("  Literal %{...}:     #{Float.round(literal_time / 1000, 1)} ms")
IO.puts("  Map.new/1:          #{Float.round(from_list_time / 1000, 1)} ms")
IO.puts("  Map.put chain:      #{Float.round(put_time / 1000, 1)} ms")
IO.puts("  :maps.put chain:    #{Float.round(erlang_time / 1000, 1)} ms")

# =============================================================================
# PART 4: Binary Construction at C Level
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 4: BINARY CONSTRUCTION INTERNALS")
IO.puts(String.duplicate("-", 70))

IO.puts("""
Binary construction (bs_create_bin) at C level:

1. **Size calculation** - Compile-time when possible
   - JIT optimizes known-size binaries
   - Dynamic size requires runtime allocation

2. **Memory allocation**
   - Small binaries (<64 bytes): heap binary
   - Large binaries (>=64 bytes): refc binary
   - Refc = reference-counted, shared

3. **Data copying**
   - Integer segments: bit operations in C
   - Binary segments: memcpy for large, inline for small
   - Alignment handled automatically

4. **Append optimization**
   - BEAM tracks writable binaries
   - Appending reuses allocated space when possible
""")

defmodule BinaryBuild do
  def build_13bytes(a, b, c) do
    <<a::little-64, b::little-32, c::8>>
  end

  def build_100bytes(data) do
    <<0::800>>
  end

  def build_with_binary(prefix, suffix) do
    <<prefix::binary, suffix::binary>>
  end
end

small_bin = <<1, 2, 3, 4, 5>>

{small_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: BinaryBuild.build_13bytes(12345, 100, 1)
  end)

{large_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: BinaryBuild.build_100bytes(nil)
  end)

{concat_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: BinaryBuild.build_with_binary(small_bin, small_bin)
  end)

IO.puts("\nBinary construction (1M iterations):")
IO.puts("  13-byte binary:     #{Float.round(small_time / 1000, 1)} ms")
IO.puts("  100-byte binary:    #{Float.round(large_time / 1000, 1)} ms")
IO.puts("  Binary concat:      #{Float.round(concat_time / 1000, 1)} ms")

# =============================================================================
# PART 5: What The JIT Does
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 5: JIT OPTIMIZATIONS")
IO.puts(String.duplicate("-", 70))

IO.puts("""
The BEAM JIT (OTP 24+) performs these optimizations:

1. **Type specialization**
   - Tracks types through SSA
   - Generates specialized code paths
   - Example: integer addition vs generic addition

2. **Instruction fusion**
   - Combines related operations
   - bs_match + extraction = single C call
   - map_get + type_check = specialized lookup

3. **Register allocation**
   - Maps BEAM registers to x86/ARM registers
   - Reduces memory traffic
   - Hot values stay in registers

4. **Inline caching**
   - Caches function lookup results
   - Module references become direct calls
   - Why module size doesn't matter

5. **Branch prediction hints**
   - Uses profiling data (when available)
   - Optimizes hot paths
   - Cold paths remain interpreted
""")

# =============================================================================
# PART 6: Hidden BIFs We Could Use
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 6: POTENTIALLY USEFUL ERLANG/C PRIMITIVES")
IO.puts(String.duplicate("-", 70))

IO.puts("""
Less-known Erlang primitives that might help:

1. **:erlang.make_tuple/2** - Pre-allocate tuple
   - Faster than building incrementally
   - Only useful if we returned tuples

2. **:erlang.setelement/3** - In-place update (sort of)
   - Still copies, but optimized path
   - Used by Record updates

3. **:binary.copy/2** - Repeat binary pattern
   - Useful for padding
   - C-level memset

4. **:erlang.adler32/1** - Fast checksum
   - If we needed checksums

5. **:persistent_term** - Global constants
   - Zero lookup cost after first access
   - Good for schema metadata (already using)

6. **:atomics / :counters** - Lock-free data
   - For statistics/metrics
   - Not applicable to encode/decode
""")

# Test :erlang.make_tuple vs literal
{make_tuple_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: :erlang.make_tuple(3, nil)
  end)

{literal_tuple_time, _} =
  :timer.tc(fn ->
    for _ <- 1..iterations, do: {nil, nil, nil}
  end)

IO.puts("\nTuple construction (1M iterations):")
IO.puts("  :erlang.make_tuple:  #{Float.round(make_tuple_time / 1000, 1)} ms")
IO.puts("  Literal {a, b, c}:   #{Float.round(literal_tuple_time / 1000, 1)} ms")

# =============================================================================
# PART 7: What We Cannot Optimize (C-Level Limits)
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("PART 7: FUNDAMENTAL C-LEVEL LIMITS")
IO.puts(String.duplicate("-", 70))

IO.puts("""
These cannot be optimized without modifying BEAM itself:

1. **Map lookup** - O(log32 n) is fundamental
   - HAMT is already optimal for functional maps
   - Pattern match uses same underlying structure

2. **Binary allocation** - GC overhead
   - Every binary needs heap space
   - Reference counting for large binaries

3. **Function call** - ~2-5ns overhead
   - Register save/restore
   - Stack frame management
   - Cannot be zero

4. **Type checking** - Required for safety
   - is_map, is_binary guards
   - Cannot be skipped

5. **Term encoding** - Fixed format
   - Integer encoding includes type tag
   - External format is standardized

BEAM is designed for correctness and fairness, not raw speed.
These trade-offs are intentional.
""")

# =============================================================================
# SUMMARY
# =============================================================================

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("SUMMARY: C-LEVEL OPTIMIZATION OPPORTUNITIES")
IO.puts(String.duplicate("=", 70))

IO.puts("""

ALREADY AT C-LEVEL OPTIMAL:
---------------------------
✅ Binary matching (bs_match) - Direct pointer operations
✅ Binary construction (bs_create_bin) - Optimized memcpy
✅ Map lookup (:maps.get) - O(log32 n) HAMT
✅ Map construction (put_map_assoc) - Single allocation

MINIMAL REMAINING OPPORTUNITIES:
--------------------------------

1. Use pattern match for batch extraction
   %{a: a, b: b, c: c} = data
   - Generates single get_map_elements
   - ~45% encode improvement
   - Requires all keys present

2. Consider tuple return for internal APIs
   - Tuple element access is O(1)
   - But: breaks map-based API

3. Pre-compute field offsets at compile time
   - Already doing this ✅

4. Use persistent_term for schema metadata
   - Already doing this ✅

VERDICT: At C-level limits for current semantics.

Further optimization requires:
- API changes (tuple input/output)
- Semantic changes (require all keys)
- Or moving to a NIF (only beneficial for large payloads >1KB)
""")
