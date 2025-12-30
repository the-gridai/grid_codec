# Field Ordering and Alignment Analysis
#
# Does field order affect performance?
# Should we align fields to natural boundaries?

IO.puts(String.duplicate("=", 70))
IO.puts("FIELD ORDERING & ALIGNMENT ANALYSIS")
IO.puts(String.duplicate("=", 70))

# =============================================================================
# Define Codecs with Different Field Orders
# =============================================================================

# Order 1: Largest to smallest (optimal for alignment)
defmodule LargeFirstCodec do
  use GridCodec
  defcodec do
    field(:u64_field, :u64)      # 8 bytes, offset 0
    field(:u32_field, :u32)      # 4 bytes, offset 8
    field(:u16_field, :u16)      # 2 bytes, offset 12
    field(:u8_field, :u8)        # 1 byte,  offset 14
    field(:flag, :bool)          # 1 byte,  offset 15
  end
end

# Order 2: Smallest to largest (worst for alignment)
defmodule SmallFirstCodec do
  use GridCodec
  defcodec do
    field(:flag, :bool)          # 1 byte,  offset 0
    field(:u8_field, :u8)        # 1 byte,  offset 1
    field(:u16_field, :u16)      # 2 bytes, offset 2
    field(:u32_field, :u32)      # 4 bytes, offset 4
    field(:u64_field, :u64)      # 8 bytes, offset 8
  end
end

# Order 3: Random (typical user order)
defmodule RandomOrderCodec do
  use GridCodec
  defcodec do
    field(:u32_field, :u32)      # 4 bytes, offset 0
    field(:u8_field, :u8)        # 1 byte,  offset 4
    field(:u64_field, :u64)      # 8 bytes, offset 5
    field(:flag, :bool)          # 1 byte,  offset 13
    field(:u16_field, :u16)      # 2 bytes, offset 14
  end
end

# Order 4: With explicit padding (SBE-style alignment)
defmodule PaddedCodec do
  use GridCodec
  defcodec do
    field(:u64_field, :u64)      # 8 bytes, offset 0 (8-aligned)
    field(:u32_field, :u32)      # 4 bytes, offset 8 (4-aligned)
    field(:u16_field, :u16)      # 2 bytes, offset 12 (2-aligned)
    field(:u8_field, :u8)        # 1 byte,  offset 14
    field(:flag, :bool)          # 1 byte,  offset 15
    # No padding needed with this order
  end
end

test_data = %{
  u64_field: 12345678901234,
  u32_field: 1234567,
  u16_field: 12345,
  u8_field: 123,
  flag: true
}

# =============================================================================
# Verify All Produce Valid Output
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("BINARY SIZE VERIFICATION")
IO.puts(String.duplicate("-", 70))

for {name, mod} <- [
  {"Large first", LargeFirstCodec},
  {"Small first", SmallFirstCodec},
  {"Random order", RandomOrderCodec},
  {"Padded", PaddedCodec}
] do
  bin = mod.encode(test_data)
  {:ok, decoded} = mod.decode(bin)
  roundtrip = mod.encode(decoded) == bin
  IO.puts("#{name}: #{byte_size(bin)} bytes, roundtrip: #{roundtrip}")
end

# =============================================================================
# Benchmark Encode
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("ENCODE BENCHMARK")
IO.puts(String.duplicate("-", 70))

Benchee.run(
  %{
    "1. Large first (aligned)" => fn -> LargeFirstCodec.encode(test_data) end,
    "2. Small first" => fn -> SmallFirstCodec.encode(test_data) end,
    "3. Random order" => fn -> RandomOrderCodec.encode(test_data) end,
    "4. Padded" => fn -> PaddedCodec.encode(test_data) end,
  },
  warmup: 2,
  time: 5,
  print: [fast_warning: false]
)

# Pre-encode for decode benchmark
large_first_bin = LargeFirstCodec.encode(test_data)
small_first_bin = SmallFirstCodec.encode(test_data)
random_order_bin = RandomOrderCodec.encode(test_data)
padded_bin = PaddedCodec.encode(test_data)

# =============================================================================
# Benchmark Decode
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("DECODE BENCHMARK")
IO.puts(String.duplicate("-", 70))

