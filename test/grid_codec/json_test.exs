defmodule GridCodec.JsonTest do
  use ExUnit.Case, async: true

  alias GridCodec.Json

  defmodule TestOrder do
    use GridCodec.Struct, template_id: 8001

    defcodec do
      field :id, :uuid_string
      field :user_id, :u64
      field :symbol, :string16
      field :quantity, :u32
      field :active, :bool
    end
  end

  describe "encode/3" do
    test "encodes GridCodec binary to JSON" do
      order = %TestOrder{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 12345,
        symbol: "BTC/USD",
        quantity: 100,
        active: true
      }

      binary = TestOrder.encode(order)
      assert {:ok, json} = Json.encode(binary, TestOrder)

      decoded = Jason.decode!(json)
      assert decoded["id"] == "550e8400-e29b-41d4-a716-446655440000"
      assert decoded["user_id"] == 12345
      assert decoded["symbol"] == "BTC/USD"
      assert decoded["quantity"] == 100
      assert decoded["active"] == true
    end

    test "encodes with pretty printing" do
      order = %TestOrder{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 1,
        symbol: "X",
        quantity: 1,
        active: true
      }

      binary = TestOrder.encode(order)
      {:ok, json} = Json.encode(binary, TestOrder, pretty: true)

      assert String.contains?(json, "\n")
    end

    test "returns error for invalid binary" do
      assert {:error, _} = Json.encode(<<1, 2, 3>>, TestOrder)
    end
  end

  describe "encode!/3" do
    test "returns JSON string on success" do
      order = %TestOrder{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 1,
        symbol: "X",
        quantity: 1,
        active: false
      }

      binary = TestOrder.encode(order)
      json = Json.encode!(binary, TestOrder)

      assert is_binary(json)
      assert String.contains?(json, "550e8400")
    end

    test "raises on error" do
      assert_raise RuntimeError, ~r/Failed to encode/, fn ->
        Json.encode!(<<1, 2, 3>>, TestOrder)
      end
    end
  end

  describe "decode/3" do
    test "decodes JSON to GridCodec binary" do
      json =
        ~s({"id":"550e8400-e29b-41d4-a716-446655440000","user_id":12345,"symbol":"BTC/USD","quantity":100,"active":true})

      assert {:ok, binary} = Json.decode(json, TestOrder)
      assert {:ok, order} = TestOrder.decode(binary)

      assert order.id == "550e8400-e29b-41d4-a716-446655440000"
      assert order.user_id == 12345
      assert order.symbol == "BTC/USD"
      assert order.quantity == 100
      assert order.active == true
    end

    test "handles missing fields as nil" do
      json = ~s({"id":"550e8400-e29b-41d4-a716-446655440000","user_id":1})

      assert {:ok, binary} = Json.decode(json, TestOrder)
      assert {:ok, order} = TestOrder.decode(binary)

      assert order.id == "550e8400-e29b-41d4-a716-446655440000"
      assert order.symbol == nil
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode_error, _}} = Json.decode("not json", TestOrder)
    end
  end

  describe "decode!/3" do
    test "returns binary on success" do
      json =
        ~s({"id":"550e8400-e29b-41d4-a716-446655440000","user_id":1,"symbol":"X","quantity":1,"active":false})

      binary = Json.decode!(json, TestOrder)
      assert is_binary(binary)
    end

    test "raises on error" do
      assert_raise RuntimeError, ~r/Failed to decode/, fn ->
        Json.decode!("not json", TestOrder)
      end
    end
  end

  describe "roundtrip" do
    test "encode then decode preserves data" do
      order = %TestOrder{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 99999,
        symbol: "ETH/BTC",
        quantity: 500,
        active: true
      }

      binary1 = TestOrder.encode(order)
      {:ok, json} = Json.encode(binary1, TestOrder)
      {:ok, binary2} = Json.decode(json, TestOrder)
      {:ok, order2} = TestOrder.decode(binary2)

      assert order.id == order2.id
      assert order.user_id == order2.user_id
      assert order.symbol == order2.symbol
      assert order.quantity == order2.quantity
      assert order.active == order2.active
    end
  end
end
