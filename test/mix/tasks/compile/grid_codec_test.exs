defmodule Mix.Tasks.Compile.GridCodecTest do
  use ExUnit.Case, async: false

  describe "build_registry_ast/1" do
    test "generates valid, compilable registry with single codec" do
      codecs = [
        %{module: GridCodec.TestSupport.OrderEvent, schema_id: 60, template_id: 600}
      ]

      ast = Mix.Tasks.Compile.GridCodec.build_registry_ast(codecs, GridCodec.TestRegistry)
      assert [{GridCodec.TestRegistry, _binary}] = Code.compile_quoted(ast)

      assert {:ok, GridCodec.TestSupport.OrderEvent} = GridCodec.TestRegistry.lookup(60, 600)
      assert {:error, :unknown_codec} = GridCodec.TestRegistry.lookup(99, 99)
      assert GridCodec.TestRegistry.consolidated?()
      assert GridCodec.TestRegistry.list_codecs() == [GridCodec.TestSupport.OrderEvent]

      assert {:ok, GridCodec.TestSupport.OrderEvent} =
               GridCodec.TestRegistry.lookup_by_type("OrderEvent")

      assert {:error, :unknown_type} = GridCodec.TestRegistry.lookup_by_type("NonExistent")
      assert GridCodec.TestRegistry.clear_cache() == :ok
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

      ast = Mix.Tasks.Compile.GridCodec.build_registry_ast(codecs, GridCodec.TestRegistry2)
      assert [{GridCodec.TestRegistry2, _binary}] = Code.compile_quoted(ast)

      assert {:ok, RegCodecA} = GridCodec.TestRegistry2.lookup(9500, 9501)
      assert {:ok, RegCodecB} = GridCodec.TestRegistry2.lookup(9500, 9502)
      assert {:error, :unknown_codec} = GridCodec.TestRegistry2.lookup(9500, 9999)
    end

    test "encode and decode dispatch correctly on generated registry" do
      codecs = [
        %{module: GridCodec.TestSupport.OrderEvent, schema_id: 60, template_id: 600}
      ]

      ast = Mix.Tasks.Compile.GridCodec.build_registry_ast(codecs, GridCodec.TestRegistry3)
      [{GridCodec.TestRegistry3, _}] = Code.compile_quoted(ast)

      event = %GridCodec.TestSupport.OrderEvent{
        order_id: <<1::128>>,
        side: :buy,
        status: :open,
        price: 100,
        quantity: 10,
        timestamp: System.system_time(:microsecond)
      }

      binary = GridCodec.TestRegistry3.encode(event)
      assert {:ok, decoded} = GridCodec.TestRegistry3.decode(binary)
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

      assert {:error, conflicts} = Mix.Tasks.Compile.GridCodec.validate_codecs(codecs)
      assert length(conflicts) == 1
    end

    test "validate_codecs passes with unique ids" do
      codecs = [
        %{module: ModA, schema_id: 100, template_id: 1},
        %{module: ModB, schema_id: 100, template_id: 2}
      ]

      assert :ok = Mix.Tasks.Compile.GridCodec.validate_codecs(codecs)
    end
  end
end
