defmodule GridCodec.FastPathComprehensiveTest do
  @moduledoc """
  Comprehensive tests for the fast-path encoder.

  The fast-path encoder uses pattern matching to extract all fields at once
  (single get_map_elements BEAM instruction). This test ensures it works
  correctly with ALL type combinations.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.Generators

  # ============================================================================
  # Type Definitions for Tests
  # ============================================================================

  defmodule TestEnums do
    defmodule Side do
      use GridCodec.Types.Enum, encoding: :u8

      defenum do
        value(:buy, 0)
        value(:sell, 1)
      end
    end

    defmodule Status do
      use GridCodec.Types.Enum, encoding: :u16

      defenum do
        value(:pending, 0)
        value(:active, 1)
        value(:completed, 2)
        value(:cancelled, 3)
      end
    end

    defmodule Priority do
      use GridCodec.Types.Enum, encoding: :u8

      defenum do
        value(:low)
        value(:medium)
        value(:high)
        value(:urgent)
      end
    end
  end

  defmodule TestCharArrays do
    defmodule Symbol8 do
      use GridCodec.Types.CharArray, length: 8
    end

    defmodule Code32 do
      use GridCodec.Types.CharArray, length: 32
    end
  end

  defmodule TestBitsets do
    defmodule Flags8 do
      use GridCodec.Types.Bitset, size: :u8
      flag(:a, 0)
      flag(:b, 1)
      flag(:c, 2)
      flag(:d, 3)
    end

    defmodule Flags16 do
      use GridCodec.Types.Bitset, size: :u16
      flag(:read, 0)
      flag(:write, 1)
      flag(:execute, 2)
      flag(:admin, 8)
    end
  end

  # ============================================================================
  # Test Codecs - All Fixed Types
  # ============================================================================

  describe "fast path with all integer types" do
    defmodule AllIntegersCodec do
      use GridCodec

      defcodec do
        field(:u8_val, :u8)
        field(:u16_val, :u16)
        field(:u32_val, :u32)
        field(:u64_val, :u64)
        field(:i8_val, :i8)
        field(:i16_val, :i16)
        field(:i32_val, :i32)
        field(:i64_val, :i64)
      end
    end

    property "all integer types roundtrip correctly" do
      gen =
        StreamData.fixed_map(%{
          u8_val: Generators.u8(),
          u16_val: Generators.u16(),
          u32_val: Generators.u32(),
          u64_val: Generators.u64(),
          i8_val: Generators.i8(),
          i16_val: Generators.i16(),
          i32_val: Generators.i32(),
          i64_val: Generators.i64()
        })

      check all(data <- gen, max_runs: 100) do
        binary = AllIntegersCodec.encode(data)
        {:ok, decoded} = AllIntegersCodec.decode(binary)

        assert decoded.u8_val == data.u8_val
        assert decoded.u16_val == data.u16_val
        assert decoded.u32_val == data.u32_val
        assert decoded.u64_val == data.u64_val
        assert decoded.i8_val == data.i8_val
        assert decoded.i16_val == data.i16_val
        assert decoded.i32_val == data.i32_val
        assert decoded.i64_val == data.i64_val
      end
    end

    test "block length is correct" do
      # 1 + 2 + 4 + 8 + 1 + 2 + 4 + 8 = 30
      assert AllIntegersCodec.block_length() == 30
    end
  end

  describe "fast path with float types" do
    defmodule AllFloatsCodec do
      use GridCodec

      defcodec do
        field(:f32_val, :f32)
        field(:f64_val, :f64)
      end
    end

    property "float types roundtrip correctly" do
      gen =
        StreamData.fixed_map(%{
          f32_val: Generators.f32(),
          f64_val: Generators.f64()
        })

      check all(data <- gen, max_runs: 100) do
        binary = AllFloatsCodec.encode(data)
        {:ok, decoded} = AllFloatsCodec.decode(binary)

        assert_in_delta decoded.f32_val, data.f32_val, abs(data.f32_val * 1.0e-6) + 1.0e-6
        assert_in_delta decoded.f64_val, data.f64_val, abs(data.f64_val * 1.0e-14) + 1.0e-14
      end
    end

    test "block length is correct" do
      # 4 + 8 = 12
      assert AllFloatsCodec.block_length() == 12
    end
  end

  describe "fast path with bool and uuid" do
    defmodule BoolUuidCodec do
      use GridCodec

      defcodec do
        field(:flag1, :bool)
        field(:flag2, :bool)
        field(:id, :uuid)
        field(:flag3, :bool)
      end
    end

    property "bool and uuid roundtrip correctly" do
      gen =
        StreamData.fixed_map(%{
          flag1: Generators.bool(),
          flag2: Generators.bool(),
          id: Generators.uuid(),
          flag3: Generators.bool()
        })

      check all(data <- gen, max_runs: 100) do
        binary = BoolUuidCodec.encode(data)
        {:ok, decoded} = BoolUuidCodec.decode(binary)

        assert decoded.flag1 == data.flag1
        assert decoded.flag2 == data.flag2
        assert decoded.id == data.id
        assert decoded.flag3 == data.flag3
      end
    end

    test "block length is correct" do
      # 1 + 1 + 16 + 1 = 19
      assert BoolUuidCodec.block_length() == 19
    end
  end

  describe "fast path with timestamps" do
    defmodule TimestampCodec do
      use GridCodec

      defcodec do
        field(:created_at, :timestamp_us)
        field(:updated_at, :timestamp_ns)
        field(:counter, :u32)
      end
    end

    property "timestamp types roundtrip correctly" do
      # Timestamps are i64, reuse that generator
      gen =
        StreamData.fixed_map(%{
          created_at: Generators.i64(),
          updated_at: Generators.i64(),
          counter: Generators.u32()
        })

      check all(data <- gen, max_runs: 100) do
        binary = TimestampCodec.encode(data)
        {:ok, decoded} = TimestampCodec.decode(binary)

        assert decoded.created_at == data.created_at
        assert decoded.updated_at == data.updated_at
        assert decoded.counter == data.counter
      end
    end

    test "block length is correct" do
      # 8 + 8 + 4 = 20
      assert TimestampCodec.block_length() == 20
    end
  end

  describe "fast path with decimal" do
    defmodule DecimalCodec do
      use GridCodec

      defcodec do
        field(:price, :decimal)
        field(:quantity, :u32)
        field(:total, :decimal)
      end
    end

    test "decimal codec roundtrips correctly" do
      data = %{
        price: Decimal.new("123.45"),
        quantity: 100,
        total: Decimal.new("12345.00")
      }

      binary = DecimalCodec.encode(data)
      {:ok, decoded} = DecimalCodec.decode(binary)

      assert Decimal.equal?(decoded.price, data.price)
      assert decoded.quantity == data.quantity
      assert Decimal.equal?(decoded.total, data.total)
    end

    test "decimal handles nil" do
      data = %{price: nil, quantity: 100, total: nil}
      binary = DecimalCodec.encode(data)
      {:ok, decoded} = DecimalCodec.decode(binary)

      assert decoded.price == nil
      assert decoded.quantity == 100
      assert decoded.total == nil
    end

    test "block length is correct" do
      # 9 (decimal) + 4 (u32) + 9 (decimal) = 22
      assert DecimalCodec.block_length() == 22
    end
  end

  describe "fast path with enum types" do
    defmodule EnumCodec do
      use GridCodec,
        types: [
          side: GridCodec.FastPathComprehensiveTest.TestEnums.Side,
          status: GridCodec.FastPathComprehensiveTest.TestEnums.Status,
          priority: GridCodec.FastPathComprehensiveTest.TestEnums.Priority
        ]

      defcodec do
        field(:id, :u64)
        field(:side, :side)
        field(:status, :status)
        field(:priority, :priority)
        field(:count, :u32)
      end
    end

    test "enum codec encodes and decodes correctly" do
      data = %{
        id: 12345,
        side: :buy,
        status: :active,
        priority: :high,
        count: 100
      }

      binary = EnumCodec.encode(data)
      {:ok, decoded} = EnumCodec.decode(binary)

      assert decoded.id == 12345
      assert decoded.side == :buy
      assert decoded.status == :active
      assert decoded.priority == :high
      assert decoded.count == 100
    end

    property "enum types roundtrip correctly" do
      sides = [:buy, :sell, nil]
      statuses = [:pending, :active, :completed, :cancelled, nil]
      priorities = [:low, :medium, :high, :urgent, nil]

      gen =
        StreamData.fixed_map(%{
          id: Generators.u64(),
          side: StreamData.member_of(sides),
          status: StreamData.member_of(statuses),
          priority: StreamData.member_of(priorities),
          count: Generators.u32()
        })

      check all(data <- gen, max_runs: 100) do
        binary = EnumCodec.encode(data)
        {:ok, decoded} = EnumCodec.decode(binary)

        assert decoded.id == data.id
        assert decoded.side == data.side
        assert decoded.status == data.status
        assert decoded.priority == data.priority
        assert decoded.count == data.count
      end
    end

    test "block length is correct" do
      # 8 + 1 + 2 + 1 + 4 = 16
      assert EnumCodec.block_length() == 16
    end
  end

  describe "fast path with char arrays" do
    defmodule CharArrayCodec do
      use GridCodec,
        types: [
          symbol8: GridCodec.FastPathComprehensiveTest.TestCharArrays.Symbol8,
          code32: GridCodec.FastPathComprehensiveTest.TestCharArrays.Code32
        ]

      defcodec do
        field(:code, :symbol8)
        field(:name, :code32)
        field(:id, :u64)
      end
    end

    test "char array codec encodes and decodes correctly" do
      data = %{
        code: "AAPL",
        name: "Apple Inc.",
        id: 12345
      }

      binary = CharArrayCodec.encode(data)
      {:ok, decoded} = CharArrayCodec.decode(binary)

      assert decoded.code == "AAPL"
      assert decoded.name == "Apple Inc."
      assert decoded.id == 12345
    end

    property "char array roundtrips correctly" do
      gen =
        StreamData.fixed_map(%{
          code: StreamData.string(:alphanumeric, max_length: 8),
          name: StreamData.string(:alphanumeric, max_length: 32),
          id: Generators.u64()
        })

      check all(data <- gen, max_runs: 100) do
        binary = CharArrayCodec.encode(data)
        {:ok, decoded} = CharArrayCodec.decode(binary)

        # Char arrays truncate to fit, so compare only the expected part
        assert decoded.code == String.slice(data.code, 0, 8)
        assert decoded.name == String.slice(data.name, 0, 32)
        assert decoded.id == data.id
      end
    end

    test "block length is correct" do
      # 8 + 32 + 8 = 48
      assert CharArrayCodec.block_length() == 48
    end
  end

  describe "fast path with bitset" do
    defmodule BitsetCodec do
      use GridCodec,
        types: [
          flags8: GridCodec.FastPathComprehensiveTest.TestBitsets.Flags8,
          flags16: GridCodec.FastPathComprehensiveTest.TestBitsets.Flags16
        ]

      defcodec do
        field(:flags, :flags8)
        field(:permissions, :flags16)
        field(:id, :u32)
      end
    end

    test "bitset codec encodes and decodes correctly" do
      data = %{
        flags: MapSet.new([:a, :b]),
        permissions: MapSet.new([:read, :admin]),
        id: 12345
      }

      binary = BitsetCodec.encode(data)
      {:ok, decoded} = BitsetCodec.decode(binary)

      assert MapSet.equal?(decoded.flags, MapSet.new([:a, :b]))
      assert MapSet.equal?(decoded.permissions, MapSet.new([:read, :admin]))
      assert decoded.id == 12345
    end

    test "block length is correct" do
      # 1 + 2 + 4 = 7
      assert BitsetCodec.block_length() == 7
    end
  end

  describe "fast path with kitchen sink codec" do
    defmodule KitchenSinkCodec do
      @moduledoc """
      A codec with EVERY fixed-size type to test the fast path comprehensively.
      """
      use GridCodec,
        types: [
          side: GridCodec.FastPathComprehensiveTest.TestEnums.Side,
          priority: GridCodec.FastPathComprehensiveTest.TestEnums.Priority,
          symbol: GridCodec.FastPathComprehensiveTest.TestCharArrays.Symbol8,
          flags8: GridCodec.FastPathComprehensiveTest.TestBitsets.Flags8
        ]

      defcodec do
        # Unsigned integers
        field(:u8_val, :u8)
        field(:u16_val, :u16)
        field(:u32_val, :u32)
        field(:u64_val, :u64)

        # Signed integers
        field(:i8_val, :i8)
        field(:i16_val, :i16)
        field(:i32_val, :i32)
        field(:i64_val, :i64)

        # Floats
        field(:f32_val, :f32)
        field(:f64_val, :f64)

        # Bool
        field(:flag, :bool)

        # UUID
        field(:id, :uuid)

        # Timestamps
        field(:created_at, :timestamp_us)
        field(:updated_at, :timestamp_ns)

        # Decimal
        field(:price, :decimal)

        # Enums
        field(:side, :side)
        field(:priority, :priority)

        # Char array
        field(:symbol, :symbol)

        # Bitset
        field(:flags, :flags8)
      end
    end

    test "kitchen sink codec encodes and decodes all types" do
      data = %{
        u8_val: 100,
        u16_val: 1000,
        u32_val: 100_000,
        u64_val: 10_000_000_000,
        i8_val: -50,
        i16_val: -500,
        i32_val: -50_000,
        i64_val: -5_000_000_000,
        f32_val: 3.14,
        f64_val: 2.718281828,
        flag: true,
        id: :crypto.strong_rand_bytes(16),
        created_at: System.system_time(:microsecond),
        updated_at: System.system_time(:nanosecond),
        price: Decimal.new("123.45"),
        side: :buy,
        priority: :high,
        symbol: "AAPL",
        flags: MapSet.new([:a, :c])
      }

      binary = KitchenSinkCodec.encode(data)
      {:ok, decoded} = KitchenSinkCodec.decode(binary)

      # Verify all fields
      assert decoded.u8_val == data.u8_val
      assert decoded.u16_val == data.u16_val
      assert decoded.u32_val == data.u32_val
      assert decoded.u64_val == data.u64_val
      assert decoded.i8_val == data.i8_val
      assert decoded.i16_val == data.i16_val
      assert decoded.i32_val == data.i32_val
      assert decoded.i64_val == data.i64_val
      assert_in_delta decoded.f32_val, data.f32_val, 0.001
      assert_in_delta decoded.f64_val, data.f64_val, 1.0e-10
      assert decoded.flag == data.flag
      assert decoded.id == data.id
      assert decoded.created_at == data.created_at
      assert decoded.updated_at == data.updated_at
      assert Decimal.equal?(decoded.price, data.price)
      assert decoded.side == data.side
      assert decoded.priority == data.priority
      assert decoded.symbol == data.symbol
      assert MapSet.equal?(decoded.flags, data.flags)
    end

    test "kitchen sink codec handles nil values (except floats)" do
      # Note: f32 and f64 are NOT nullable - passing nil will raise an error
      # This is intentional: use integer types with fixed-point for nullable numerics
      data = %{
        u8_val: nil,
        u16_val: nil,
        u32_val: nil,
        u64_val: nil,
        i8_val: nil,
        i16_val: nil,
        i32_val: nil,
        i64_val: nil,
        f32_val: 0.0,
        f64_val: 0.0,
        flag: nil,
        id: nil,
        created_at: nil,
        updated_at: nil,
        price: nil,
        side: nil,
        priority: nil,
        symbol: nil,
        flags: nil
      }

      binary = KitchenSinkCodec.encode(data)
      {:ok, decoded} = KitchenSinkCodec.decode(binary)

      assert decoded.u8_val == nil
      assert decoded.u16_val == nil
      assert decoded.u32_val == nil
      assert decoded.u64_val == nil
      assert decoded.i8_val == nil
      assert decoded.i16_val == nil
      assert decoded.i32_val == nil
      assert decoded.i64_val == nil
      assert_in_delta decoded.f32_val, 0.0, 0.0001
      assert_in_delta decoded.f64_val, 0.0, 0.0001
      assert decoded.flag == nil
      # UUID nil encodes as all-zeros, which now decodes back to nil
      assert decoded.id == nil
      assert decoded.created_at == nil
      assert decoded.updated_at == nil
      assert decoded.price == nil
      assert decoded.side == nil
      assert decoded.priority == nil
      # Char array nil becomes empty string, bitset nil becomes empty MapSet
      assert decoded.flags == nil or decoded.flags == MapSet.new()
    end

    test "block length is correct" do
      # u8(1) + u16(2) + u32(4) + u64(8) + i8(1) + i16(2) + i32(4) + i64(8) +
      # f32(4) + f64(8) + bool(1) + uuid(16) + ts_us(8) + ts_ns(8) +
      # decimal(9) + side(1) + priority(1) + symbol(8) + flags(1)
      # = 1+2+4+8+1+2+4+8+4+8+1+16+8+8+9+1+1+8+1 = 95
      assert KitchenSinkCodec.block_length() == 95
    end

    test "zero-copy access works for all types" do
      data = %{
        u8_val: 100,
        u16_val: 1000,
        u32_val: 100_000,
        u64_val: 10_000_000_000,
        i8_val: -50,
        i16_val: -500,
        i32_val: -50_000,
        i64_val: -5_000_000_000,
        f32_val: 3.14,
        f64_val: 2.718281828,
        flag: true,
        id: :crypto.strong_rand_bytes(16),
        created_at: System.system_time(:microsecond),
        updated_at: System.system_time(:nanosecond),
        price: Decimal.new("123.45"),
        side: :buy,
        priority: :high,
        symbol: "AAPL",
        flags: MapSet.new([:a, :c])
      }

      binary = KitchenSinkCodec.encode(data)
      env = KitchenSinkCodec.wrap(binary)
      {:ok, decoded} = KitchenSinkCodec.decode(binary)

      # Verify get/2 returns same values as decode
      assert KitchenSinkCodec.get(env, :u8_val) == decoded.u8_val
      assert KitchenSinkCodec.get(env, :u16_val) == decoded.u16_val
      assert KitchenSinkCodec.get(env, :u32_val) == decoded.u32_val
      assert KitchenSinkCodec.get(env, :u64_val) == decoded.u64_val
      assert KitchenSinkCodec.get(env, :i8_val) == decoded.i8_val
      assert KitchenSinkCodec.get(env, :i16_val) == decoded.i16_val
      assert KitchenSinkCodec.get(env, :i32_val) == decoded.i32_val
      assert KitchenSinkCodec.get(env, :i64_val) == decoded.i64_val
      assert_in_delta KitchenSinkCodec.get(env, :f32_val), decoded.f32_val, 0.001
      assert_in_delta KitchenSinkCodec.get(env, :f64_val), decoded.f64_val, 1.0e-10
      assert KitchenSinkCodec.get(env, :flag) == decoded.flag
      assert KitchenSinkCodec.get(env, :id) == decoded.id
      assert KitchenSinkCodec.get(env, :created_at) == decoded.created_at
      assert KitchenSinkCodec.get(env, :updated_at) == decoded.updated_at
      # Decimal via get returns the decoded Decimal value
      assert Decimal.equal?(KitchenSinkCodec.get(env, :price), decoded.price)
      assert KitchenSinkCodec.get(env, :side) == decoded.side
      assert KitchenSinkCodec.get(env, :priority) == decoded.priority
      assert KitchenSinkCodec.get(env, :symbol) == decoded.symbol
      assert MapSet.equal?(KitchenSinkCodec.get(env, :flags), decoded.flags)
    end
  end

  # ============================================================================
  # Fast Path Specific Tests
  # ============================================================================

  describe "fast path optimization verification" do
    defmodule FastPathVerifyCodec do
      use GridCodec

      defcodec do
        field(:a, :u64)
        field(:b, :u32)
        field(:c, :bool)
      end
    end

    test "fast path is used for fixed-only codecs" do
      # The fast path generates a pattern match clause
      # We can verify it works by checking the function exists and works
      data = %{a: 123, b: 456, c: true}
      binary = FastPathVerifyCodec.encode(data)
      {:ok, decoded} = FastPathVerifyCodec.decode(binary)

      assert decoded == data
    end

    test "encode works with struct input" do
      # Using an anonymous map that has all fields works like a struct
      struct_like = %{a: 123, b: 456, c: true}
      binary = FastPathVerifyCodec.encode(struct_like)
      {:ok, decoded} = FastPathVerifyCodec.decode(binary)

      assert decoded.a == 123
      assert decoded.b == 456
      assert decoded.c == true
    end

    test "encode works with partial map (fallback path)" do
      # Missing :c field should use fallback and apply default (nil -> null sentinel)
      partial_data = %{a: 123, b: 456}
      binary = FastPathVerifyCodec.encode(partial_data)
      {:ok, decoded} = FastPathVerifyCodec.decode(binary)

      assert decoded.a == 123
      assert decoded.b == 456
      assert decoded.c == nil
    end

    test "encode works with empty map (all defaults)" do
      binary = FastPathVerifyCodec.encode(%{})
      {:ok, decoded} = FastPathVerifyCodec.decode(binary)

      assert decoded.a == nil
      assert decoded.b == nil
      assert decoded.c == nil
    end
  end
end
