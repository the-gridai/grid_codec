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

      {:ok, binary} = FixedTypesStruct.encode(original)
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

      {:ok, binary} = FixedTypesStruct.encode(original)
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

      {:ok, binary} = TimestampStruct.encode(original)
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

      {:ok, binary} = TimestampStruct.encode(original)
      {:ok, decoded} = TimestampStruct.decode(binary)

      assert decoded.timestamp_us == nil
      assert decoded.timestamp_ns == nil
    end

    # Test datetime types (DateTime domain)
    defmodule DateTimeStruct do
      use GridCodec.Struct, template_id: 109, schema_id: 1

      defcodec do
        field :created_at, :datetime_us
        field :event_time, :datetime_ns
      end
    end

    test "datetime_us roundtrips as DateTime" do
      dt = ~U[2024-06-15 12:30:00.123456Z]
      original = %DateTimeStruct{created_at: dt, event_time: nil}

      {:ok, binary} = DateTimeStruct.encode(original)
      {:ok, decoded} = DateTimeStruct.decode(binary)

      assert %DateTime{} = decoded.created_at
      assert DateTime.compare(decoded.created_at, dt) == :eq
    end

    test "datetime_ns roundtrips as DateTime" do
      dt = ~U[2024-06-15 12:30:00.123456Z]
      original = %DateTimeStruct{created_at: nil, event_time: dt}

      {:ok, binary} = DateTimeStruct.encode(original)
      {:ok, decoded} = DateTimeStruct.decode(binary)

      assert %DateTime{} = decoded.event_time
      assert DateTime.compare(decoded.event_time, dt) == :eq
    end

    test "nil datetimes roundtrip" do
      original = %DateTimeStruct{created_at: nil, event_time: nil}
      {:ok, binary} = DateTimeStruct.encode(original)
      {:ok, decoded} = DateTimeStruct.decode(binary)

      assert decoded.created_at == nil
      assert decoded.event_time == nil
    end

    test "datetime types wire-compatible with timestamp types" do
      dt = ~U[2024-06-15 12:30:00.123456Z]
      us = DateTime.to_unix(dt, :microsecond)

      dt_struct = %DateTimeStruct{created_at: dt, event_time: nil}
      {:ok, dt_binary} = DateTimeStruct.encode(dt_struct)

      ts_struct = %TimestampStruct{timestamp_us: us, timestamp_ns: nil}
      {:ok, ts_binary} = TimestampStruct.encode(ts_struct)

      header_size = 8
      dt_payload = binary_part(dt_binary, header_size, 16)
      ts_payload = binary_part(ts_binary, header_size, 16)
      assert dt_payload == ts_payload
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
      {:ok, binary} = DecimalStruct.encode(original)
      {:ok, decoded} = DecimalStruct.decode(binary)

      assert Decimal.equal?(decoded.price, price)
    end

    test "nil decimal roundtrips" do
      original = %DecimalStruct{price: nil}
      {:ok, binary} = DecimalStruct.encode(original)
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
        long_name:
          "This is a very long string that exceeds 255 characters " <>
            String.duplicate("x", 200)
      }

      {:ok, binary} = StringStruct.encode(original)
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

      {:ok, binary} = StringStruct.encode(original)
      {:ok, decoded} = StringStruct.decode(binary)

      assert decoded.name == nil
      assert decoded.short_name == nil
      assert decoded.long_name == nil
    end

    # Test enum type
    defmodule OrderStatus do
      use GridCodec.Types.Enum, encoding: :u8

      defenum do
        value(:pending)
        value(:filled)
        value(:cancelled)
      end
    end

    defmodule EnumStruct do
      use GridCodec.Struct, template_id: 104, schema_id: 1

      defcodec do
        field :status, OrderStatus
      end
    end

    test "enum type roundtrips" do
      original = %EnumStruct{status: :pending}
      {:ok, binary} = EnumStruct.encode(original)
      {:ok, decoded} = EnumStruct.decode(binary)

      assert decoded.status == :pending
    end

    test "nil enum roundtrips" do
      original = %EnumStruct{status: nil}
      {:ok, binary} = EnumStruct.encode(original)
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
      use GridCodec.Struct, template_id: 105, schema_id: 1

      defcodec do
        field :flags, Flags
      end
    end

    test "bitset type roundtrips" do
      flags = MapSet.new([:active, :verified])

      original = %BitsetStruct{flags: flags}
      {:ok, binary} = BitsetStruct.encode(original)
      {:ok, decoded} = BitsetStruct.decode(binary)

      assert MapSet.equal?(decoded.flags, flags)
    end

    test "nil bitset roundtrips" do
      original = %BitsetStruct{flags: nil}
      {:ok, binary} = BitsetStruct.encode(original)
      {:ok, decoded} = BitsetStruct.decode(binary)

      # Bitset decodes nil as empty MapSet
      assert MapSet.size(decoded.flags) == 0
    end

    # Test char_array type
    defmodule Symbol8 do
      use GridCodec.Types.CharArray, length: 8
    end

    defmodule CharArrayStruct do
      use GridCodec.Struct, template_id: 106, schema_id: 1

      defcodec do
        field :symbol, Symbol8
      end
    end

    test "char_array type roundtrips" do
      original = %CharArrayStruct{symbol: "BTCUSD"}
      {:ok, binary} = CharArrayStruct.encode(original)
      {:ok, decoded} = CharArrayStruct.decode(binary)

      assert decoded.symbol == "BTCUSD"
    end

    test "char_array with padding" do
      original = %CharArrayStruct{symbol: "BTC"}
      {:ok, binary} = CharArrayStruct.encode(original)
      {:ok, decoded} = CharArrayStruct.decode(binary)

      # Char arrays strip trailing nulls on decode, so "BTC" stays "BTC"
      assert decoded.symbol == "BTC"
      # But the binary is 8 bytes
      assert byte_size(binary) >= 8
    end

    # Test uuid_string type
    defmodule UUIDStringStruct do
      use GridCodec.Struct, template_id: 107, schema_id: 1

      defcodec do
        field :id, :uuid_string
      end
    end

    test "uuid_string type roundtrips" do
      uuid_str = "550e8400-e29b-41d4-a716-446655440000"

      original = %UUIDStringStruct{id: uuid_str}
      {:ok, binary} = UUIDStringStruct.encode(original)
      {:ok, decoded} = UUIDStringStruct.decode(binary)

      assert String.downcase(decoded.id) == String.downcase(uuid_str)
    end

    test "nil uuid_string roundtrips" do
      original = %UUIDStringStruct{id: nil}
      {:ok, binary} = UUIDStringStruct.encode(original)
      {:ok, decoded} = UUIDStringStruct.decode(binary)

      assert decoded.id == nil
    end

    # Test positive_decimal type
    defmodule PositiveDecimalStruct do
      use GridCodec.Struct, template_id: 108, schema_id: 1

      defcodec do
        field :balance, :positive_decimal
      end
    end

    test "positive_decimal type roundtrips" do
      balance = Decimal.new("999.99")

      original = %PositiveDecimalStruct{balance: balance}
      {:ok, binary} = PositiveDecimalStruct.encode(original)
      {:ok, decoded} = PositiveDecimalStruct.decode(binary)

      assert Decimal.equal?(decoded.balance, balance)
    end

    test "nil positive_decimal roundtrips" do
      original = %PositiveDecimalStruct{balance: nil}
      {:ok, binary} = PositiveDecimalStruct.encode(original)
      {:ok, decoded} = PositiveDecimalStruct.decode(binary)

      assert decoded.balance == nil
    end

    defmodule TestUserId do
      use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01
    end

    defmodule PrefixedIdStruct do
      use GridCodec.Struct, template_id: 110, schema_id: 1

      defcodec do
        field :user_id, TestUserId
        field :name, :string8
      end
    end

    test "prefixed_id type roundtrips" do
      user_id = TestUserId.generate()
      original = %PrefixedIdStruct{user_id: user_id, name: "Alice"}

      {:ok, binary} = PrefixedIdStruct.encode(original)
      {:ok, decoded} = PrefixedIdStruct.decode(binary)

      assert decoded.user_id == user_id
      assert decoded.name == "Alice"
    end

    test "nil prefixed_id roundtrips" do
      original = %PrefixedIdStruct{user_id: nil, name: "Bob"}

      {:ok, binary} = PrefixedIdStruct.encode(original)
      {:ok, decoded} = PrefixedIdStruct.decode(binary)

      assert decoded.user_id == nil
      assert decoded.name == "Bob"
    end

    test "prefixed_id coerces plain UUID via new/1" do
      uuid_str = "550e8400-e29b-41d4-a716-446655440000"
      {:ok, via_new} = PrefixedIdStruct.new(%{user_id: uuid_str, name: "Charlie"})

      assert String.starts_with?(via_new.user_id, "user-")
      assert String.ends_with?(via_new.user_id, uuid_str)

      {:ok, bin} = PrefixedIdStruct.encode(via_new)
      {:ok, decoded} = PrefixedIdStruct.decode(bin)
      assert decoded.user_id == via_new.user_id
    end
  end

  describe "new/1 ↔ decode/1 identity invariant" do
    defmodule IdentityCodec do
      use GridCodec.Struct, template_id: 120, schema_id: 1

      defcodec do
        field :uuid_str, :uuid_string
        field :ts_us, :timestamp_us
        field :ts_ns, :timestamp_ns
        field :dec, :decimal
        field :pos_dec, :positive_decimal
        field :flag, :bool
        field :uid, :uuid
      end
    end

    test "uuid_string: new/1 then roundtrip preserves identity" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      {:ok, via_new} = IdentityCodec.new(%{uuid_str: uuid})

      {:ok, bin} = IdentityCodec.encode(via_new)
      {:ok, via_decode} = IdentityCodec.decode(bin)

      assert via_new.uuid_str == via_decode.uuid_str
    end

    test "uuid_string: raw bytes input normalized to string" do
      raw = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      {:ok, via_new} = IdentityCodec.new(%{uuid_str: raw})

      assert is_binary(via_new.uuid_str)
      assert byte_size(via_new.uuid_str) == 36
      assert via_new.uuid_str == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "uuid_string: hex string input normalized to dash format" do
      hex = "550e8400e29b41d4a716446655440000"
      {:ok, via_new} = IdentityCodec.new(%{uuid_str: hex})

      assert via_new.uuid_str == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "timestamp_us: DateTime input normalized to integer" do
      dt = ~U[2024-06-15 12:30:00.123456Z]
      {:ok, via_new} = IdentityCodec.new(%{ts_us: dt})

      assert is_integer(via_new.ts_us)
      assert via_new.ts_us == DateTime.to_unix(dt, :microsecond)

      {:ok, bin} = IdentityCodec.encode(via_new)
      {:ok, via_decode} = IdentityCodec.decode(bin)
      assert via_new.ts_us == via_decode.ts_us
    end

    test "timestamp_us: ISO 8601 string normalized to integer" do
      {:ok, via_new} = IdentityCodec.new(%{ts_us: "2024-06-15T12:30:00Z"})

      assert is_integer(via_new.ts_us)

      {:ok, bin} = IdentityCodec.encode(via_new)
      {:ok, via_decode} = IdentityCodec.decode(bin)
      assert via_new.ts_us == via_decode.ts_us
    end

    test "timestamp_ns: DateTime input normalized to integer" do
      dt = ~U[2024-06-15 12:30:00.123456Z]
      {:ok, via_new} = IdentityCodec.new(%{ts_ns: dt})

      assert is_integer(via_new.ts_ns)
      assert via_new.ts_ns == DateTime.to_unix(dt, :nanosecond)

      {:ok, bin} = IdentityCodec.encode(via_new)
      {:ok, via_decode} = IdentityCodec.decode(bin)
      assert via_new.ts_ns == via_decode.ts_ns
    end

    test "decimal: {mantissa, exponent} tuple normalized to %Decimal{}" do
      {:ok, via_new} = IdentityCodec.new(%{dec: {12345, -2}})

      assert %Decimal{} = via_new.dec
      assert Decimal.equal?(via_new.dec, Decimal.new("123.45"))

      {:ok, bin} = IdentityCodec.encode(via_new)
      {:ok, via_decode} = IdentityCodec.decode(bin)
      assert via_new.dec == via_decode.dec
    end

    test "positive_decimal: {mantissa, exponent} tuple normalized to %Decimal{}" do
      {:ok, via_new} = IdentityCodec.new(%{pos_dec: {99999, -4}})

      assert %Decimal{} = via_new.pos_dec
      assert Decimal.equal?(via_new.pos_dec, Decimal.new("9.9999"))

      {:ok, bin} = IdentityCodec.encode(via_new)
      {:ok, via_decode} = IdentityCodec.decode(bin)
      assert via_new.pos_dec == via_decode.pos_dec
    end

    test "all types: new/1 → encode → decode produces identical struct" do
      uuid_str = "a1b2c3d4-e5f6-7890-abcd-ef0123456789"
      ts = System.system_time(:microsecond)
      price = Decimal.new("42.50")
      balance = Decimal.new("100.00")
      raw_uuid = :crypto.strong_rand_bytes(16)

      {:ok, via_new} =
        IdentityCodec.new(%{
          uuid_str: uuid_str,
          ts_us: ts,
          ts_ns: ts * 1000,
          dec: price,
          pos_dec: balance,
          flag: true,
          uid: raw_uuid
        })

      {:ok, bin} = IdentityCodec.encode(via_new)
      {:ok, via_decode} = IdentityCodec.decode(bin)

      assert via_new.uuid_str == via_decode.uuid_str
      assert via_new.ts_us == via_decode.ts_us
      assert via_new.ts_ns == via_decode.ts_ns
      assert via_new.dec == via_decode.dec
      assert via_new.pos_dec == via_decode.pos_dec
      assert via_new.flag == via_decode.flag
      assert via_new.uid == via_decode.uid
    end

    defmodule DateTimeIdentityCodec do
      use GridCodec.Struct, template_id: 121, schema_id: 1

      defcodec do
        field :dt_us, :datetime_us
        field :dt_ns, :datetime_ns
      end
    end

    test "datetime_us: new/1 with DateTime preserves identity" do
      dt = ~U[2024-06-15 12:30:00.123456Z]
      {:ok, via_new} = DateTimeIdentityCodec.new(%{dt_us: dt})

      assert %DateTime{} = via_new.dt_us
      assert DateTime.compare(via_new.dt_us, dt) == :eq

      {:ok, bin} = DateTimeIdentityCodec.encode(via_new)
      {:ok, via_decode} = DateTimeIdentityCodec.decode(bin)
      assert DateTime.compare(via_new.dt_us, via_decode.dt_us) == :eq
    end

    test "datetime_us: new/1 with integer coerces to DateTime" do
      us = 1_718_451_000_123_456
      {:ok, via_new} = DateTimeIdentityCodec.new(%{dt_us: us})

      assert %DateTime{} = via_new.dt_us

      {:ok, bin} = DateTimeIdentityCodec.encode(via_new)
      {:ok, via_decode} = DateTimeIdentityCodec.decode(bin)
      assert DateTime.compare(via_new.dt_us, via_decode.dt_us) == :eq
    end

    test "datetime_us: new/1 with ISO 8601 string coerces to DateTime" do
      {:ok, via_new} = DateTimeIdentityCodec.new(%{dt_us: "2024-06-15T12:30:00Z"})

      assert %DateTime{} = via_new.dt_us

      {:ok, bin} = DateTimeIdentityCodec.encode(via_new)
      {:ok, via_decode} = DateTimeIdentityCodec.decode(bin)
      assert DateTime.compare(via_new.dt_us, via_decode.dt_us) == :eq
    end

    test "datetime_ns: new/1 with DateTime preserves identity" do
      dt = ~U[2024-06-15 12:30:00.123456Z]
      {:ok, via_new} = DateTimeIdentityCodec.new(%{dt_ns: dt})

      assert %DateTime{} = via_new.dt_ns

      {:ok, bin} = DateTimeIdentityCodec.encode(via_new)
      {:ok, via_decode} = DateTimeIdentityCodec.decode(bin)
      assert DateTime.compare(via_new.dt_ns, via_decode.dt_ns) == :eq
    end

    test "datetime_ns: new/1 with microsecond-aligned integer coerces to DateTime" do
      ns = 1_718_451_000_123_456_000
      {:ok, via_new} = DateTimeIdentityCodec.new(%{dt_ns: ns})

      assert %DateTime{} = via_new.dt_ns
      assert DateTime.to_unix(via_new.dt_ns, :nanosecond) == ns

      {:ok, bin} = DateTimeIdentityCodec.encode(via_new)
      {:ok, via_decode} = DateTimeIdentityCodec.decode(bin)
      assert DateTime.to_unix(via_decode.dt_ns, :nanosecond) == ns
    end

    test "datetime_ns: new/1 rejects sub-microsecond integer precision" do
      ns = 1_718_451_000_123_456_789

      assert {:error, %GridCodec.ValidationError{code: :cast_error, details: %{field: :dt_ns}}} =
               DateTimeIdentityCodec.new(%{dt_ns: ns})
    end

    test "datetime_ns: encode rejects sub-microsecond integer precision" do
      ns = 1_718_451_000_123_456_789

      assert {:error, %GridCodec.ValidationError{code: :cast_error, details: details}} =
               DateTimeIdentityCodec.encode(%DateTimeIdentityCodec{dt_ns: ns})

      assert details.description =~ "datetime_ns integers must be microsecond-aligned"
    end
  end
end
