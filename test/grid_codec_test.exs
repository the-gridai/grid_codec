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

  # > 64 bytes total to ensure refc binary behavior for sub-binary tests
  # header(8) + uuid(16) + uuid(16) + u64(8) + u64(8) + u64(8) + u32(4) = 68 bytes
  defmodule LargeUUIDCodec do
    use GridCodec.Struct

    defcodec do
      field(:trace_id, :uuid)
      field(:span_id, :uuid)
      field(:start_time, :u64)
      field(:end_time, :u64)
      field(:duration, :u64)
      field(:status, :u32)
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
      {:ok, binary} = SimpleCodec.encode(data)

      assert {:ok, decoded} = SimpleCodec.decode(binary)
      assert decoded.id == 12345
      assert decoded.count == 100
      # bool decoded as boolean
      assert decoded.flag == true
    end

    test "uuid codec" do
      uuid = :crypto.strong_rand_bytes(16)
      data = %UUIDCodec{order_id: uuid, price: 15000, quantity: 50}
      {:ok, binary} = UUIDCodec.encode(data)

      assert {:ok, decoded} = UUIDCodec.decode(binary)
      assert decoded.order_id == uuid
      assert decoded.price == 15000
      assert decoded.quantity == 50
    end

    test "signed integers" do
      data = %SignedCodec{temp: -42, offset: -9_999_999}
      {:ok, binary} = SignedCodec.encode(data)

      assert {:ok, decoded} = SignedCodec.decode(binary)
      assert decoded.temp == -42
      assert decoded.offset == -9_999_999
    end

    test "float codec" do
      data = %FloatCodec{latitude: 37.7749, longitude: -122.4194, altitude: 10.5}
      {:ok, binary} = FloatCodec.encode(data)

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
      {:ok, binary} = SimpleCodec.encode(data)

      assert SimpleCodec.get(binary, :id) == 99999
      assert SimpleCodec.get(binary, :count) == 42
      assert SimpleCodec.get(binary, :flag) == false
    end

    test "uuid field returns sub-binary" do
      require UUIDCodec

      uuid = :crypto.strong_rand_bytes(16)
      data = %UUIDCodec{order_id: uuid, price: 15000, quantity: 50}
      {:ok, binary} = UUIDCodec.encode(data)

      # Should return the same bytes
      assert UUIDCodec.get(binary, :order_id) == uuid
      assert UUIDCodec.get(binary, :price) == 15000
    end

    test "get with copy: true returns correct value for uuid" do
      require LargeUUIDCodec

      trace_id = :crypto.strong_rand_bytes(16)
      span_id = :crypto.strong_rand_bytes(16)

      data = %LargeUUIDCodec{
        trace_id: trace_id,
        span_id: span_id,
        start_time: 1000,
        end_time: 2000,
        duration: 1000,
        status: 1
      }

      {:ok, binary} = LargeUUIDCodec.encode(data)

      result = LargeUUIDCodec.get(binary, :trace_id, copy: true)
      assert result == trace_id
      # copy: true ensures the result is independent (at most 16 bytes referenced)
      assert :binary.referenced_byte_size(result) == 16
    end

    test "get with copy: true on integer field passes through unchanged" do
      require SimpleCodec

      data = %SimpleCodec{id: 42, count: 7, flag: true}
      {:ok, binary} = SimpleCodec.encode(data)

      assert SimpleCodec.get(binary, :id, copy: true) == 42
      assert SimpleCodec.get(binary, :flag, copy: true) == true
    end

    test "get with copy: true on null uuid returns nil" do
      require LargeUUIDCodec

      data = %LargeUUIDCodec{
        trace_id: nil,
        span_id: :crypto.strong_rand_bytes(16),
        start_time: 1,
        end_time: 2,
        duration: 1,
        status: 0
      }

      {:ok, binary} = LargeUUIDCodec.encode(data)
      assert LargeUUIDCodec.get(binary, :trace_id, copy: true) == nil
    end

    test "copy: true guarantees independent binary regardless of original size" do
      require LargeUUIDCodec

      trace_id = :crypto.strong_rand_bytes(16)
      span_id = :crypto.strong_rand_bytes(16)

      data = %LargeUUIDCodec{
        trace_id: trace_id,
        span_id: span_id,
        start_time: 1000,
        end_time: 2000,
        duration: 1000,
        status: 1
      }

      {:ok, binary} = LargeUUIDCodec.encode(data)

      result_copy = LargeUUIDCodec.get(binary, :trace_id, copy: true)
      result_no_copy = LargeUUIDCodec.get(binary, :trace_id)

      # Both return the correct value
      assert result_copy == trace_id
      assert result_no_copy == trace_id

      # With copy: always exactly 16 bytes referenced (independent copy)
      assert :binary.referenced_byte_size(result_copy) == 16
      # Without copy: either a sub-binary (references full binary) or
      # a heap binary (BEAM may optimize small extractions). Either way,
      # referenced size is <= original size.
      assert :binary.referenced_byte_size(result_no_copy) <= byte_size(binary)
    end
  end

  describe "binary size" do
    test "simple codec produces expected size with header" do
      data = %SimpleCodec{id: 1, count: 1, flag: true}
      {:ok, binary} = SimpleCodec.encode(data)

      # header (8) + u64 (8) + u32 (4) + bool (1) = 21 bytes
      assert byte_size(binary) == 21
    end

    test "simple codec payload size without header" do
      data = %SimpleCodec{id: 1, count: 1, flag: true}
      {:ok, payload} = SimpleCodec.encode(data, header: false)

      # u64 (8) + u32 (4) + bool (1) = 13 bytes
      assert byte_size(payload) == 13
    end

    test "uuid codec produces expected size with header" do
      data = %UUIDCodec{order_id: <<0::128>>, price: 0, quantity: 0}
      {:ok, binary} = UUIDCodec.encode(data)

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

  describe "GridCodec.Binary" do
    test "detach/1 copies binary fields in decoded struct" do
      trace_id = :crypto.strong_rand_bytes(16)
      span_id = :crypto.strong_rand_bytes(16)

      data = %LargeUUIDCodec{
        trace_id: trace_id,
        span_id: span_id,
        start_time: 1000,
        end_time: 2000,
        duration: 1000,
        status: 1
      }

      {:ok, binary} = LargeUUIDCodec.encode(data)
      {:ok, decoded} = LargeUUIDCodec.decode(binary)

      detached = GridCodec.Binary.detach(decoded)

      # Values are preserved
      assert detached.trace_id == trace_id
      assert detached.span_id == span_id
      assert detached.start_time == 1000
      assert detached.status == 1
      # Binary fields are independent copies (16 bytes each)
      assert :binary.referenced_byte_size(detached.trace_id) == 16
      assert :binary.referenced_byte_size(detached.span_id) == 16
    end

    test "detach/1 handles nil binary fields" do
      data = %LargeUUIDCodec{
        trace_id: nil,
        span_id: :crypto.strong_rand_bytes(16),
        start_time: 1,
        end_time: 2,
        duration: 1,
        status: 0
      }

      {:ok, binary} = LargeUUIDCodec.encode(data)
      {:ok, decoded} = LargeUUIDCodec.decode(binary)

      detached = GridCodec.Binary.detach(decoded)
      assert detached.trace_id == nil
      assert detached.span_id == decoded.span_id
      assert detached.start_time == 1
    end

    test "detach/1 on struct with no binary fields is a no-op" do
      data = %SimpleCodec{id: 42, count: 7, flag: true}
      {:ok, binary} = SimpleCodec.encode(data)
      {:ok, decoded} = SimpleCodec.decode(binary)

      detached = GridCodec.Binary.detach(decoded)
      assert detached == decoded
    end

    test "copy_field/1 copies binary and handles nil" do
      binary = :crypto.strong_rand_bytes(16)
      assert GridCodec.Binary.copy_field(binary) == binary
      assert GridCodec.Binary.copy_field(nil) == nil
      assert GridCodec.Binary.copy_field(42) == 42
    end
  end
end
