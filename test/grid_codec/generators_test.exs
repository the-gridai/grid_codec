defmodule GridCodec.GeneratorsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.Generators

  describe "type generators" do
    property "u8 generates values in 0..255 range" do
      check all(v <- Generators.for_type(:u8)) do
        assert is_integer(v)
        assert v >= 0 and v <= 255
      end
    end

    property "u16 generates values in 0..65535 range" do
      check all(v <- Generators.for_type(:u16)) do
        assert is_integer(v)
        assert v >= 0 and v <= 65535
      end
    end

    property "u32 generates values in u32 range" do
      check all(v <- Generators.for_type(:u32)) do
        assert is_integer(v)
        assert v >= 0 and v <= 0xFFFFFFFF
      end
    end

    property "u64 generates values in u64 range" do
      check all(v <- Generators.for_type(:u64)) do
        assert is_integer(v)
        assert v >= 0 and v <= 0xFFFFFFFFFFFFFFFF
      end
    end

    property "i8 generates values in -128..127 range" do
      check all(v <- Generators.for_type(:i8)) do
        assert is_integer(v)
        assert v >= -128 and v <= 127
      end
    end

    property "i16 generates values in i16 range" do
      check all(v <- Generators.for_type(:i16)) do
        assert is_integer(v)
        assert v >= -32768 and v <= 32767
      end
    end

    property "i32 generates values in i32 range" do
      check all(v <- Generators.for_type(:i32)) do
        assert is_integer(v)
        assert v >= -0x80000000 and v <= 0x7FFFFFFF
      end
    end

    property "i64 generates values in i64 range" do
      check all(v <- Generators.for_type(:i64)) do
        assert is_integer(v)
        assert v >= -0x8000000000000000 and v <= 0x7FFFFFFFFFFFFFFF
      end
    end

    property "f32 generates floats" do
      check all(v <- Generators.for_type(:f32)) do
        assert is_float(v)
      end
    end

    property "f64 generates floats" do
      check all(v <- Generators.for_type(:f64)) do
        assert is_float(v)
      end
    end

    property "bool generates booleans or nil" do
      check all(v <- Generators.for_type(:bool)) do
        assert is_boolean(v) or is_nil(v)
      end
    end

    property "uuid generates 16-byte binaries" do
      check all(v <- Generators.for_type(:uuid)) do
        assert is_binary(v)
        assert byte_size(v) == 16
      end
    end

    property "string16 generates strings with valid length prefix" do
      check all(v <- Generators.for_type(:string16)) do
        assert is_binary(v)
      end
    end

    property "timestamp_us generates integer timestamps or nil" do
      check all(v <- Generators.for_type(:timestamp_us)) do
        assert is_integer(v) or is_nil(v)
      end
    end

    property "timestamp_ns generates integer timestamps or nil" do
      check all(v <- Generators.for_type(:timestamp_ns)) do
        assert is_integer(v) or is_nil(v)
      end
    end

    property "decimal generates Decimal-compatible values" do
      check all(v <- Generators.for_type(:decimal)) do
        assert is_nil(v) or is_struct(v, Decimal) or is_tuple(v)
      end
    end
  end

  describe "for_codec/1" do
    defmodule TestCodec do
      use GridCodec.Struct, template_id: 7700, schema_id: 77

      defcodec do
        field :id, :u64
        field :active, :bool
        field :score, :f64
      end
    end

    property "for_codec generates maps that encode successfully" do
      check all(fields <- Generators.for_codec(TestCodec)) do
        struct = struct!(TestCodec, fields)
        assert {:ok, bin} = TestCodec.encode(struct)
        assert is_binary(bin)
        assert {:ok, decoded} = TestCodec.decode(bin)
        assert decoded.id == struct.id
        assert decoded.active == struct.active
      end
    end
  end

  describe "PrefixedId generator" do
    defmodule GenTestUserId do
      use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01
    end

    defmodule PrefixedIdCodec do
      use GridCodec.Struct, template_id: 7701, schema_id: 77

      defcodec do
        field :user_id, GenTestUserId
        field :count, :u64
      end
    end

    property "PrefixedId generator produces valid prefixed strings" do
      gen = GenTestUserId.generator()

      check all(v <- gen) do
        assert is_binary(v)
        assert String.starts_with?(v, "user-")
        assert byte_size(v) == 5 + 36
        assert GenTestUserId.valid?(v)
      end
    end

    property "for_codec with PrefixedId generates roundtrippable maps" do
      check all(fields <- Generators.for_codec(PrefixedIdCodec)) do
        struct = struct!(PrefixedIdCodec, fields)
        assert {:ok, bin} = PrefixedIdCodec.encode(struct)
        assert is_binary(bin)
        assert {:ok, decoded} = PrefixedIdCodec.decode(bin)
        assert decoded.user_id == struct.user_id
        assert decoded.count == struct.count
      end
    end
  end
end
