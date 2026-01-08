defmodule GridCodec.FramingTest do
  use ExUnit.Case, async: true

  alias GridCodec.Envelope

  describe "codec with template_id and schema_id" do
    defmodule OrderEvent do
      use GridCodec.Struct, template_id: 42, schema_id: 100, version: 3

      defcodec do
        field :order_id, :u64
        field :price, :u64
        field :quantity, :u32
      end
    end

    test "__template_id__/0 returns configured template_id" do
      assert OrderEvent.__template_id__() == 42
    end

    test "__schema_id__/0 returns configured schema_id" do
      assert OrderEvent.__schema_id__() == 100
    end

    test "__version__/0 returns configured version" do
      assert OrderEvent.__version__() == 3
    end

    test "encode/1 includes header by default" do
      data = %OrderEvent{order_id: 123, price: 1000, quantity: 50}
      binary = OrderEvent.encode(data)

      # Framed = header (8) + payload (20) = 28 bytes
      assert byte_size(binary) == 28

      # Verify header is correct
      {:ok, header, payload} = GridCodec.Header.decode(binary)
      assert header.block_length == 20
      assert header.template_id == 42
      assert header.schema_id == 100
      assert header.version == 3
      assert byte_size(payload) == 20
    end

    test "encode/2 with header: false produces payload only" do
      data = %OrderEvent{order_id: 123, price: 1000, quantity: 50}
      payload = OrderEvent.encode(data, header: false)

      # Payload should be exactly block_length bytes (8 + 8 + 4 = 20)
      assert byte_size(payload) == 20
    end

    test "decode/1 expects header by default" do
      data = %OrderEvent{order_id: 123, price: 1000, quantity: 50}
      framed = OrderEvent.encode(data)

      assert {:ok, decoded} = OrderEvent.decode(framed)
      assert decoded.order_id == 123
      assert decoded.price == 1000
      assert decoded.quantity == 50
    end

    test "decode/2 with header: false decodes payload only" do
      data = %OrderEvent{order_id: 123, price: 1000, quantity: 50}
      payload = OrderEvent.encode(data, header: false)

      assert {:ok, decoded} = OrderEvent.decode(payload, header: false)
      assert decoded.order_id == 123
      assert decoded.price == 1000
      assert decoded.quantity == 50
    end

    test "decode/1 rejects wrong template_id" do
      # Create a message with wrong template_id
      header =
        GridCodec.Header.encode(
          block_length: 20,
          template_id: 999,
          schema_id: 100,
          version: 3
        )

      payload = <<0::160>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:template_id_mismatch, 999, 42}} = OrderEvent.decode(binary)
    end

    test "decode/1 rejects wrong schema_id" do
      header =
        GridCodec.Header.encode(
          block_length: 20,
          template_id: 42,
          schema_id: 999,
          version: 3
        )

      payload = <<0::160>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:schema_id_mismatch, 999, 100}} = OrderEvent.decode(binary)
    end

    test "decode/1 rejects version newer than codec" do
      header =
        GridCodec.Header.encode(
          block_length: 20,
          template_id: 42,
          schema_id: 100,
          version: 4
        )

      payload = <<0::160>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:version_too_new, 4, 3}} = OrderEvent.decode(binary)
    end

    test "decode/1 accepts older version" do
      # Version 1 message should be decodable by version 3 codec
      header =
        GridCodec.Header.encode(
          block_length: 20,
          template_id: 42,
          schema_id: 100,
          version: 1
        )

      payload = <<123::little-64, 1000::little-64, 50::little-32>>
      binary = <<header::binary, payload::binary>>

      assert {:ok, decoded} = OrderEvent.decode(binary)
      assert decoded.order_id == 123
    end

    test "wrap/1 wraps framed binary for zero-copy access" do
      data = %OrderEvent{order_id: 123, price: 1000, quantity: 50}
      framed = OrderEvent.encode(data)

      env = OrderEvent.wrap(framed)
      assert Envelope.get(env, :order_id) == 123
      assert Envelope.get(env, :price) == 1000
      assert Envelope.get(env, :quantity) == 50
    end

    test "wrap/2 with header: false wraps payload directly" do
      data = %OrderEvent{order_id: 123, price: 1000, quantity: 50}
      payload = OrderEvent.encode(data, header: false)

      env = OrderEvent.wrap(payload, header: false)
      assert Envelope.get(env, :order_id) == 123
      assert Envelope.get(env, :price) == 1000
      assert Envelope.get(env, :quantity) == 50
    end
  end

  describe "default template_id and schema_id" do
    defmodule SimpleCodec do
      use GridCodec.Struct

      defcodec do
        field :value, :u64
      end
    end

    test "defaults to auto-generated template_id" do
      # Template ID is auto-generated from module name hash
      assert is_integer(SimpleCodec.__template_id__())
    end

    test "defaults to schema_id: 0" do
      assert SimpleCodec.__schema_id__() == 0
    end

    test "defaults to version: 1" do
      assert SimpleCodec.__version__() == 1
    end

    test "encode/1 includes header with defaults" do
      framed = SimpleCodec.encode(%SimpleCodec{value: 42})

      {:ok, header, _} = GridCodec.Header.decode(framed)
      assert header.template_id == SimpleCodec.__template_id__()
      assert header.schema_id == 0
      assert header.version == 1
    end
  end

  describe "roundtrip with framing" do
    defmodule ComplexEvent do
      use GridCodec.Struct, template_id: 10, schema_id: 50, version: 2

      defcodec do
        field :id, :uuid
        field :count, :u32
        field :price, :u64
        field :active, :bool
      end
    end

    test "encode/decode roundtrip preserves data" do
      uuid = :crypto.strong_rand_bytes(16)

      data = %ComplexEvent{
        id: uuid,
        count: 100,
        price: 50000,
        active: true
      }

      framed = ComplexEvent.encode(data)
      {:ok, decoded} = ComplexEvent.decode(framed)

      assert decoded.id == uuid
      assert decoded.count == 100
      assert decoded.price == 50000
      assert decoded.active == true
    end
  end
end
