defmodule GridCodec.Schema.GridFileTest do
  use ExUnit.Case, async: true

  # Define modules that load from a .grid file with unique IDs
  defmodule OrderFromFile do
    use GridCodec.Struct,
      grid_file: "test/fixtures/grid_file_test.grid",
      message: :Order
  end

  defmodule TradeFromFile do
    use GridCodec.Struct,
      grid_file: "test/fixtures/grid_file_test.grid",
      message: :Trade
  end

  describe "loading from .grid file" do
    test "creates struct with correct fields" do
      order = %OrderFromFile{}
      assert Map.has_key?(order, :id)
      assert Map.has_key?(order, :user_id)
      assert Map.has_key?(order, :symbol)
      assert Map.has_key?(order, :quantity)
      assert Map.has_key?(order, :active)
    end

    test "has correct template_id from file" do
      assert OrderFromFile.__template_id__() == 7001
      assert TradeFromFile.__template_id__() == 7002
    end

    test "has correct schema_id from file" do
      assert OrderFromFile.__schema_id__() == 7000
      assert TradeFromFile.__schema_id__() == 7000
    end

    test "has correct version from file" do
      assert OrderFromFile.__version__() == 1
      assert TradeFromFile.__version__() == 1
    end

    test "encode/decode roundtrip works" do
      order = %OrderFromFile{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 12345,
        symbol: "BTC/USD",
        quantity: 100,
        active: true
      }

      binary = OrderFromFile.encode(order)
      {:ok, decoded} = OrderFromFile.decode(binary)

      assert decoded.id == order.id
      assert decoded.user_id == order.user_id
      assert decoded.symbol == order.symbol
      assert decoded.quantity == order.quantity
      assert decoded.active == order.active
    end

    test "trade message encode/decode works" do
      trade = %TradeFromFile{
        trade_id: "550e8400-e29b-41d4-a716-446655440000",
        order_id: "660e8400-e29b-41d4-a716-446655440000",
        price: 50000,
        quantity: 10
      }

      binary = TradeFromFile.encode(trade)
      {:ok, decoded} = TradeFromFile.decode(binary)

      assert decoded.trade_id == trade.trade_id
      assert decoded.order_id == trade.order_id
      assert decoded.price == trade.price
      assert decoded.quantity == trade.quantity
    end

    test "can be dispatched via GridCodec.decode" do
      order = %OrderFromFile{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 1,
        symbol: "X",
        quantity: 1,
        active: false
      }

      binary = OrderFromFile.encode(order)
      {:ok, decoded} = GridCodec.decode(binary)

      # Check values match what we encoded
      assert decoded.id == order.id
      assert decoded.user_id == order.user_id
      assert decoded.symbol == order.symbol
      assert decoded.quantity == order.quantity
      assert decoded.active == order.active
    end
  end

  describe "__fields__/0" do
    test "returns field names from .grid file" do
      fields = OrderFromFile.__fields__()
      assert :id in fields
      assert :user_id in fields
      assert :symbol in fields
      assert :quantity in fields
      assert :active in fields
    end
  end
end
