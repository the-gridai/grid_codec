defmodule GridCodec.Schema.SigilTest do
  use ExUnit.Case, async: true

  import GridCodec.Schema.Sigil

  describe "~g sigil" do
    test "parses simple schema" do
      schema = ~g"""
      schema { id: 100 }
      struct Order (template_id: 1001) {
        id: uuid_string
        quantity: u32
      }
      """

      assert schema.id == 100
      assert Map.has_key?(schema.structs, :Order)
      assert schema.structs[:Order].template_id == 1001
    end

    test "parses schema with name" do
      schema = ~g"""
      schema Trading {
        id: 200
        version: 2
      }
      """

      assert schema.name == :Trading
      assert schema.id == 200
      assert schema.version == 2
    end

    test "parses multiple structs" do
      schema = ~g"""
      schema { id: 1 }
      struct Order (template_id: 1001) { id: uuid_string }
      struct Trade (template_id: 1002) { trade_id: uuid_string }
      """

      assert map_size(schema.structs) == 2
      assert schema.structs[:Order].template_id == 1001
      assert schema.structs[:Trade].template_id == 1002
    end

    test "parses enums" do
      schema = ~g"""
      schema { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      """

      assert Map.has_key?(schema.enums, :Side)
      assert schema.enums[:Side].underlying_type == :u8
      assert schema.enums[:Side].values == [buy: 1, sell: 2]
    end

    test "parses composite types" do
      schema = ~g"""
      schema { id: 1 }
      type Price {
        mantissa: i64
        exponent: i8
      }
      """

      assert Map.has_key?(schema.types, :Price)
      assert length(schema.types[:Price].fields) == 2
    end

    test "parses struct with version override" do
      schema = ~g"""
      schema { id: 1 version: 1 }
      struct Order (template_id: 1001, version: 3) {
        id: uuid_string
      }
      """

      assert schema.structs[:Order].version == 3
    end
  end

  describe "~G sigil (no interpolation)" do
    test "parses schema at compile time" do
      schema = ~G"""
      schema { id: 100 }
      struct Order (template_id: 1001) {
        id: uuid_string
      }
      """

      assert schema.id == 100
      assert schema.structs[:Order].template_id == 1001
    end
  end

  describe "using sigil with GridCodec.Struct" do
    # Define module using sigil
    defmodule OrderFromSigil do
      use GridCodec.Struct,
        grid_schema: ~G"""
          schema { id: 300 version: 1 }
          struct Order (template_id: 3001) {
            id: uuid_string
            user_id: u64
            quantity: u32
          }
        """,
        message: :Order
    end

    test "creates struct with correct fields" do
      order = %OrderFromSigil{}
      assert Map.has_key?(order, :id)
      assert Map.has_key?(order, :user_id)
      assert Map.has_key?(order, :quantity)
    end

    test "has correct metadata" do
      assert OrderFromSigil.__template_id__() == 3001
      assert OrderFromSigil.__schema_id__() == 300
      assert OrderFromSigil.__version__() == 1
    end

    test "encode/decode roundtrip works" do
      order = %OrderFromSigil{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 12345,
        quantity: 100
      }

      binary = OrderFromSigil.encode(order)
      {:ok, decoded} = OrderFromSigil.decode(binary)

      assert decoded.id == order.id
      assert decoded.user_id == order.user_id
      assert decoded.quantity == order.quantity
    end
  end

  describe "sigil equivalence with DSL" do
    defmodule OrderDSL do
      use GridCodec.Struct,
        template_id: 4001,
        schema_id: 400,
        version: 1

      defcodec do
        field :id, :uuid_string
        field :amount, :u64
      end
    end

    defmodule OrderSigil do
      use GridCodec.Struct,
        grid_schema: ~G"""
          schema { id: 400 version: 1 }
          struct Order (template_id: 4001) {
            id: uuid_string
            amount: u64
          }
        """,
        message: :Order
    end

    test "same template_id" do
      assert OrderDSL.__template_id__() == OrderSigil.__template_id__()
    end

    test "same schema_id" do
      assert OrderDSL.__schema_id__() == OrderSigil.__schema_id__()
    end

    test "same fields" do
      assert Enum.sort(OrderDSL.__fields__()) == Enum.sort(OrderSigil.__fields__())
    end

    test "encode produces identical binary" do
      data = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        amount: 99999
      }

      dsl_binary = OrderDSL.encode(struct(OrderDSL, data))
      sigil_binary = OrderSigil.encode(struct(OrderSigil, data))

      assert dsl_binary == sigil_binary
    end
  end
end
