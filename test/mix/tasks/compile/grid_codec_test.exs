defmodule Mix.Tasks.Compile.GridCodecTest do
  use ExUnit.Case, async: false

  # credo:disable-for-this-file Credo.Check.Refactor.Apply
  # Dynamically-compiled registry modules use apply/3 to avoid
  # "module is not available or is yet to be defined" compiler warnings.

  describe "build_registry_ast/1" do
    test "generates valid, compilable registry with single codec" do
      codecs = [
        %{module: GridCodec.TestSupport.OrderEvent, schema_id: 60, template_id: 600}
      ]

      reg = GridCodec.TestRegistry
      ast = Mix.Tasks.Compile.GridCodec.build_registry_ast(codecs, reg)
      assert [{^reg, _binary}] = Code.compile_quoted(ast)

      assert {:ok, GridCodec.TestSupport.OrderEvent} = apply(reg, :lookup, [60, 600])
      assert {:error, :unknown_codec} = apply(reg, :lookup, [99, 99])
      assert apply(reg, :consolidated?, [])
      assert apply(reg, :list_codecs, []) == [GridCodec.TestSupport.OrderEvent]

      assert {:ok, GridCodec.TestSupport.OrderEvent} =
               apply(reg, :lookup_by_type, ["OrderEvent"])

      assert {:error, :unknown_type} = apply(reg, :lookup_by_type, ["NonExistent"])
      assert apply(reg, :clear_cache, []) == :ok
    end

    test "generates valid registry with multiple codecs" do
      defmodule RegCodecA do
        use GridCodec.Struct, template_id: 9501, schema_id: 9500

        defcodec do
          field :id, :u64
        end
      end

      defmodule RegCodecB do
        use GridCodec.Struct, template_id: 9502, schema_id: 9500

        defcodec do
          field :value, :u32
        end
      end

      codecs = [
        %{module: RegCodecA, schema_id: 9500, template_id: 9501},
        %{module: RegCodecB, schema_id: 9500, template_id: 9502}
      ]

      reg = GridCodec.TestRegistry2
      ast = Mix.Tasks.Compile.GridCodec.build_registry_ast(codecs, reg)
      assert [{^reg, _binary}] = Code.compile_quoted(ast)

      assert {:ok, RegCodecA} = apply(reg, :lookup, [9500, 9501])
      assert {:ok, RegCodecB} = apply(reg, :lookup, [9500, 9502])
      assert {:error, :unknown_codec} = apply(reg, :lookup, [9500, 9999])
    end

    test "encode and decode dispatch correctly on generated registry" do
      codecs = [
        %{module: GridCodec.TestSupport.OrderEvent, schema_id: 60, template_id: 600}
      ]

      reg = GridCodec.TestRegistry3
      ast = Mix.Tasks.Compile.GridCodec.build_registry_ast(codecs, reg)
      [{^reg, _}] = Code.compile_quoted(ast)

      event = %GridCodec.TestSupport.OrderEvent{
        order_id: <<1::128>>,
        side: :buy,
        status: :open,
        price: 100,
        quantity: 10,
        timestamp: System.system_time(:microsecond)
      }

      {:ok, binary} = apply(reg, :encode, [event])
      assert {:ok, decoded} = apply(reg, :decode, [binary])
      assert decoded.side == :buy
      assert decoded.price == 100
    end
  end

  describe "conflict detection" do
    test "validate_codecs detects duplicate template_ids" do
      codecs = [
        %{module: ModA, schema_id: 100, template_id: 1},
        %{module: ModB, schema_id: 100, template_id: 1}
      ]

      assert {:error, %{id_conflicts: id_conflicts, type_conflicts: type_conflicts}} =
               Mix.Tasks.Compile.GridCodec.validate_codecs(codecs)

      assert length(id_conflicts) == 1
      assert type_conflicts == []
    end

    test "validate_codecs passes with unique ids" do
      codecs = [
        %{module: ModA, schema_id: 100, template_id: 1},
        %{module: ModB, schema_id: 100, template_id: 2}
      ]

      assert :ok = Mix.Tasks.Compile.GridCodec.validate_codecs(codecs)
    end

    test "validate_codecs detects duplicate type names" do
      defmodule TypeConflictA do
        def __type__, do: "DuplicateTypeName"
      end

      defmodule TypeConflictB do
        def __type__, do: "DuplicateTypeName"
      end

      codecs = [
        %{module: TypeConflictA, schema_id: 9800, template_id: 9801},
        %{module: TypeConflictB, schema_id: 9800, template_id: 9802}
      ]

      assert {:error, %{id_conflicts: id_conflicts, type_conflicts: type_conflicts}} =
               Mix.Tasks.Compile.GridCodec.validate_codecs(codecs)

      assert id_conflicts == []
      assert [{"DuplicateTypeName", modules}] = type_conflicts
      assert Enum.sort(modules) == Enum.sort([TypeConflictA, TypeConflictB])
    end
  end
end
