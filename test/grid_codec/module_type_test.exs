defmodule GridCodec.ModuleTypeTest do
  use ExUnit.Case, async: true

  defmodule TestSide do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:buy)
      value(:sell)
    end
  end

  defmodule WithModuleType do
    use GridCodec.Struct, template_id: 750, schema_id: 75

    defcodec do
      field :id, :u64
      field :side, TestSide
      field :price, :decimal
    end
  end

  defmodule WithAliasedModuleType do
    alias GridCodec.ModuleTypeTest.TestSide, as: Side

    use GridCodec.Struct, template_id: 751, schema_id: 75

    defcodec do
      field :id, :u64
      field :side, Side
      field :price, :decimal
    end
  end

  describe "module reference as field type" do
    test "roundtrip with enum module reference" do
      struct = %WithModuleType{id: 42, side: :buy, price: Decimal.new("99.50")}
      {:ok, binary} = WithModuleType.encode(struct)
      assert {:ok, decoded} = WithModuleType.decode(binary)

      assert decoded.id == 42
      assert decoded.side == :buy
      assert Decimal.equal?(decoded.price, Decimal.new("99.50"))
    end

    test "nil enum value roundtrips" do
      struct = %WithModuleType{id: 1, side: nil, price: nil}
      {:ok, binary} = WithModuleType.encode(struct)
      assert {:ok, decoded} = WithModuleType.decode(binary)

      assert decoded.side == nil
    end

    test "aliased module reference works identically" do
      struct = %WithAliasedModuleType{id: 42, side: :sell, price: Decimal.new("100")}
      {:ok, binary} = WithAliasedModuleType.encode(struct)
      assert {:ok, decoded} = WithAliasedModuleType.decode(binary)

      assert decoded.side == :sell
    end

    test "schema metadata shows module as type" do
      schema = WithModuleType.__schema__()
      {_name, type, _opts} = Enum.find(schema.fields, fn {n, _, _} -> n == :side end)
      assert type == TestSide
    end
  end

  describe "Type.lookup with module reference" do
    test "recognizes a GridCodec type module" do
      assert {:ok, TestSide} = GridCodec.Type.lookup(TestSide)
    end

    test "rejects non-type modules" do
      assert {:error, :unknown_type} = GridCodec.Type.lookup(String)
    end

    test "builtin atoms still work" do
      assert {:ok, GridCodec.Types.U64} = GridCodec.Type.lookup(:u64)
    end
  end

  # ============================================================================
  # Cross-module compilation: types defined in separate files (test/support/)
  # This exercises the Code.ensure_compiled path that fails with ensure_loaded
  # ============================================================================

  describe "cross-module type references (separate files)" do
    alias GridCodec.TestSupport.OrderEvent

    test "roundtrip with types from separate modules" do
      struct = %OrderEvent{
        order_id: <<1::128>>,
        side: :buy,
        status: :open,
        price: 50_000,
        quantity: 100,
        timestamp: System.system_time(:microsecond)
      }

      {:ok, binary} = OrderEvent.encode(struct)
      assert {:ok, decoded} = OrderEvent.decode(binary)

      assert decoded.order_id == <<1::128>>
      assert decoded.side == :buy
      assert decoded.status == :open
      assert decoded.price == 50_000
      assert decoded.quantity == 100
    end

    test "nil custom type values roundtrip" do
      struct = %OrderEvent{
        order_id: <<1::128>>,
        side: nil,
        status: nil,
        price: 100,
        quantity: 1,
        timestamp: System.system_time(:microsecond)
      }

      {:ok, binary} = OrderEvent.encode(struct)
      assert {:ok, decoded} = OrderEvent.decode(binary)

      assert decoded.side == nil
      assert decoded.status == nil
    end

    test "all enum values roundtrip correctly" do
      for side <- [:buy, :sell], status <- [:open, :filled, :cancelled] do
        struct = %OrderEvent{
          order_id: <<1::128>>,
          side: side,
          status: status,
          price: 100,
          quantity: 1,
          timestamp: System.system_time(:microsecond)
        }

        {:ok, binary} = OrderEvent.encode(struct)
        assert {:ok, decoded} = OrderEvent.decode(binary)
        assert decoded.side == side
        assert decoded.status == status
      end
    end

    test "__type__ returns configured name" do
      assert OrderEvent.__type__() == "OrderEvent"
    end
  end
end
