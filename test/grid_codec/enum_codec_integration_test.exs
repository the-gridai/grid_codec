defmodule GridCodec.EnumCodecIntegrationTest do
  use ExUnit.Case

  # Define test enums
  defmodule Side do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:buy, 0)
      value(:sell, 1)
    end
  end

  defmodule OrderType do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:limit, 0)
      value(:market, 1)
      value(:stop, 2)
    end
  end

  # Define codec with enum fields
  defmodule OrderCodec do
    use GridCodec,
      types: [
        side: GridCodec.EnumCodecIntegrationTest.Side,
        order_type: GridCodec.EnumCodecIntegrationTest.OrderType
      ]

    defcodec do
      field(:id, :u64)
      field(:side, :side)
      field(:order_type, :order_type)
      field(:quantity, :u32)
      field(:price, :i64)
    end
  end

  describe "codec with enum fields" do
    test "encodes with enum values" do
      data = %{
        id: 12345,
        side: :buy,
        order_type: :limit,
        quantity: 100,
        price: 150_00
      }

      binary = OrderCodec.encode(data)
      assert byte_size(binary) == OrderCodec.block_length()
    end

    test "decodes enum values to atoms" do
      data = %{
        id: 12345,
        side: :sell,
        order_type: :market,
        quantity: 200,
        price: 250_00
      }

      binary = OrderCodec.encode(data)
      {:ok, decoded} = OrderCodec.decode(binary)

      assert decoded.id == 12345
      assert decoded.side == :sell
      assert decoded.order_type == :market
      assert decoded.quantity == 200
      assert decoded.price == 250_00
    end

    test "handles nil enum values" do
      data = %{
        id: 12345,
        side: nil,
        order_type: nil,
        quantity: 100,
        price: nil
      }

      binary = OrderCodec.encode(data)
      {:ok, decoded} = OrderCodec.decode(binary)

      assert decoded.side == nil
      assert decoded.order_type == nil
      assert decoded.price == nil
    end

    test "roundtrips all enum values" do
      for side <- [:buy, :sell, nil] do
        for order_type <- [:limit, :market, :stop, nil] do
          data = %{
            id: 999,
            side: side,
            order_type: order_type,
            quantity: 1,
            price: 1
          }

          binary = OrderCodec.encode(data)
          {:ok, decoded} = OrderCodec.decode(binary)

          assert decoded.side == side,
                 "side mismatch: expected #{inspect(side)}, got #{inspect(decoded.side)}"

          assert decoded.order_type == order_type
        end
      end
    end

    test "zero-copy get works with enum fields" do
      data = %{
        id: 12345,
        side: :buy,
        order_type: :limit,
        quantity: 100,
        price: 150_00
      }

      binary = OrderCodec.encode(data)
      env = OrderCodec.wrap(binary)

      assert OrderCodec.get(env, :id) == 12345
      assert OrderCodec.get(env, :side) == :buy
      assert OrderCodec.get(env, :order_type) == :limit
      assert OrderCodec.get(env, :quantity) == 100
      assert OrderCodec.get(env, :price) == 150_00
    end

    test "zero-copy get handles nil enum values" do
      data = %{
        id: 12345,
        side: nil,
        order_type: nil,
        quantity: 100,
        price: nil
      }

      binary = OrderCodec.encode(data)
      env = OrderCodec.wrap(binary)

      assert OrderCodec.get(env, :side) == nil
      assert OrderCodec.get(env, :order_type) == nil
    end

    test "block length is correct" do
      # id (8) + side (1) + order_type (1) + quantity (4) + price (8) = 22
      assert OrderCodec.block_length() == 22
    end

    test "encodes integer values directly for enums" do
      # Can pass integer values directly
      data = %{
        id: 12345,
        side: 0,
        order_type: 1,
        quantity: 100,
        price: 150_00
      }

      binary = OrderCodec.encode(data)
      {:ok, decoded} = OrderCodec.decode(binary)

      # Decodes to atoms
      assert decoded.side == :buy
      assert decoded.order_type == :market
    end
  end
end
