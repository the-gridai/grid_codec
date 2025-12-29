defmodule GridCodec.TypeTest do
  use ExUnit.Case

  alias GridCodec.Type

  describe "builtin_types/0" do
    test "returns map of type atoms to modules" do
      types = Type.builtin_types()

      assert is_map(types)
      assert types[:u8] == GridCodec.Types.U8
      assert types[:u64] == GridCodec.Types.U64
      assert types[:i32] == GridCodec.Types.I32
      assert types[:uuid] == GridCodec.Types.UUID
      assert types[:bool] == GridCodec.Types.Bool
      # :string is an alias for :string16
      assert types[:string] == GridCodec.Types.String16
      assert types[:string8] == GridCodec.Types.String8
      assert types[:string16] == GridCodec.Types.String16
      assert types[:string32] == GridCodec.Types.String32
    end
  end

  describe "lookup/2" do
    test "finds builtin types" do
      assert {:ok, GridCodec.Types.U64} = Type.lookup(:u64)
      assert {:ok, GridCodec.Types.Bool} = Type.lookup(:bool)
    end

    test "finds custom types" do
      custom = %{money: GridCodec.Types.I64}
      assert {:ok, GridCodec.Types.I64} = Type.lookup(:money, custom)
    end

    test "custom types override builtins" do
      custom = %{u64: GridCodec.Types.I64}
      assert {:ok, GridCodec.Types.I64} = Type.lookup(:u64, custom)
    end

    test "returns error for unknown type" do
      assert {:error, :unknown_type} = Type.lookup(:nonexistent)
    end
  end

  describe "size/1" do
    test "returns correct sizes for all builtins" do
      assert Type.size(:u8) == 1
      assert Type.size(:u16) == 2
      assert Type.size(:u32) == 4
      assert Type.size(:u64) == 8
      assert Type.size(:i8) == 1
      assert Type.size(:i16) == 2
      assert Type.size(:i32) == 4
      assert Type.size(:i64) == 8
      assert Type.size(:f32) == 4
      assert Type.size(:f64) == 8
      assert Type.size(:uuid) == 16
      assert Type.size(:bool) == 1
      assert Type.size(:string) == :variable
    end
  end

  describe "alignment/1" do
    test "returns correct alignments" do
      assert Type.alignment(:u8) == 1
      assert Type.alignment(:u16) == 2
      assert Type.alignment(:u32) == 4
      assert Type.alignment(:u64) == 8
      assert Type.alignment(:uuid) == 1
    end
  end

  describe "fixed_size?/1" do
    test "returns true for fixed types" do
      assert Type.fixed_size?(:u64) == true
      assert Type.fixed_size?(:bool) == true
      assert Type.fixed_size?(:uuid) == true
    end

    test "returns false for variable types" do
      assert Type.fixed_size?(:string) == false
    end
  end

  describe "padding_for/2" do
    test "calculates padding correctly" do
      assert Type.padding_for(0, 4) == 0
      assert Type.padding_for(1, 4) == 3
      assert Type.padding_for(2, 4) == 2
      assert Type.padding_for(3, 4) == 1
      assert Type.padding_for(4, 4) == 0
      assert Type.padding_for(5, 8) == 3
    end
  end

  describe "align/2" do
    test "aligns offset correctly" do
      assert Type.align(0, 4) == 0
      assert Type.align(1, 4) == 4
      assert Type.align(4, 4) == 4
      assert Type.align(5, 8) == 8
      assert Type.align(8, 8) == 8
    end
  end

  describe "type modules implement behaviour" do
    @types [:u8, :u16, :u32, :u64, :i8, :i16, :i32, :i64, :f32, :f64, :uuid, :bool]

    for type <- @types do
      test "#{type} implements size/0" do
        {:ok, module} = Type.lookup(unquote(type))
        assert is_integer(module.size())
      end

      test "#{type} implements alignment/0" do
        {:ok, module} = Type.lookup(unquote(type))
        assert is_integer(module.alignment())
      end

      test "#{type} implements null_value/0" do
        {:ok, module} = Type.lookup(unquote(type))
        # Just verify it's callable - value can be anything
        _ = module.null_value()
      end
    end
  end

  describe "null_values" do
    test "unsigned integers use max value" do
      assert GridCodec.Types.U8.null_value() == 255
      assert GridCodec.Types.U16.null_value() == 65_535
      assert GridCodec.Types.U32.null_value() == 4_294_967_295
      assert GridCodec.Types.U64.null_value() == 18_446_744_073_709_551_615
    end

    test "signed integers use min value" do
      assert GridCodec.Types.I8.null_value() == -128
      assert GridCodec.Types.I16.null_value() == -32_768
      assert GridCodec.Types.I32.null_value() == -2_147_483_648
      assert GridCodec.Types.I64.null_value() == -9_223_372_036_854_775_808
    end

    test "floats use NaN" do
      assert GridCodec.Types.F32.null_value() == :nan
      assert GridCodec.Types.F64.null_value() == :nan
    end

    test "bool uses 255" do
      assert GridCodec.Types.Bool.null_value() == 255
    end

    test "uuid uses zero bytes" do
      assert GridCodec.Types.UUID.null_value() == <<0::128>>
    end
  end
end
