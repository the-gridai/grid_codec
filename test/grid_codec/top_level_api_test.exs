defmodule GridCodec.TopLevelApiTest do
  use ExUnit.Case, async: true

  # Define test codecs with unique IDs
  defmodule Order do
    use GridCodec.Struct, template_id: 301, schema_id: 800

    defcodec do
      field :id, :u64
      field :price, :u32
      field :quantity, :u16
    end
  end

  defmodule Trade do
    use GridCodec.Struct, template_id: 302, schema_id: 800

    defcodec do
      field :trade_id, :u64
      field :amount, :u32
    end
  end

  describe "GridCodec.encode/1" do
    test "encodes a struct with header" do
      order = %Order{id: 12345, price: 999, quantity: 50}

      binary = GridCodec.encode(order)

      # Should include 8-byte header + payload
      assert is_binary(binary)
      # Payload: u64 (8) + u32 (4) + u16 (2) = 14 bytes
      # Header: 8 bytes
      assert byte_size(binary) == 8 + 14
    end

    test "encoded binary has correct header" do
      order = %Order{id: 12345, price: 999, quantity: 50}

      binary = GridCodec.encode(order)

      {:ok, header, _payload} = GridCodec.Header.decode(binary)
      assert header.template_id == 301
      assert header.schema_id == 800
    end

    test "raises for non-struct input" do
      assert_raise FunctionClauseError, fn ->
        GridCodec.encode(%{id: 123})
      end
    end
  end

  describe "GridCodec.decode/1" do
    test "decodes to correct struct type based on header" do
      order = %Order{id: 12345, price: 999, quantity: 50}
      binary = GridCodec.encode(order)

      {:ok, decoded} = GridCodec.decode(binary)

      assert %Order{} = decoded
      assert decoded.id == 12345
      assert decoded.price == 999
      assert decoded.quantity == 50
    end

    test "decodes different struct types correctly" do
      order = %Order{id: 111, price: 100, quantity: 10}
      trade = %Trade{trade_id: 222, amount: 500}

      order_binary = GridCodec.encode(order)
      trade_binary = GridCodec.encode(trade)

      {:ok, decoded_order} = GridCodec.decode(order_binary)
      {:ok, decoded_trade} = GridCodec.decode(trade_binary)

      assert %Order{id: 111} = decoded_order
      assert %Trade{trade_id: 222} = decoded_trade
    end

    test "returns error for unknown codec" do
      # Create a binary with unknown template_id
      header =
        GridCodec.Header.encode(
          block_length: 8,
          template_id: 999,
          schema_id: 999,
          version: 1
        )

      payload = <<0::64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, :unknown_codec} = GridCodec.decode(binary)
    end

    test "returns error for invalid binary" do
      assert {:error, _} = GridCodec.decode(<<1, 2, 3>>)
    end
  end

  describe "GridCodec.wrap/1" do
    test "wraps binary for zero-copy access" do
      order = %Order{id: 12345, price: 999, quantity: 50}
      binary = GridCodec.encode(order)

      {:ok, env, codec} = GridCodec.wrap(binary)

      assert %GridCodec.Envelope{} = env
      assert codec == Order
    end

    test "allows field access via codec module" do
      order = %Order{id: 12345, price: 999, quantity: 50}
      binary = GridCodec.encode(order)

      {:ok, env, Order} = GridCodec.wrap(binary)

      assert Order.get(env, :id) == 12345
      assert Order.get(env, :price) == 999
      assert Order.get(env, :quantity) == 50
    end

    test "returns error for unknown codec" do
      header =
        GridCodec.Header.encode(
          block_length: 8,
          template_id: 999,
          schema_id: 999,
          version: 1
        )

      payload = <<0::64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, :unknown_codec} = GridCodec.wrap(binary)
    end
  end

  describe "module encode/decode equivalence" do
    test "GridCodec.encode equals Module.encode!" do
      order = %Order{id: 12345, price: 999, quantity: 50}

      via_gridcodec = GridCodec.encode(order)
      via_module = Order.encode!(order)

      assert via_gridcodec == via_module
    end

    test "both GridCodec.decode and Module.decode! return same struct" do
      order = %Order{id: 12345, price: 999, quantity: 50}
      binary = GridCodec.encode(order)

      {:ok, via_gridcodec} = GridCodec.decode(binary)
      {:ok, via_module} = Order.decode!(binary)

      assert via_gridcodec == via_module
    end
  end
end
