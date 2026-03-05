defmodule GridCodec.PinMatchTest do
  use ExUnit.Case, async: true

  defmodule Event do
    use GridCodec.Struct, template_id: 99, schema_id: 99

    defcodec do
      field :id, :u64
      field :status, :u8
      field :flags, :u8
      field :value, :u32
    end
  end

  defmodule Order do
    use GridCodec.Struct, template_id: 98, schema_id: 99

    defcodec do
      field :order_id, :u64
      field :price, :decimal
      field :quantity, :u32
    end
  end

  describe "pin on primitive types" do
    setup do
      struct = %Event{id: 42, status: 2, flags: 7, value: 1000}
      {:ok, bin} = Event.encode(struct)
      %{bin: bin}
    end

    test "pin matches correct value", %{bin: bin} do
      require Event
      expected = 2
      assert match?(Event.match(status: ^expected), bin)
    end

    test "pin rejects wrong value", %{bin: bin} do
      require Event
      wrong = 99
      refute match?(Event.match(status: ^wrong), bin)
    end

    test "pin + variable binding", %{bin: bin} do
      require Event
      expected_id = 42

      case bin do
        Event.match(id: ^expected_id, value: v) ->
          assert v == 1000

        _ ->
          flunk("pin + binding should have matched")
      end
    end

    test "pin + literal together", %{bin: bin} do
      require Event
      expected_flags = 7
      assert match?(Event.match(status: 2, flags: ^expected_flags), bin)
    end

    test "pin in function dispatch", %{bin: bin} do
      require Event

      dispatch = fn bin, expected_status ->
        case bin do
          Event.match(status: ^expected_status) -> {:matched, expected_status}
          _ -> :no_match
        end
      end

      assert dispatch.(bin, 2) == {:matched, 2}
      assert dispatch.(bin, 99) == :no_match
    end
  end

  describe "pin on custom types (decimal) via encode_field" do
    setup do
      price = Decimal.new("123.45")
      struct = %Order{order_id: 1, price: price, quantity: 100}
      {:ok, bin} = Order.encode(struct)
      %{bin: bin, price: price}
    end

    test "encode_field + pin matches correct value", %{bin: bin, price: price} do
      require Order
      encoded = Order.encode_field(:price, price)
      assert match?(Order.match(price: ^encoded), bin)
    end

    test "encode_field + pin rejects wrong value", %{bin: bin} do
      require Order
      encoded = Order.encode_field(:price, Decimal.new("999.99"))
      refute match?(Order.match(price: ^encoded), bin)
    end

    test "encode_field + pin + binding", %{bin: bin, price: price} do
      require Order
      encoded = Order.encode_field(:price, price)

      case bin do
        Order.match(price: ^encoded, quantity: q) ->
          assert q == 100

        _ ->
          flunk("decimal pin + binding should have matched")
      end
    end

    test "encode_field with tuple form", %{bin: bin} do
      require Order
      encoded = Order.encode_field(:price, {12345, -2})
      assert match?(Order.match(price: ^encoded), bin)
    end

    test "encode_field in dynamic dispatch", %{bin: bin} do
      require Order

      dispatch = fn bin, target_price ->
        encoded = Order.encode_field(:price, target_price)

        case bin do
          Order.match(price: ^encoded) -> :found
          _ -> :not_found
        end
      end

      assert dispatch.(bin, Decimal.new("123.45")) == :found
      assert dispatch.(bin, Decimal.new("0.01")) == :not_found
    end

    test "literal nil matches decimal null sentinel" do
      require Order

      {:ok, null_bin} = Order.encode(%Order{order_id: 1, price: nil, quantity: 100})

      {:ok, non_null_bin} =
        Order.encode(%Order{order_id: 1, price: Decimal.new("123.45"), quantity: 100})

      assert match?(Order.match(price: nil), null_bin)
      refute match?(Order.match(price: nil), non_null_bin)
    end
  end
end
