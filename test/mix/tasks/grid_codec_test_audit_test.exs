defmodule Mix.Tasks.GridCodec.TestAuditTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.GridCodec.TestAudit

  describe "audit/3" do
    test "treats full module references as covered" do
      modules = [{"GridCodec.Types.Bitset", "lib/grid_codec/types/bitset.ex"}]
      tests = ["defmodule FooTest do\n  alias GridCodec.Types.Bitset\nend\n"]

      assert TestAudit.audit(modules, tests, []) == []
    end

    test "treats aliased last-segment references as covered" do
      modules = [{"GridCodec.Types.DateTimeMicros", "lib/grid_codec/types/datetime.ex"}]
      tests = ["defmodule FooTest do\n  alias GridCodec.Types.DateTimeMicros\nend\n"]

      assert TestAudit.audit(modules, tests, []) == []
    end

    test "ignores configured modules" do
      modules = [{"GridCodec.Struct.Compiler", "lib/grid_codec/struct/compiler.ex"}]

      assert TestAudit.audit(modules, [""], [GridCodec.Struct.Compiler]) == []
    end

    test "returns modules that have no matching test reference" do
      modules = [{"GridCodec.Types.CharArray", "lib/grid_codec/types/char_array.ex"}]

      assert TestAudit.audit(modules, ["defmodule OtherTest do\nend\n"], []) == modules
    end
  end
end
