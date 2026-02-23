defmodule GridCodec.Types.IntegerRangeValidationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  defmodule IntegerCodec do
    use GridCodec.Struct

    defcodec do
      field :u8v, :u8
      field :u16v, :u16
      field :u32v, :u32
      field :u64v, :u64
      field :i8v, :i8
      field :i16v, :i16
      field :i32v, :i32
      field :i64v, :i64
    end
  end

  defp valid_struct(overrides) do
    base = %IntegerCodec{
      u8v: 1,
      u16v: 2,
      u32v: 3,
      u64v: 4,
      i8v: -1,
      i16v: -2,
      i32v: -3,
      i64v: -4
    }

    struct!(base, overrides)
  end

  test "raises for unsigned overflow and underflow" do
    assert_raise ArgumentError, ~r/expects u8 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{u8v: 256}), header: false)
    end

    assert_raise ArgumentError, ~r/expects u16 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{u16v: -1}), header: false)
    end

    assert_raise ArgumentError, ~r/expects u32 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{u32v: 4_294_967_296}), header: false)
    end
  end

  test "raises for signed overflow and underflow" do
    assert_raise ArgumentError, ~r/expects i8 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{i8v: 128}), header: false)
    end

    assert_raise ArgumentError, ~r/expects i16 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{i16v: -32_769}), header: false)
    end

    assert_raise ArgumentError, ~r/expects i32 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{i32v: 2_147_483_648}), header: false)
    end
  end

  test "raises for non-integer values" do
    assert_raise ArgumentError, ~r/expects u64 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{u64v: 1.5}), header: false)
    end

    assert_raise ArgumentError, ~r/expects i64 integer/, fn ->
      IntegerCodec.encode(valid_struct(%{i64v: "5"}), header: false)
    end
  end

  property "u8 rejects any integer outside 0..255" do
    outside_range_gen =
      StreamData.one_of([
        StreamData.integer(-10_000..-1),
        StreamData.integer(256..10_000)
      ])

    check all(value <- outside_range_gen, max_runs: 50) do
      assert_raise ArgumentError, ~r/expects u8 integer/, fn ->
        IntegerCodec.encode(valid_struct(%{u8v: value}), header: false)
      end
    end
  end

  property "i16 rejects any integer outside -32768..32767" do
    outside_range_gen =
      StreamData.one_of([
        StreamData.integer(-1_000_000..-32_769),
        StreamData.integer(32_768..1_000_000)
      ])

    check all(value <- outside_range_gen, max_runs: 50) do
      assert_raise ArgumentError, ~r/expects i16 integer/, fn ->
        IntegerCodec.encode(valid_struct(%{i16v: value}), header: false)
      end
    end
  end
end
