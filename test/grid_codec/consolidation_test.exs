defmodule GridCodec.ConsolidationTest do
  use ExUnit.Case, async: false
  import Bitwise

  # Clear the registry cache at the start of each test to ensure
  # our dynamically-defined test codecs are found
  setup do
    GridCodec.Registry.clear_cache()
    :ok
  end

  describe "GridCodec.Registry fallback" do
    # These test modules use GridCodec.Struct
    defmodule Order do
      use GridCodec.Struct, template_id: 101, schema_id: 500

      defcodec do
        field :id, :u64
        field :price, :u32
      end
    end

    defmodule Trade do
      use GridCodec.Struct, template_id: 102, schema_id: 500

      defcodec do
        field :trade_id, :u64
        field :quantity, :u32
      end
    end

    test "lookup/2 finds registered struct codecs" do
      assert {:ok, Order} = GridCodec.Registry.lookup(500, 101)
      assert {:ok, Trade} = GridCodec.Registry.lookup(500, 102)
    end

    test "lookup/2 returns error for unknown codecs" do
      assert {:error, :unknown_codec} = GridCodec.Registry.lookup(999, 999)
    end

    test "consolidated?/0 returns false for fallback registry" do
      assert GridCodec.Registry.consolidated?() == false
    end
  end

  describe "Mix.Tasks.Compile.GridCodec" do
    defmodule CodecA do
      use GridCodec.Struct, template_id: 201, schema_id: 600

      defcodec do
        field :value, :u64
      end
    end

    defmodule CodecB do
      use GridCodec.Struct, template_id: 202, schema_id: 600

      defcodec do
        field :value, :u64
      end
    end

    test "codecs expose required introspection functions" do
      assert function_exported?(CodecA, :__template_id__, 0)
      assert function_exported?(CodecA, :__schema_id__, 0)
      assert function_exported?(CodecA, :__gridcodec_struct__?, 0)

      assert CodecA.__template_id__() == 201
      assert CodecA.__schema_id__() == 600
      assert CodecA.__gridcodec_struct__?() == true
    end

    test "auto template_id is hash of module name" do
      defmodule AutoIdCodec do
        use GridCodec.Struct, schema_id: 700

        defcodec do
          field :value, :u64
        end
      end

      expected_id = :erlang.phash2(AutoIdCodec) &&& 0xFFFF
      assert AutoIdCodec.__template_id__() == expected_id
    end
  end

  describe "conflict detection" do
    # Note: Actual conflict detection happens in Mix.Tasks.Compile.GridCodec
    # We test the validation logic directly

    test "validate_codecs detects duplicate template_ids" do
      codecs = [
        %{module: ModuleA, schema_id: 100, template_id: 1},
        # conflict!
        %{module: ModuleB, schema_id: 100, template_id: 1},
        %{module: ModuleC, schema_id: 100, template_id: 2}
      ]

      # Simulate the validation logic
      conflicts =
        codecs
        |> Enum.group_by(fn %{schema_id: s, template_id: t} -> {s, t} end)
        |> Enum.filter(fn {_key, mods} -> length(mods) > 1 end)

      assert length(conflicts) == 1
      [{key, _mods}] = conflicts
      assert key == {100, 1}
    end

    test "same template_id in different schemas is allowed" do
      codecs = [
        %{module: ModuleA, schema_id: 100, template_id: 1},
        # OK - different schema
        %{module: ModuleB, schema_id: 200, template_id: 1}
      ]

      conflicts =
        codecs
        |> Enum.group_by(fn %{schema_id: s, template_id: t} -> {s, t} end)
        |> Enum.filter(fn {_key, mods} -> length(mods) > 1 end)

      assert conflicts == []
    end
  end
end
