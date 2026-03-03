defmodule GridCodec.CompareTest do
  use ExUnit.Case, async: true

  defmodule SideEnum do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:buy, 1)
      value(:sell, 2)
    end
  end

  defmodule CompareCodec do
    use GridCodec.Struct, template_id: 9001, schema_id: 42

    defcodec do
      field :id, :u64
      field :price, :u64
      field :delta, :i32
      field :amount, :decimal
      field :side, SideEnum
      field :note, :string16
    end
  end

  describe "GridCodec.compare/5 with value rhs" do
    test "compares integer fields without full decode" do
      require CompareCodec
      binary = CompareCodec.encode(%CompareCodec{id: 1, price: 100, delta: -5})

      assert GridCodec.compare(binary, CompareCodec.field(:price), :>, 90)
      refute GridCodec.compare(binary, CompareCodec.field(:price), :<, 90)
      assert GridCodec.compare(binary, CompareCodec.field(:delta), :==, -5)
      assert GridCodec.compare(binary, CompareCodec.field(:delta), :!=, 10)
    end

    test "compares decimal fields using decimal semantics" do
      require CompareCodec

      binary =
        CompareCodec.encode(%CompareCodec{id: 1, amount: Decimal.new("12.34"), side: :buy})

      assert GridCodec.compare(binary, CompareCodec.field(:amount), :==, Decimal.new("12.340"))
      assert GridCodec.compare(binary, CompareCodec.field(:amount), :>, Decimal.new("12.33"))
      assert GridCodec.compare(binary, CompareCodec.field(:amount), :<, {1235, -2})
    end

    test "compares enum values by encoded integer ordering" do
      require CompareCodec
      binary = CompareCodec.encode(%CompareCodec{id: 1, side: :buy})

      assert GridCodec.compare(binary, CompareCodec.field(:side), :<, :sell)
      assert GridCodec.compare(binary, CompareCodec.field(:side), :==, :buy)
      refute GridCodec.compare(binary, CompareCodec.field(:side), :>, :sell)
    end
  end

  describe "binary-to-binary comparison" do
    test "compare with rhs: :binary extracts same field from rhs binary" do
      require CompareCodec
      low = CompareCodec.encode(%CompareCodec{id: 1, price: 100})
      high = CompareCodec.encode(%CompareCodec{id: 2, price: 150})
      spec = CompareCodec.field(:price)

      assert GridCodec.compare(high, spec, :>, low, rhs: :binary)
      assert GridCodec.compare_binaries(high, spec, :>=, low)
      refute GridCodec.compare(low, spec, :>, high, rhs: :binary)
    end
  end

  describe "codec compare macro" do
    test "inlines fixed-field compare operations" do
      require CompareCodec

      low = CompareCodec.encode(%CompareCodec{id: 1, price: 100}, header: false)
      high = CompareCodec.encode(%CompareCodec{id: 2, price: 200}, header: false)

      assert CompareCodec.compare(high, :price, :>, 150, header: false)
      assert CompareCodec.compare(high, :price, :>, low, header: false, rhs: :binary)
      refute CompareCodec.compare(low, :price, :>, high, header: false, rhs: :binary)
    end
  end

  describe "unsupported field classes" do
    test "variable-length fields require full decode for compare" do
      require CompareCodec
      binary = CompareCodec.encode(%CompareCodec{id: 1, note: "hello"})

      assert_raise ArgumentError, ~r/Variable-length field :note requires full decode/, fn ->
        GridCodec.compare(binary, CompareCodec.field(:note), :==, "hello")
      end
    end

    test "raises on unsupported operators" do
      require CompareCodec
      binary = CompareCodec.encode(%CompareCodec{id: 1, price: 100})

      assert_raise ArgumentError, ~r/unsupported compare operator/, fn ->
        GridCodec.compare(binary, CompareCodec.field(:price), :in, 100)
      end
    end
  end
end
