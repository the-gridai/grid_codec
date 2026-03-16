defmodule GridCodec.Types.BitsetTest do
  use ExUnit.Case, async: true

  defmodule SchemaBoundFlags do
    use GridCodec.Types.Bitset, size: :u16, schema: "events"

    flag(:read, 0)
    flag(:write, 1)
    flag(:execute, 2)
  end

  describe "__bitset_meta__/0" do
    test "returns size, ordered flags, and schema affinity" do
      assert SchemaBoundFlags.__bitset_meta__() == %{
               size: :u16,
               flags: [read: 0, write: 1, execute: 2],
               schema: "events"
             }
    end
  end

  describe "public helpers" do
    test "flags/0 and flag_map/0 expose compile-time definitions" do
      assert SchemaBoundFlags.flags() == [:read, :write, :execute]
      assert SchemaBoundFlags.flag_map() == %{read: 0, write: 1, execute: 2}
    end
  end
end
