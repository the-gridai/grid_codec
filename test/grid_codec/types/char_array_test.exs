defmodule GridCodec.Types.CharArrayTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defmodule SchemaBoundCode4 do
    use GridCodec.Types.CharArray, length: 4, schema: "events"
  end

  describe "compile-time code generation" do
    test "on_overflow: :error does not emit impossible-branch warnings" do
      module_name = Module.concat(__MODULE__, :"Probe#{System.unique_integer([:positive])}")

      warning_output =
        capture_io(:stderr, fn ->
          Code.compiler_options(ignore_module_conflict: true)

          Code.compile_string("""
          defmodule #{inspect(module_name)} do
            use GridCodec.Types.CharArray, length: 4, on_overflow: :error
          end
          """)
        end)

      refute warning_output =~ "comparison between distinct types found"
      refute warning_output =~ "will never match"
      refute warning_output =~ "encode_ast/4"
    end
  end

  describe "overflow behavior" do
    defmodule Code4Strict do
      use GridCodec.Types.CharArray, length: 4, on_overflow: :error
    end

    defmodule Code4Truncate do
      use GridCodec.Types.CharArray, length: 4, on_overflow: :truncate
    end

    test "strict mode still raises on oversized strings" do
      assert_raise ArgumentError, ~r/exceeds char array length 4/, fn ->
        Code4Strict.encode("ABCDE")
      end
    end

    test "truncate mode still truncates oversized strings" do
      assert Code4Truncate.encode("ABCDE") == "ABCD"
    end
  end

  describe "__char_array_meta__/0" do
    test "returns length and schema affinity" do
      assert SchemaBoundCode4.__char_array_meta__() == %{length: 4, schema: "events"}
    end
  end
end
