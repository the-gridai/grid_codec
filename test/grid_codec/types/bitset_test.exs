defmodule GridCodec.Types.BitsetTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Define test bitsets
  defmodule OrderFlags do
    use GridCodec.Types.Bitset, size: :u8

    flag(:active, 0)
    flag(:verified, 1)
    flag(:premium, 2)
    flag(:suspended, 3)
  end

  defmodule ExtendedFlags do
    use GridCodec.Types.Bitset, size: :u16

    flag(:flag_0, 0)
    flag(:flag_1, 1)
    flag(:flag_8, 8)
    flag(:flag_15, 15)
  end

  defmodule LargeFlags do
    use GridCodec.Types.Bitset, size: :u32

    flag(:bit_0, 0)
    flag(:bit_16, 16)
    flag(:bit_31, 31)
  end

  describe "flag definitions" do
    test "flags/0 returns all flag names" do
      assert OrderFlags.flags() == [:active, :verified, :premium, :suspended]
    end

    test "flag_map/0 returns name to position mapping" do
      assert OrderFlags.flag_map() == %{
               active: 0,
               verified: 1,
               premium: 2,
               suspended: 3
             }
    end
  end

  describe "to_integer/1" do
    test "empty set is 0" do
      assert OrderFlags.to_integer(MapSet.new()) == 0
    end

    test "single flag" do
      assert OrderFlags.to_integer(MapSet.new([:active])) == 1
      assert OrderFlags.to_integer(MapSet.new([:verified])) == 2
      assert OrderFlags.to_integer(MapSet.new([:premium])) == 4
      assert OrderFlags.to_integer(MapSet.new([:suspended])) == 8
    end

    test "multiple flags" do
      flags = MapSet.new([:active, :premium])
      assert OrderFlags.to_integer(flags) == 5

      flags = MapSet.new([:active, :verified, :premium, :suspended])
      assert OrderFlags.to_integer(flags) == 15
    end

    test "raises on unknown flag" do
      assert_raise ArgumentError, ~r/Unknown flag/, fn ->
        OrderFlags.to_integer(MapSet.new([:unknown]))
      end
    end
  end

  describe "from_integer/1" do
    test "0 is empty set" do
      assert OrderFlags.from_integer(0) == MapSet.new()
    end

    test "single bit" do
      assert OrderFlags.from_integer(1) == MapSet.new([:active])
      assert OrderFlags.from_integer(2) == MapSet.new([:verified])
      assert OrderFlags.from_integer(4) == MapSet.new([:premium])
      assert OrderFlags.from_integer(8) == MapSet.new([:suspended])
    end

    test "multiple bits" do
      assert OrderFlags.from_integer(5) == MapSet.new([:active, :premium])
      assert OrderFlags.from_integer(15) == MapSet.new([:active, :verified, :premium, :suspended])
    end

    test "ignores undefined bits" do
      # Bit 4 (16) is not defined, should be ignored
      assert OrderFlags.from_integer(17) == MapSet.new([:active])
    end
  end

  describe "encode/1 and decode/1" do
    test "roundtrip with u8" do
      flags = MapSet.new([:active, :premium])
      binary = OrderFlags.encode(flags)

      assert byte_size(binary) == 1
      assert OrderFlags.decode(binary) == flags
    end

    test "roundtrip with u16" do
      flags = MapSet.new([:flag_0, :flag_8, :flag_15])
      binary = ExtendedFlags.encode(flags)

      assert byte_size(binary) == 2
      assert ExtendedFlags.decode(binary) == flags
    end

    test "roundtrip with u32" do
      flags = MapSet.new([:bit_0, :bit_16, :bit_31])
      binary = LargeFlags.encode(flags)

      assert byte_size(binary) == 4
      assert LargeFlags.decode(binary) == flags
    end

    test "nil encodes as empty set" do
      binary = OrderFlags.encode(nil)
      assert OrderFlags.decode(binary) == MapSet.new()
    end
  end

  describe "predicates" do
    test "flag?/1 with MapSet" do
      flags = MapSet.new([:active, :premium])

      assert OrderFlags.active?(flags) == true
      assert OrderFlags.verified?(flags) == false
      assert OrderFlags.premium?(flags) == true
      assert OrderFlags.suspended?(flags) == false
    end

    test "flag?/1 with integer" do
      integer = 5

      assert OrderFlags.active?(integer) == true
      assert OrderFlags.verified?(integer) == false
      assert OrderFlags.premium?(integer) == true
      assert OrderFlags.suspended?(integer) == false
    end
  end

  describe "GridCodec.Type behaviour" do
    test "size/0 returns byte size" do
      assert OrderFlags.size() == 1
      assert ExtendedFlags.size() == 2
      assert LargeFlags.size() == 4
    end

    test "alignment/0 equals size" do
      assert OrderFlags.alignment() == 1
      assert ExtendedFlags.alignment() == 2
      assert LargeFlags.alignment() == 4
    end

    test "null_value/0 returns max for type" do
      assert OrderFlags.null_value() == 255
      assert ExtendedFlags.null_value() == 65535
      assert LargeFlags.null_value() == 4_294_967_295
    end
  end

  describe "integration with GridCodec" do
    defmodule TestCodecWithBitset do
      use GridCodec, types: [order_flags: OrderFlags]

      defcodec do
        field :order_id, :u64
        field :flags, :order_flags
      end
    end

    test "encode/decode roundtrip" do
      flags = MapSet.new([:active, :verified])

      data = %{order_id: 123, flags: flags}
      binary = TestCodecWithBitset.encode(data)

      assert {:ok, decoded} = TestCodecWithBitset.decode(binary)
      assert decoded.order_id == 123
      assert decoded.flags == flags
    end

    test "zero-copy access" do
      flags = MapSet.new([:premium, :suspended])
      data = %{order_id: 456, flags: flags}

      binary = TestCodecWithBitset.encode(data)
      env = TestCodecWithBitset.wrap(binary)

      assert TestCodecWithBitset.get(env, :order_id) == 456
      assert TestCodecWithBitset.get(env, :flags) == flags
    end

    test "nil flags encode as empty set" do
      data = %{order_id: 789, flags: nil}
      binary = TestCodecWithBitset.encode(data)

      {:ok, decoded} = TestCodecWithBitset.decode(binary)
      assert decoded.flags == MapSet.new()
    end
  end

  describe "property tests" do
    property "roundtrip preserves flags" do
      check all(
              flags_list <- StreamData.list_of(StreamData.member_of(OrderFlags.flags())),
              max_runs: 100
            ) do
        flags = MapSet.new(flags_list)
        binary = OrderFlags.encode(flags)
        decoded = OrderFlags.decode(binary)
        assert decoded == flags
      end
    end

    property "to_integer/from_integer roundtrip" do
      check all(
              flags_list <- StreamData.list_of(StreamData.member_of(OrderFlags.flags())),
              max_runs: 100
            ) do
        flags = MapSet.new(flags_list)
        integer = OrderFlags.to_integer(flags)
        decoded = OrderFlags.from_integer(integer)
        assert decoded == flags
      end
    end
  end
end
