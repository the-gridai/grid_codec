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
      binary = WithModuleType.encode(struct)
      assert {:ok, decoded} = WithModuleType.decode(binary)

      assert decoded.id == 42
      assert decoded.side == :buy
      assert Decimal.equal?(decoded.price, Decimal.new("99.50"))
    end

    test "nil enum value roundtrips" do
      struct = %WithModuleType{id: 1, side: nil, price: nil}
      binary = WithModuleType.encode(struct)
      assert {:ok, decoded} = WithModuleType.decode(binary)

      assert decoded.side == nil
    end

    test "aliased module reference works identically" do
      struct = %WithAliasedModuleType{id: 42, side: :sell, price: Decimal.new("100")}
      binary = WithAliasedModuleType.encode(struct)
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
end
