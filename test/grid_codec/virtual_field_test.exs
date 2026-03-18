defmodule GridCodec.VirtualFieldTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  defp assert_only_expected_warning(stderr, expected_fragment) do
    assert stderr =~ "warning:"
    assert stderr =~ expected_fragment
    assert Regex.scan(~r/\bwarning:/, stderr) |> length() == 1
  end

  defmodule BasicVirtual do
    use GridCodec.Struct, template_id: 8000, schema_id: 80, version: 1

    defcodec do
      field :id, :u64
      field :name, :string16

      virtual(:metadata, default: %{})
      virtual(:tags, default: [])
    end
  end

  defmodule NoValidateVirtual do
    use GridCodec.Struct, template_id: 8001, schema_id: 80, version: 1

    defcodec do
      field :id, :u64

      virtual(:cache, default: %{}, validate: false)
      virtual(:tracked, default: :idle)
    end
  end

  defmodule NilDefaultVirtual do
    use GridCodec.Struct, template_id: 8002, schema_id: 80, version: 1

    defcodec do
      field :count, :u32

      virtual(:extra)
    end
  end

  describe "struct definition" do
    test "virtual fields exist in the struct with defaults" do
      basic = %BasicVirtual{}
      assert basic.metadata == %{}
      assert basic.tags == []
    end

    test "virtual fields default to nil when no default given" do
      s = %NilDefaultVirtual{}
      assert s.extra == nil
    end

    test "virtual fields can be set directly on struct" do
      s = %BasicVirtual{id: 1, name: "hello", metadata: %{foo: :bar}, tags: [:a]}
      assert s.metadata == %{foo: :bar}
      assert s.tags == [:a]
    end
  end

  describe "encode/decode roundtrip" do
    test "virtual fields are excluded from binary — roundtrip preserves wire fields only" do
      original = %BasicVirtual{id: 42, name: "test", metadata: %{key: "val"}, tags: [:important]}

      {:ok, binary} = BasicVirtual.encode(original)
      {:ok, decoded} = BasicVirtual.decode(binary)

      assert decoded.id == 42
      assert decoded.name == "test"
      assert decoded.metadata == %{}
      assert decoded.tags == []
    end

    test "binary size is not affected by virtual field values" do
      small = %BasicVirtual{id: 1, name: "a", metadata: %{}}
      big = %BasicVirtual{id: 1, name: "a", metadata: %{a: 1, b: 2, c: List.duplicate(0, 1000)}}

      {:ok, bin1} = BasicVirtual.encode(small)
      {:ok, bin2} = BasicVirtual.encode(big)

      assert byte_size(bin1) == byte_size(bin2)
    end
  end

  describe "new/1 with validate: true (default)" do
    test "accepts virtual fields from atom-keyed attrs" do
      {:ok, s} = BasicVirtual.new(%{id: 10, name: "hi", metadata: %{a: 1}, tags: [:x]})

      assert s.id == 10
      assert s.name == "hi"
      assert s.metadata == %{a: 1}
      assert s.tags == [:x]
    end

    test "accepts virtual fields from string-keyed attrs" do
      {:ok, s} = BasicVirtual.new(%{"id" => "10", "name" => "hi", "metadata" => %{b: 2}})

      assert s.id == 10
      assert s.name == "hi"
      assert s.metadata == %{b: 2}
    end

    test "uses default when virtual field not provided" do
      {:ok, s} = BasicVirtual.new(%{id: 5, name: "x"})

      assert s.metadata == %{}
      assert s.tags == []
    end

    test "nil default virtual field: passes through from new/1" do
      {:ok, s} = NilDefaultVirtual.new(%{count: 7, extra: :something})
      assert s.extra == :something
    end

    test "nil default virtual field: defaults to nil when not provided" do
      {:ok, s} = NilDefaultVirtual.new(%{count: 7})
      assert s.extra == nil
    end
  end

  describe "new/1 with validate: false" do
    test "ignores virtual field from attrs — always uses struct default" do
      {:ok, s} = NoValidateVirtual.new(%{id: 1, cache: %{stale: true}})

      assert s.id == 1
      assert s.cache == %{}
    end

    test "validate: true virtual fields are still accepted" do
      {:ok, s} = NoValidateVirtual.new(%{id: 1, tracked: :active})

      assert s.tracked == :active
    end
  end

  describe "schema introspection" do
    test "__schema__/0 includes virtual_fields metadata" do
      schema = BasicVirtual.__schema__()

      assert is_list(schema.virtual_fields)
      assert length(schema.virtual_fields) == 2

      meta = Enum.find(schema.virtual_fields, &(&1.name == :metadata))
      assert meta.default == %{}
      assert meta.validate == true

      tags = Enum.find(schema.virtual_fields, &(&1.name == :tags))
      assert tags.default == []
      assert tags.validate == true
    end

    test "__schema__/0 tracks validate option correctly" do
      schema = NoValidateVirtual.__schema__()

      cache = Enum.find(schema.virtual_fields, &(&1.name == :cache))
      assert cache.validate == false

      tracked = Enum.find(schema.virtual_fields, &(&1.name == :tracked))
      assert tracked.validate == true
    end

    test "virtual fields are NOT in fixed_fields or var_fields" do
      schema = BasicVirtual.__schema__()

      assert :metadata not in schema.fixed_fields
      assert :metadata not in schema.var_fields
      assert :tags not in schema.fixed_fields
      assert :tags not in schema.var_fields
    end
  end

  describe "compile-time validation" do
    test "rejects virtual field with same name as a wire field" do
      stderr =
        capture_io(:stderr, fn ->
          assert_raise CompileError, ~r/conflicts with an existing field/, fn ->
            defmodule ConflictVirtual do
              use GridCodec.Struct, template_id: 8090, schema_id: 80, version: 1

              defcodec do
                field :id, :u64
                virtual(:id, default: nil)
              end
            end
          end
        end)

      assert_only_expected_warning(stderr, "duplicate key :id found in struct")
    end

    test "rejects duplicate virtual field names" do
      stderr =
        capture_io(:stderr, fn ->
          assert_raise CompileError, ~r/Duplicate virtual field/, fn ->
            defmodule DuplicateVirtual do
              use GridCodec.Struct, template_id: 8091, schema_id: 80, version: 1

              defcodec do
                field :id, :u64
                virtual(:cache, default: %{})
                virtual(:cache, default: [])
              end
            end
          end
        end)

      assert_only_expected_warning(stderr, "duplicate key :cache found in struct")
    end
  end
end
