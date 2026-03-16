defmodule GridCodec.TypeNameTest do
  use ExUnit.Case, async: true

  # ============================================================================
  # Test modules with explicit and default type names
  # ============================================================================

  defmodule ExplicitName do
    use GridCodec.Struct, template_id: 700, schema_id: 70, name: "OrderSubmitted"

    defcodec do
      field :id, :u64
    end
  end

  defmodule ExplicitAtomName do
    use GridCodec.Struct, template_id: 701, schema_id: 70, name: :TradeFilled

    defcodec do
      field :id, :u64
    end
  end

  defmodule DefaultName do
    use GridCodec.Struct, template_id: 702, schema_id: 70

    defcodec do
      field :id, :u64
    end
  end

  # Deeply nested module to verify the default uses last segment only
  defmodule Deep.Nested.Module.EventCreated do
    use GridCodec.Struct, template_id: 703, schema_id: 70

    defcodec do
      field :id, :u64
    end
  end

  # ============================================================================
  # Tests: __type__/0
  # ============================================================================

  describe "__type__/0" do
    test "returns explicit string name" do
      assert ExplicitName.__type__() == "OrderSubmitted"
    end

    test "returns explicit atom name as string" do
      assert ExplicitAtomName.__type__() == "TradeFilled"
    end

    test "defaults to full module path" do
      assert DefaultName.__type__() == "GridCodec.TypeNameTest.DefaultName"
    end

    test "deeply nested module uses full path" do
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      assert Deep.Nested.Module.EventCreated.__type__() ==
               "GridCodec.TypeNameTest.Deep.Nested.Module.EventCreated"
    end
  end

  # ============================================================================
  # Tests: Schema metadata
  # ============================================================================

  describe "schema metadata includes type" do
    test "explicit name in schema" do
      assert ExplicitName.__schema__().type == "OrderSubmitted"
    end

    test "default name in schema" do
      assert DefaultName.__schema__().type == "GridCodec.TypeNameTest.DefaultName"
    end
  end

  # ============================================================================
  # Tests: Registry lookup_by_type
  # ============================================================================

  describe "lookup_by_type/1" do
    test "finds module by explicit type name" do
      assert {:ok, ExplicitName} = GridCodec.Registry.lookup_by_type("OrderSubmitted")
    end

    test "finds module by default type name" do
      assert {:ok, DefaultName} =
               GridCodec.Registry.lookup_by_type("GridCodec.TypeNameTest.DefaultName")
    end

    test "returns error for unknown type" do
      assert {:error, :unknown_type} = GridCodec.Registry.lookup_by_type("NonExistent")
    end
  end

  # ============================================================================
  # Tests: Compile-time usability
  # ============================================================================

  describe "compile-time type name access" do
    test "type name can be pinned in pattern match" do
      type = ExplicitName.__type__()
      event_type = "OrderSubmitted"

      assert match?(^type, event_type)
    end

    test "type name is a binary literal at runtime" do
      assert is_binary(ExplicitName.__type__())
      assert is_binary(DefaultName.__type__())
    end
  end

  describe "compile-time type name uniqueness" do
    test "raises when two modules use the same type name" do
      suffix = System.unique_integer([:positive])
      mod_a = Module.concat(__MODULE__, :"DuplicateTypeA#{suffix}")
      mod_b = Module.concat(__MODULE__, :"DuplicateTypeB#{suffix}")
      type_name = "DuplicateTypeName#{suffix}"

      code = """
      defmodule #{inspect(mod_a)} do
        use GridCodec.Struct, template_id: 19_001, schema_id: 190, name: "#{type_name}"

        defcodec do
          field :id, :u64
        end
      end

      defmodule #{inspect(mod_b)} do
        use GridCodec.Struct, template_id: 19_002, schema_id: 190, name: "#{type_name}"

        defcodec do
          field :id, :u64
        end
      end
      """

      assert_raise CompileError, ~r/GridCodec type name collision: "#{type_name}"/, fn ->
        Code.compile_string(code)
      end
    end
  end
end
