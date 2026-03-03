defmodule GridCodec.StructCodecTest do
  use ExUnit.Case, async: true

  describe "encode/decode roundtrip" do
    defmodule SimpleStruct do
      use GridCodec.Struct, template_id: 1, schema_id: 100

      defcodec do
        field :id, :u64
        field :value, :u32
      end
    end

    test "encodes and decodes a simple struct" do
      original = %SimpleStruct{id: 12345, value: 999}

      # Encode with header (default)
      binary = SimpleStruct.encode(original)
      assert is_binary(binary)
      # header (8) + payload (12) = 20
      assert byte_size(binary) == 20

      # Decode framed binary back to struct
      {:ok, decoded} = SimpleStruct.decode(binary)
      assert %SimpleStruct{} = decoded
      assert decoded.id == 12345
      assert decoded.value == 999
    end

    test "encode/decode with header: false for payload only" do
      original = %SimpleStruct{id: 12345, value: 999}

      # Encode without header
      payload = SimpleStruct.encode(original, header: false)
      assert is_binary(payload)
      # payload only: 8 + 4 = 12
      assert byte_size(payload) == 12

      # Decode payload
      {:ok, decoded} = SimpleStruct.decode(payload, header: false)
      assert %SimpleStruct{} = decoded
      assert decoded.id == 12345
      assert decoded.value == 999
    end

    test "encode/decode roundtrip with default header" do
      original = %SimpleStruct{id: 12345, value: 999}

      # Encode with header (default)
      framed = SimpleStruct.encode(original)
      assert is_binary(framed)
      # header + payload
      assert byte_size(framed) == 8 + 12

      # Decode framed binary
      {:ok, decoded} = SimpleStruct.decode(framed)
      assert decoded.id == 12345
      assert decoded.value == 999
    end

    test "nil fields roundtrip as nil" do
      original = %SimpleStruct{id: nil, value: nil}

      binary = SimpleStruct.encode(original)
      {:ok, decoded} = SimpleStruct.decode(binary)

      # Nil values are preserved through encode/decode (null sentinel in binary)
      assert decoded.id == nil
      assert decoded.value == nil
    end
  end

  describe "all fixed-size types" do
    defmodule AllTypesStruct do
      use GridCodec.Struct, template_id: 2, schema_id: 100

      defcodec do
        field :f_u8, :u8
        field :f_u16, :u16
        field :f_u32, :u32
        field :f_u64, :u64
        field :f_i8, :i8
        field :f_i16, :i16
        field :f_i32, :i32
        field :f_i64, :i64
        field :f_uuid, :uuid
        field :f_bool, :bool
      end
    end

    test "roundtrip all unsigned integer types" do
      uuid = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>

      # Note: Max values for unsigned types are null sentinels, so use max-1
      original = %AllTypesStruct{
        # max is null (255)
        f_u8: 254,
        # max is null (65535)
        f_u16: 65534,
        # max is null
        f_u32: 4_294_967_294,
        # max is null
        f_u64: 18_446_744_073_709_551_614,
        # min is null (-128)
        f_i8: -127,
        # min is null (-32768)
        f_i16: -32767,
        # min is null
        f_i32: -2_147_483_647,
        # min is null
        f_i64: -9_223_372_036_854_775_807,
        f_uuid: uuid,
        f_bool: true
      }

      binary = AllTypesStruct.encode(original)
      {:ok, decoded} = AllTypesStruct.decode(binary)

      assert decoded.f_u8 == 254
      assert decoded.f_u16 == 65534
      assert decoded.f_u32 == 4_294_967_294
      assert decoded.f_u64 == 18_446_744_073_709_551_614
      assert decoded.f_i8 == -127
      assert decoded.f_i16 == -32767
      assert decoded.f_i32 == -2_147_483_647
      assert decoded.f_i64 == -9_223_372_036_854_775_807
      assert decoded.f_uuid == uuid
      assert decoded.f_bool == true
    end

    test "boolean false roundtrip" do
      original = %AllTypesStruct{
        f_u8: 0,
        f_u16: 0,
        f_u32: 0,
        f_u64: 0,
        f_i8: 0,
        f_i16: 0,
        f_i32: 0,
        f_i64: 0,
        f_uuid: <<0::128>>,
        f_bool: false
      }

      binary = AllTypesStruct.encode(original)
      {:ok, decoded} = AllTypesStruct.decode(binary)

      assert decoded.f_bool == false
    end
  end

  describe "default values in encoding" do
    defmodule DefaultStruct do
      use GridCodec.Struct, template_id: 3, schema_id: 100

      defcodec do
        field :id, :u64
        field :count, :u32, default: 100
        field :status, :u8, default: 1
      end
    end

    test "default values are used when field is nil" do
      original = %DefaultStruct{id: 123, count: nil, status: nil}

      binary = DefaultStruct.encode(original)
      {:ok, decoded} = DefaultStruct.decode(binary)

      assert decoded.id == 123
      # default
      assert decoded.count == 100
      # default
      assert decoded.status == 1
    end

    test "explicit values override defaults" do
      original = %DefaultStruct{id: 123, count: 500, status: 2}

      binary = DefaultStruct.encode(original)
      {:ok, decoded} = DefaultStruct.decode(binary)

      assert decoded.count == 500
      assert decoded.status == 2
    end
  end

  describe "constant fields" do
    defmodule ConstantStruct do
      use GridCodec.Struct, template_id: 4, schema_id: 100

      defcodec do
        field :id, :u64
        field :msg_type, :u8, presence: :constant, value: 42
      end
    end

    test "constant fields are always encoded with constant value" do
      # Even if struct has different value, encoding uses constant
      original = %ConstantStruct{id: 123, msg_type: 99}

      binary = ConstantStruct.encode(original)
      {:ok, decoded} = ConstantStruct.decode(binary)

      assert decoded.id == 123
      # constant value, not 99
      assert decoded.msg_type == 42
    end
  end

  describe "required fields" do
    defmodule RequiredStruct do
      use GridCodec.Struct, template_id: 5, schema_id: 100

      defcodec do
        field :id, :uuid, presence: :required
        field :value, :u64
      end
    end

    test "required fields cannot be nil during encoding" do
      original = %RequiredStruct{id: nil, value: 100}

      assert_raise ArgumentError, ~r/required field :id cannot be nil/, fn ->
        RequiredStruct.encode(original)
      end
    end

    test "required fields encode/decode correctly when provided" do
      uuid = <<1::128>>
      original = %RequiredStruct{id: uuid, value: 100}

      binary = RequiredStruct.encode(original)
      {:ok, decoded} = RequiredStruct.decode(binary)

      assert decoded.id == uuid
      assert decoded.value == 100
    end
  end

  describe "zero-copy get macro" do
    defmodule WrapStruct do
      use GridCodec.Struct, template_id: 6, schema_id: 100

      defcodec do
        field :id, :u64
        field :price, :u32
        field :quantity, :u16
      end
    end

    test "get macro retrieves field from binary" do
      require WrapStruct

      original = %WrapStruct{id: 12345, price: 999, quantity: 50}
      binary = WrapStruct.encode(original)

      assert WrapStruct.get(binary, :id) == 12345
      assert WrapStruct.get(binary, :price) == 999
      assert WrapStruct.get(binary, :quantity) == 50
    end

    test "get macro with payload-only binary" do
      require WrapStruct

      original = %WrapStruct{id: 12345, price: 999, quantity: 50}
      payload = WrapStruct.encode(original, header: false)

      assert WrapStruct.get(payload, :id, header: false) == 12345
      assert WrapStruct.get(payload, :price, header: false) == 999
      assert WrapStruct.get(payload, :quantity, header: false) == 50
    end
  end

  describe "header validation" do
    defmodule HeaderStruct do
      use GridCodec.Struct, template_id: 7, schema_id: 100, version: 2

      defcodec do
        field :id, :u64
      end
    end

    test "decode! validates template_id" do
      # Create a valid binary with wrong template_id
      header =
        GridCodec.Header.encode(
          block_length: 8,
          # wrong
          template_id: 999,
          schema_id: 100,
          version: 2
        )

      payload = <<12345::little-64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:template_id_mismatch, 999, 7}} = HeaderStruct.decode(binary)
    end

    test "decode! validates schema_id" do
      header =
        GridCodec.Header.encode(
          block_length: 8,
          template_id: 7,
          # wrong
          schema_id: 999,
          version: 2
        )

      payload = <<12345::little-64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:schema_id_mismatch, 999, 100}} = HeaderStruct.decode(binary)
    end

    test "decode! validates version" do
      header =
        GridCodec.Header.encode(
          block_length: 8,
          template_id: 7,
          schema_id: 100,
          # newer than codec version
          version: 99
        )

      payload = <<12345::little-64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:version_too_new, 99, 2}} = HeaderStruct.decode(binary)
    end

    test "decode! accepts older versions" do
      header =
        GridCodec.Header.encode(
          block_length: 8,
          template_id: 7,
          schema_id: 100,
          # older is ok
          version: 1
        )

      payload = <<12345::little-64>>
      binary = <<header::binary, payload::binary>>

      {:ok, decoded} = HeaderStruct.decode(binary)
      assert decoded.id == 12345
    end
  end

  describe "match/1,2 macro" do
    defmodule MatchTestStruct do
      use GridCodec.Struct, template_id: 50, schema_id: 100

      defcodec do
        field :id, :u64
        field :price, :u32
        field :quantity, :u16
      end
    end

    test "match extracts fields from framed binary (default header: true)" do
      require MatchTestStruct

      original = %MatchTestStruct{id: 12345, price: 999, quantity: 42}
      binary = MatchTestStruct.encode(original)

      result =
        case binary do
          MatchTestStruct.match(id: id, price: p) -> {:ok, id, p}
          _ -> :no_match
        end

      assert result == {:ok, 12345, 999}
    end

    test "match extracts fields from payload-only binary (header: false)" do
      require MatchTestStruct

      original = %MatchTestStruct{id: 12345, price: 999, quantity: 42}
      payload = MatchTestStruct.encode(original, header: false)

      result =
        case payload do
          MatchTestStruct.match([id: id, quantity: q], header: false) -> {:ok, id, q}
          _ -> :no_match
        end

      assert result == {:ok, 12345, 42}
    end

    test "match works with guards" do
      require MatchTestStruct

      original = %MatchTestStruct{id: 12345, price: 999, quantity: 42}
      binary = MatchTestStruct.encode(original)

      result =
        case binary do
          MatchTestStruct.match(price: p) when p > 500 -> :high_price
          MatchTestStruct.match(price: p) when p <= 500 -> :low_price
          _ -> :unknown
        end

      assert result == :high_price
    end

    test "match returns raw sentinel value for null fields, not nil" do
      require MatchTestStruct

      # Create struct with nil price
      original = %MatchTestStruct{id: 12345, price: nil, quantity: 42}
      binary = MatchTestStruct.encode(original)

      # Match extracts raw sentinel value, NOT nil
      result =
        case binary do
          MatchTestStruct.match(price: p) -> p
          _ -> :no_match
        end

      # u32 null sentinel is 0xFFFFFFFF
      assert result == 0xFFFFFFFF
      refute is_nil(result)
    end

    test "match on literal nil matches encoded null sentinel for primitive fields" do
      require MatchTestStruct

      null_binary = MatchTestStruct.encode(%MatchTestStruct{id: 1, price: nil, quantity: 10})
      non_null_binary = MatchTestStruct.encode(%MatchTestStruct{id: 1, price: 123, quantity: 10})

      assert match?(MatchTestStruct.match(price: nil), null_binary)
      refute match?(MatchTestStruct.match(price: nil), non_null_binary)
    end
  end
end