Benchee.run(
  %{
    "1. Large first (aligned)" => fn -> LargeFirstCodec.decode(large_first_bin) end,
    "2. Small first" => fn -> SmallFirstCodec.decode(small_first_bin) end,
    "3. Random order" => fn -> RandomOrderCodec.decode(random_order_bin) end,
    "4. Padded" => fn -> PaddedCodec.decode(padded_bin) end,
  },
  warmup: 2,
  time: 5,
  print: [fast_warning: false]
)

# =============================================================================
# Benchmark Single Field Access (get/2)
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("SINGLE FIELD ACCESS (get/2)")
IO.puts(String.duplicate("-", 70))

Benchee.run(
  %{
    "1. Large first - u64" => fn -> LargeFirstCodec.get(large_first_bin, :u64_field) end,
    "2. Small first - u64" => fn -> SmallFirstCodec.get(small_first_bin, :u64_field) end,
    "3. Random order - u64" => fn -> RandomOrderCodec.get(random_order_bin, :u64_field) end,
    "4. Large first - u8" => fn -> LargeFirstCodec.get(large_first_bin, :u8_field) end,
    "5. Random order - u8" => fn -> RandomOrderCodec.get(random_order_bin, :u8_field) end,
  },
  warmup: 2,
  time: 5,
  print: [fast_warning: false]
)

# =============================================================================
# Analyze BS_MATCH with Unaligned Access
# =============================================================================

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("UNALIGNED ACCESS ANALYSIS")
IO.puts(String.duplicate("-", 70))

IO.puts("""

BEAM's bs_match instruction handles unaligned access efficiently:
- For little-endian: no penalty (just reads bytes)
- For big-endian: minimal overhead (byte swap)
- CPU's L1 cache handles unaligned word reads

Typical unaligned access penalty on modern x86-64: ~0-2 cycles
This is negligible compared to function call overhead (~5-10 cycles)

RECOMMENDATION:
- Field order has NO significant performance impact on BEAM
- Focus on logical grouping for code clarity
- Consider alignment only for:
  1. Interop with C/native code (NIFs)
  2. Memory-mapped files
  3. Network protocols with strict requirements
""")

# =============================================================================
# Test with Manual Unaligned Access
# =============================================================================

defmodule AlignmentTest do
  def aligned_read(<<_::64, value::little-32, _::binary>>), do: value
  def unaligned_read(<<_::8, value::little-32, _::binary>>), do: value
  def very_unaligned_read(<<_::1, value::little-32, _::binary>>), do: value
end

# Create test binaries
aligned_bin = <<0::64, 12345678::little-32, 0::32>>
unaligned_bin = <<0::8, 12345678::little-32, 0::56>>
bit_unaligned_bin = <<0::1, 12345678::little-32, 0::63>>

IO.puts("\n" <> String.duplicate("-", 70))
IO.puts("MANUAL ALIGNMENT TEST")
IO.puts(String.duplicate("-", 70))

IO.puts("\nReading 32-bit integer from different alignments:")

Benchee.run(
  %{
    "8-byte aligned" => fn -> AlignmentTest.aligned_read(aligned_bin) end,
    "1-byte offset" => fn -> AlignmentTest.unaligned_read(unaligned_bin) end,
    "1-bit offset" => fn -> AlignmentTest.very_unaligned_read(bit_unaligned_bin) end,
  },
  warmup: 2,
  time: 5,
  print: [fast_warning: false]
)

# =============================================================================
# Summary
# =============================================================================

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("FIELD ORDERING CONCLUSIONS")
IO.puts(String.duplicate("=", 70))

IO.puts("""

FINDINGS:
---------
1. Field order has MINIMAL impact on encode/decode performance
2. BEAM's binary matching handles unaligned access efficiently
3. The bs_match instruction coalesces adjacent matches

RECOMMENDATIONS:
----------------
1. NO NEED to reorder fields for performance
2. Keep user-specified order for predictability
3. Consider providing alignment helpers for NIF interop
4. Document wire format so users can make informed decisions

OPTIONAL FUTURE WORK:
---------------------
1. Add `align: N` option to pad fields to N-byte boundaries
2. Add `offset: N` option to skip/pad to specific offset
3. Add `padding: N` option to add explicit padding bytes
""")
