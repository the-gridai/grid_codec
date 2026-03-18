defmodule GridCodec.Types.EnumTest do
  use ExUnit.Case

  # Define test enums
  defmodule OrderSide do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:buy, 0)
      value(:sell, 1)
    end
  end

  defmodule OrderStatus do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:pending)
      value(:filled)
      value(:cancelled)
      value(:rejected)
    end
  end

  defmodule LargeEnum do
    use GridCodec.Types.Enum, encoding: :u16

    defenum do
      value(:type_a, 1000)
      value(:type_b, 2000)
      value(:type_c, 3000)
    end
  end

  defmodule DocumentedEnum do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:buy, 0, doc: "Bid-side order.")
      value(:sell, 1, doc: "Ask-side order.")
    end
  end

  describe "value definition" do
    test "explicit values work" do
      assert OrderSide.to_integer(:buy) == 0
      assert OrderSide.to_integer(:sell) == 1
    end

    test "auto-incremented values work" do
      assert OrderStatus.to_integer(:pending) == 0
      assert OrderStatus.to_integer(:filled) == 1
      assert OrderStatus.to_integer(:cancelled) == 2
      assert OrderStatus.to_integer(:rejected) == 3
    end

    test "values/0 returns all values" do
      values = OrderSide.values()
      assert {:buy, 0} in values
      assert {:sell, 1} in values
    end

    test "encoding/0 returns encoding type" do
      assert OrderSide.encoding() == :u8
      assert LargeEnum.encoding() == :u16
    end
  end

  describe "encode/decode" do
    test "encodes atom to binary" do
      assert OrderSide.encode(:buy) == <<0>>
      assert OrderSide.encode(:sell) == <<1>>
    end

    test "encodes integer directly" do
      assert OrderSide.encode(0) == <<0>>
      assert OrderSide.encode(1) == <<1>>
    end

    test "encodes nil as null value" do
      assert OrderSide.encode(nil) == <<255>>
    end

    test "decodes binary to atom" do
      assert OrderSide.decode(<<0>>) == {:buy, <<>>}
      assert OrderSide.decode(<<1>>) == {:sell, <<>>}
    end

    test "decodes null to nil" do
      assert OrderSide.decode(<<255>>) == {nil, <<>>}
    end

    test "decodes unknown value to integer" do
      # Unknown value 5 should return as integer
      assert OrderSide.decode(<<5>>) == {5, <<>>}
    end

    test "decodes with remaining binary" do
      assert OrderSide.decode(<<0, "rest">>) == {:buy, "rest"}
    end
  end

  describe "u16 encoding" do
    test "encodes large values" do
      assert LargeEnum.encode(:type_a) == <<232, 3>>
      assert LargeEnum.encode(:type_b) == <<208, 7>>
    end

    test "null value is 65535" do
      assert LargeEnum.null_value() == 65_535
      assert LargeEnum.encode(nil) == <<255, 255>>
    end

    test "decodes u16 values" do
      assert LargeEnum.decode(<<232, 3>>) == {:type_a, <<>>}
      assert LargeEnum.decode(<<208, 7>>) == {:type_b, <<>>}
    end
  end

  describe "type behaviour" do
    test "size returns correct value" do
      assert OrderSide.size() == 1
      assert LargeEnum.size() == 2
    end

    test "alignment equals size" do
      assert OrderSide.alignment() == 1
      assert LargeEnum.alignment() == 2
    end

    test "to_atom handles unknown values" do
      assert OrderSide.to_atom(0) == :buy
      assert OrderSide.to_atom(1) == :sell
      # Unknown value returns integer
      assert OrderSide.to_atom(99) == 99
    end

    test "to_integer raises on unknown atom" do
      assert_raise ArgumentError, ~r/Unknown enum value/, fn ->
        OrderSide.to_integer(:unknown)
      end
    end

    test "generated enum types are available" do
      assert has_type?(GridCodec.TestSupport.Side, :known, 0)
      assert has_type?(GridCodec.TestSupport.Side, :t, 0)
      assert has_type?(GridCodec.TestSupport.Side, :encoded, 0)
    end

    test "value_docs/0 returns enum value documentation" do
      assert DocumentedEnum.value_docs() == %{
               buy: "Bid-side order.",
               sell: "Ask-side order."
             }
    end
  end

  describe "roundtrip" do
    test "all values roundtrip" do
      for {name, _int} <- OrderSide.values() do
        binary = OrderSide.encode(name)
        {decoded, <<>>} = OrderSide.decode(binary)
        assert decoded == name
      end
    end

    test "nil roundtrips" do
      binary = OrderSide.encode(nil)
      {decoded, <<>>} = OrderSide.decode(binary)
      assert decoded == nil
    end
  end

  defp has_type?(module, type_name, arity) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        Enum.any?(types, fn
          {:type, {^type_name, _type_ast, args}} -> length(args) == arity
          {_, {^type_name, _type_ast, args}} -> length(args) == arity
          _ -> false
        end)

      :error ->
        false
    end
  end
end
