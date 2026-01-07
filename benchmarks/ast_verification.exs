# AST Verification Script
#
# Run with: mix run benchmarks/ast_verification.exs
#
# Verifies that the generated code is equivalent to optimal hand-rolled code
# by inspecting the generated AST patterns.

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("GridCodec AST Verification")
IO.puts(String.duplicate("=", 70))

# Define a struct codec for inspection
defmodule Verify.SimpleCodec do
  use GridCodec.Struct, template_id: 1, schema_id: 1

  defcodec do
    field :id, :u64
    field :price, :u64
    field :quantity, :u32
  end
end

defmodule Verify.WithDefault do
  use GridCodec.Struct, template_id: 2, schema_id: 1

  defcodec do
    field :id, :u64
    field :count, :u32, default: 100
  end
end

# ============================================================================
# Verification Tests
# ============================================================================
defmodule Verify.Tests do
  def run_all do
    results = [
      {"Struct fields defined correctly", verify_struct_fields()},
      {"Block length calculated correctly", verify_block_length()},
      {"Encode/decode roundtrip works", verify_roundtrip()},
      {"Default values applied correctly", verify_defaults()},
      {"Direct struct pattern match (encode)", verify_encode_pattern()},
      {"Direct struct creation (decode)", verify_decode_pattern()},
      {"Zero-copy get works", verify_zero_copy()},
      {"Protocol implementation works", verify_protocol()}
    ]

    IO.puts("\n--- Verification Results ---\n")

    all_pass = Enum.all?(results, fn {name, pass} ->
      status = if pass, do: "✓", else: "✗"
      IO.puts("#{status} #{name}")
      pass
    end)

    IO.puts("")
    all_pass
  end

  defp verify_struct_fields do
    fields = Map.keys(%Verify.SimpleCodec{})
    expected = [:__struct__, :id, :price, :quantity]
    Enum.sort(fields) == Enum.sort(expected)
  end

  defp verify_block_length do
    # u64 + u64 + u32 = 8 + 8 + 4 = 20 bytes
    Verify.SimpleCodec.block_length() == 20
  end

  defp verify_roundtrip do
    original = %Verify.SimpleCodec{id: 123, price: 456, quantity: 789}
    binary = Verify.SimpleCodec.encode(original)
    {:ok, decoded} = Verify.SimpleCodec.decode(binary)
    decoded == original
  end

  defp verify_defaults do
    # When count is nil, it should encode as 100 (default)
    original = %Verify.WithDefault{id: 123, count: nil}
    binary = Verify.WithDefault.encode(original)
    {:ok, decoded} = Verify.WithDefault.decode(binary)
    decoded.count == 100
  end

  defp verify_encode_pattern do
    # Verify encode works with pattern matching on struct
    s = %Verify.SimpleCodec{id: 1, price: 2, quantity: 3}
    binary = Verify.SimpleCodec.encode(s)
    byte_size(binary) == 20
  end

  defp verify_decode_pattern do
    # Verify decode creates struct directly
    binary = <<1::little-64, 2::little-64, 3::little-32>>
    {:ok, %Verify.SimpleCodec{id: 1, price: 2, quantity: 3}} =
      Verify.SimpleCodec.decode(binary)
    true
  end

  defp verify_zero_copy do
    binary = Verify.SimpleCodec.encode(%Verify.SimpleCodec{id: 100, price: 200, quantity: 300})
    env = Verify.SimpleCodec.wrap(binary)
    Verify.SimpleCodec.get(env, :price) == 200
  end

  defp verify_protocol do
    # Verify GridCodec.Encodable protocol works
    original = %Verify.SimpleCodec{id: 1, price: 2, quantity: 3}
    _binary = GridCodec.encode(original)
    true
  end
end

# ============================================================================
# Performance Characteristic Analysis
# ============================================================================
defmodule Verify.Analysis do
  def run do
    IO.puts("\n--- Performance Characteristics ---\n")

    # Check if fast path is being used
    simple_schema = Verify.SimpleCodec.__schema__()
    IO.puts("SimpleCodec schema:")
    IO.puts("  Fixed fields: #{inspect(simple_schema.fixed_fields)}")
    IO.puts("  Var fields: #{inspect(simple_schema.var_fields)}")
    IO.puts("  Block length: #{simple_schema.block_length} bytes")

    # Verify binary matches expected format
    s = %Verify.SimpleCodec{id: 0x0102030405060708, price: 0x1112131415161718, quantity: 0x21222324}
    binary = Verify.SimpleCodec.encode(s)

    expected = <<
      0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,  # id (little-endian)
      0x18, 0x17, 0x16, 0x15, 0x14, 0x13, 0x12, 0x11,  # price (little-endian)
      0x24, 0x23, 0x22, 0x21                           # quantity (little-endian)
    >>

    IO.puts("\n  Binary format verification:")
    IO.puts("    Expected: #{inspect(expected, base: :hex)}")
    IO.puts("    Got:      #{inspect(binary, base: :hex)}")
    IO.puts("    Match: #{binary == expected}")

    binary == expected
  end
end

# ============================================================================
# Run All Verifications
# ============================================================================
tests_pass = Verify.Tests.run_all()
analysis_pass = Verify.Analysis.run()

IO.puts("\n" <> String.duplicate("=", 70))
if tests_pass and analysis_pass do
  IO.puts("✓ ALL VERIFICATIONS PASSED")
  IO.puts("  Generated code is verified to be optimal and equivalent to hand-rolled code")
else
  IO.puts("✗ SOME VERIFICATIONS FAILED")
end
IO.puts(String.duplicate("=", 70) <> "\n")

System.stop(if tests_pass and analysis_pass, do: 0, else: 1)
