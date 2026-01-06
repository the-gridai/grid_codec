defmodule GridCodec.StructAllTypesTest do
  use ExUnit.Case, async: true

  describe "all built-in types with GridCodec.Struct" do
    # Test all fixed-size types
    defmodule FixedTypesStruct do
      use GridCodec.Struct, template_id: 100, schema_id: 1

      defcodec do
        field :u8_val, :u8
        field :u16_val, :u16
        field :u32_val, :u32
        field :u64_val, :u64
        field :i8_val, :i8
        field :i16_val, :i16
        field :i32_val, :i32
        field :i64_val, :i64
        field :f32_val, :f32
        field :f64_val, :f64
        field :uuid_val, :uuid
        field :bool_val, :bool
      end
    end

    test "all fixed-size types roundtrip" do
      uuid = :crypto.strong_rand_bytes(16)

      original = %FixedTypesStruct{
        u8_val: 42,
        u16_val: 1234,
        u32_val: 123_456,
        u64_val: 12_345_678_901_234_567,
        i8_val: -42,
        i16_val: -1234,
        i32_val: -123_456,
        i64_val: -12_345_678_901_234_567,
        f32_val: 123.456,
        f64_val: 123.456789,
        uuid_val: uuid,
        bool_val: true
      }

      binary = FixedTypesStruct.encode(original)
      {:ok, decoded} = FixedTypesStruct.decode(binary)

      assert decoded.u8_val == 42
      assert decoded.u16_val == 1234
      assert decoded.u32_val == 123_456
      assert decoded.u64_val == 12_345_678_901_234_567
      assert decoded.i8_val == -42
      assert decoded.i16_val == -1234
      assert decoded.i32_val == -123_456
      assert decoded.i64_val == -12_345_678_901_234_567
      # Float comparison with tolerance
      assert_in_delta decoded.f32_val, 123.456, 0.001
      assert_in_delta decoded.f64_val, 123.456789, 0.000001
      assert decoded.uuid_val == uuid
      assert decoded.bool_val == true
    end

    test "float values roundtrip" do
      # Floats don't support nil - they must have a value
      # Test with actual float values
      original = %FixedTypesStruct{
        u8_val: 0,
        u16_val: 0,
        u32_val: 0,
        u64_val: 0,
        i8_val: 0,
        i16_val: 0,
        i32_val: 0,
        i64_val: 0,
        f32_val: 123.456,
        f64_val: 123.456789,
        uuid_val: <<0::128>>,
        bool_val: false
      }

      binary = FixedTypesStruct.encode(original)
      {:ok, decoded} = FixedTypesStruct.decode(binary)

      assert_in_delta decoded.f32_val, 123.456, 0.001
      assert_in_delta decoded.f64_val, 123.456789, 0.000001
    end

    # Test timestamp types
    defmodule TimestampStruct do
      use GridCodec.Struct, template_id: 101, schema_id: 1

      defcodec do
        field :timestamp_us, :timestamp_us
        field :timestamp_ns, :timestamp_ns
      end
    end

    test "timestamp types roundtrip" do
      # Timestamps encode DateTime but decode as integer microseconds/nanoseconds
      fixed_time = ~U[2024-01-01 12:00:00.000000Z]
      expected_us = DateTime.to_unix(fixed_time, :microsecond)
      expected_ns = DateTime.to_unix(fixed_time, :nanosecond)

      original = %TimestampStruct{
        timestamp_us: fixed_time,
        timestamp_ns: fixed_time
      }

      binary = TimestampStruct.encode(original)
      {:ok, decoded} = TimestampStruct.decode(binary)

      # Timestamps decode as integers (microseconds/nanoseconds)
      assert decoded.timestamp_us == expected_us
      assert decoded.timestamp_ns == expected_ns
    end

    test "nil timestamps roundtrip" do
      original = %TimestampStruct{
        timestamp_us: nil,
        timestamp_ns: nil
      }

      binary = TimestampStruct.encode(original)
      {:ok, decoded} = TimestampStruct.decode(binary)

      assert decoded.timestamp_us == nil
      assert decoded.timestamp_ns == nil
    end

    # Test decimal type
    defmodule DecimalStruct do
      use GridCodec.Struct, template_id: 102, schema_id: 1

      defcodec do
        field :price, :decimal
      end
    end

    test "decimal type roundtrips" do
      price = Decimal.new("123.45")

      original = %DecimalStruct{price: price}
      binary = DecimalStruct.encode(original)
      {:ok, decoded} = DecimalStruct.decode(binary)

      assert Decimal.equal?(decoded.price, price)
    end

    test "nil decimal roundtrips" do
      original = %DecimalStruct{price: nil}
      binary = DecimalStruct.encode(original)
      {:ok, decoded} = DecimalStruct.decode(binary)

      assert decoded.price == nil
    end

    # Test string types
    defmodule StringStruct do
      use GridCodec.Struct, template_id: 103, schema_id: 1

      defcodec do
        field :name, :string16
        field :short_name, :string8
        field :long_name, :string32
      end
    end

    test "string types roundtrip" do
      original = %StringStruct{
        name: "Hello World",
        short_name: "Hi",
        long_name: "This is a very long string that exceeds 255 characters " <>
          String.duplicate("x", 200)
      }

      binary = StringStruct.encode(original)
      {:ok, decoded} = StringStruct.decode(binary)

      assert decoded.name == "Hello World"
      assert decoded.short_name == "Hi"
      assert decoded.long_name == original.long_name
    end

    test "nil strings roundtrip" do
      original = %StringStruct{
        name: nil,
        short_name: nil,
        long_name: nil
      }

      binary = StringStruct.encode(original)
      {:ok, decoded} = StringStruct.decode(binary)

      assert decoded.name == nil
      assert decoded.short_name == nil
      assert decoded.long_name == nil
    end

    # Test enum type
    defmodule OrderStatus do
      use GridCodec.Types.Enum, encoding: :u8

      defenum do
        value :pending
        value :filled
        value :cancelled
      end
    end

    defmodule EnumStruct do
      use GridCodec.Struct, template_id: 104, schema_id: 1, types: [status: OrderStatus]

      defcodec do
        field :status, :status
      end
    end

    test "enum type roundtrips" do
      original = %EnumStruct{status: :pending}
      binary = EnumStruct.encode(original)
      {:ok, decoded} = EnumStruct.decode(binary)

      assert decoded.status == :pending
    end

    test "nil enum roundtrips" do
      original = %EnumStruct{status: nil}
      binary = EnumStruct.encode(original)
      {:ok, decoded} = EnumStruct.decode(binary)

      assert decoded.status == nil
    end

    # Test bitset type
    defmodule Flags do
      use GridCodec.Types.Bitset, size: :u8

      flag(:active, 0)
      flag(:verified, 1)
      flag(:premium, 2)
    end

    defmodule BitsetStruct do
      use GridCodec.Struct, template_id: 105, schema_id: 1, types: [flags: Flags]

      defcodec do
        field :flags, :flags
      end
    end

    test "bitset type roundtrips" do
      flags = MapSet.new([:active, :verified])

      original = %BitsetStruct{flags: flags}
      binary = BitsetStruct.encode(original)
      {:ok, decoded} = BitsetStruct.decode(binary)

      assert MapSet.equal?(decoded.flags, flags)
    end

    test "nil bitset roundtrips" do
      original = %BitsetStruct{flags: nil}
      binary = BitsetStruct.encode(original)
      {:ok, decoded} = BitsetStruct.decode(binary)

      # Bitset decodes nil as empty MapSet
      assert MapSet.size(decoded.flags) == 0
    end

    # Test char_array type
    defmodule Symbol8 do
      use GridCodec.Types.CharArray, length: 8
    end

    defmodule CharArrayStruct do
      use GridCodec.Struct, template_id: 106, schema_id: 1, types: [symbol8: Symbol8]

      defcodec do
        field :symbol, :symbol8
      end
    end

    test "char_array type roundtrips" do
      original = %CharArrayStruct{symbol: "BTCUSD"}
      binary = CharArrayStruct.encode(original)
      {:ok, decoded} = CharArrayStruct.decode(binary)

      assert decoded.symbol == "BTCUSD"
    end

    test "char_array with padding" do
      original = %CharArrayStruct{symbol: "BTC"}
      binary = CharArrayStruct.encode(original)
      {:ok, decoded} = CharArrayStruct.decode(binary)

      # Char arrays strip trailing nulls on decode, so "BTC" stays "BTC"
      assert decoded.symbol == "BTC"
      # But the binary is 8 bytes
      assert byte_size(binary) >= 8
    end
  end
end
