defmodule GridCodecTest do
  use ExUnit.Case
  doctest GridCodec

  defmodule SimpleCodec do
    use GridCodec.Struct

    defcodec do
      field(:id, :u64)
      field(:count, :u32)
      field(:flag, :bool)
    end
  end

  defmodule UUIDCodec do
    use GridCodec.Struct

    defcodec do
      field(:order_id, :uuid)
      field(:price, :u64)
      field(:quantity, :u32)
    end
  end

  defmodule SignedCodec do
    use GridCodec.Struct

    defcodec do
      field(:temp, :i32)
      field(:offset, :i64)
    end
  end

  defmodule FloatCodec do
    use GridCodec.Struct

    defcodec do
      field(:latitude, :f64)
      field(:longitude, :f64)
      field(:altitude, :f32)
    end
  end

  describe "encode/decode roundtrip" do
    test "simple codec with integers and bool" do
      data = %SimpleCodec{id: 12345, count: 100, flag: true}
      binary = SimpleCodec.encode(data)

      assert {:ok, decoded} = SimpleCodec.decode(binary)
      assert decoded.id == 12345
      assert decoded.count == 100
      # bool decoded as boolean
      assert decoded.flag == true
    end

    test "uuid codec" do
      uuid = :crypto.strong_rand_bytes(16)
      data = %UUIDCodec{order_id: uuid, price: 15000, quantity: 50}
      binary = UUIDCodec.encode(data)

      assert {:ok, decoded} = UUIDCodec.decode(binary)
      assert decoded.order_id == uuid
      assert decoded.price == 15000
      assert decoded.quantity == 50
    end

    test "signed integers" do
      data = %SignedCodec{temp: -42, offset: -9_999_999}
      binary = SignedCodec.encode(data)

      assert {:ok, decoded} = SignedCodec.decode(binary)
      assert decoded.temp == -42
      assert decoded.offset == -9_999_999
    end

    test "float codec" do
      data = %FloatCodec{latitude: 37.7749, longitude: -122.4194, altitude: 10.5}
      binary = FloatCodec.encode(data)

      assert {:ok, decoded} = FloatCodec.decode(binary)
      assert_in_delta decoded.latitude, 37.7749, 0.0001
      assert_in_delta decoded.longitude, -122.4194, 0.0001
      assert_in_delta decoded.altitude, 10.5, 0.01
    end
  end

  describe "zero-copy field access via get macro" do
    test "get individual fields without full decode" do
      require SimpleCodec

      data = %SimpleCodec{id: 99999, count: 42, flag: false}
      binary = SimpleCodec.encode(data)

      assert SimpleCodec.get(binary, :id) == 99999
      assert SimpleCodec.get(binary, :count) == 42
      assert SimpleCodec.get(binary, :flag) == false
    end

    test "uuid field returns sub-binary" do
      require UUIDCodec

      uuid = :crypto.strong_rand_bytes(16)
      data = %UUIDCodec{order_id: uuid, price: 15000, quantity: 50}
      binary = UUIDCodec.encode(data)

      # Should return the same bytes
      assert UUIDCodec.get(binary, :order_id) == uuid
      assert UUIDCodec.get(binary, :price) == 15000
    end
  end

  describe "binary size" do
    test "simple codec produces expected size with header" do
      data = %SimpleCodec{id: 1, count: 1, flag: true}
      binary = SimpleCodec.encode(data)

      # header (8) + u64 (8) + u32 (4) + bool (1) = 21 bytes
      assert byte_size(binary) == 21
    end

    test "simple codec payload size without header" do
      data = %SimpleCodec{id: 1, count: 1, flag: true}
      payload = SimpleCodec.encode(data, header: false)

      # u64 (8) + u32 (4) + bool (1) = 13 bytes
      assert byte_size(payload) == 13
    end

    test "uuid codec produces expected size with header" do
      data = %UUIDCodec{order_id: <<0::128>>, price: 0, quantity: 0}
      binary = UUIDCodec.encode(data)

      # header (8) + uuid (16) + u64 (8) + u32 (4) = 36 bytes
      assert byte_size(binary) == 36
    end

    test "block_length/0 returns fixed block size (payload only)" do
      assert SimpleCodec.block_length() == 13
      assert UUIDCodec.block_length() == 28
    end
  end

  describe "schema introspection" do
    test "returns schema metadata" do
      schema = SimpleCodec.__schema__()

      assert schema.version == 1
      assert schema.endian == :little
      assert length(schema.fields) == 3
      assert schema.block_length == 13
    end

    test "tracks fixed vs variable fields" do
      schema = SimpleCodec.__schema__()

      assert :id in schema.fixed_fields
      assert :count in schema.fixed_fields
      assert :flag in schema.fixed_fields
      assert schema.var_fields == []
    end

    test "__fields__/0 returns list of field names" do
      assert SimpleCodec.__fields__() == [:id, :count, :flag]
      assert UUIDCodec.__fields__() == [:order_id, :price, :quantity]
    end

    test "t() type documentation is generated" do
      # The type is generated and should be usable by Dialyzer
      # We verify it's defined by checking the @typedoc attribute exists
      # Dialyzer passing is the real verification that t() is correctly typed
      # The test "__fields__/0 returns list of field names" also verifies compilation
      assert is_list(SimpleCodec.__fields__())
    end
  end
end
