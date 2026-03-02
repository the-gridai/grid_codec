defmodule GridCodec.SchemaEvolutionTest do
  use ExUnit.Case, async: true

  # ============================================================================
  # Test Modules: V1 and V2 codecs with same template_id/schema_id
  # ============================================================================

  defmodule EventV1 do
    use GridCodec.Struct, template_id: 900, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
      field :price, :u32
    end
  end

  defmodule EventV2 do
    use GridCodec.Struct, template_id: 900, schema_id: 50, version: 2

    defcodec do
      field :id, :u64
      field :price, :u32
      field :quantity, :u32, since: 2
    end
  end

  defmodule EventV3 do
    use GridCodec.Struct, template_id: 900, schema_id: 50, version: 3

    defcodec do
      field :id, :u64
      field :price, :u32
      field :quantity, :u32, since: 2
      field :discount, :u16, since: 3
    end
  end

  # V1 and V2 with variable-length fields
  defmodule WithStringV1 do
    use GridCodec.Struct, template_id: 901, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
      field :name, :string
    end
  end

  defmodule WithStringV2 do
    use GridCodec.Struct, template_id: 901, schema_id: 50, version: 2

    defcodec do
      field :id, :u64
      field :score, :u32, since: 2
      field :name, :string
    end
  end

  # V1 and V2 with variable-length fields AND nil v1 values
  defmodule WithStringV1AllNil do
    use GridCodec.Struct, template_id: 903, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
      field :price, :u32
    end
  end

  defmodule WithStringV2AllNil do
    use GridCodec.Struct, template_id: 903, schema_id: 50, version: 2

    defcodec do
      field :id, :u64
      field :price, :u32
      field :quantity, :u32, since: 2
    end
  end

  # V1 and V2 with mixed types (uuid, decimal, bool, timestamp)
  defmodule MixedV1 do
    use GridCodec.Struct, template_id: 902, schema_id: 50, version: 1

    defcodec do
      field :id, :uuid
      field :active, :bool
    end
  end

  defmodule MixedV2 do
    use GridCodec.Struct, template_id: 902, schema_id: 50, version: 2

    defcodec do
      field :id, :uuid
      field :active, :bool
      field :amount, :decimal, since: 2
      field :created_at, :timestamp_us, since: 2
    end
  end

  # Signed integer :since fields (different null sentinel pattern)
  defmodule SignedV1 do
    use GridCodec.Struct, template_id: 904, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
    end
  end

  defmodule SignedV2 do
    use GridCodec.Struct, template_id: 904, schema_id: 50, version: 2

    defcodec do
      field :id, :u64
      field :offset, :i32, since: 2
      field :delta, :i64, since: 2
    end
  end

  # No :since fields at all (tests that version-aware decode is a no-op)
  defmodule NoSinceV1 do
    use GridCodec.Struct, template_id: 905, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
      field :count, :u32
    end
  end

  # ============================================================================
  # Tests: Backward Compatibility (older binary → newer codec)
  # ============================================================================

  describe "v1 binary decoded by v2 codec" do
    test "new fixed fields decode as nil" do
      v1 = %EventV1{id: 42, price: 1000}
      binary = EventV1.encode(v1)

      assert {:ok, result} = EventV2.decode(binary)
      assert result.id == 42
      assert result.price == 1000
      assert result.quantity == nil
    end

    test "same-version binary decodes normally" do
      v2 = %EventV2{id: 42, price: 1000, quantity: 50}
      binary = EventV2.encode(v2)

      assert {:ok, result} = EventV2.decode(binary)
      assert result.id == 42
      assert result.price == 1000
      assert result.quantity == 50
    end
  end

  describe "v1 binary decoded by v3 codec (multi-version gap)" do
    test "all newer fields decode as nil" do
      v1 = %EventV1{id: 99, price: 500}
      binary = EventV1.encode(v1)

      assert {:ok, result} = EventV3.decode(binary)
      assert result.id == 99
      assert result.price == 500
      assert result.quantity == nil
      assert result.discount == nil
    end

    test "v2 binary decoded by v3 keeps v2 fields" do
      v2 = %EventV2{id: 99, price: 500, quantity: 25}
      binary = EventV2.encode(v2)

      assert {:ok, result} = EventV3.decode(binary)
      assert result.id == 99
      assert result.price == 500
      assert result.quantity == 25
      assert result.discount == nil
    end
  end

  describe "version-aware decode with variable-length fields" do
    test "v1 string fields survive padding" do
      v1 = %WithStringV1{id: 7, name: "hello world"}
      binary = WithStringV1.encode(v1)

      assert {:ok, result} = WithStringV2.decode(binary)
      assert result.id == 7
      assert result.score == nil
      assert result.name == "hello world"
    end

    test "v1 with nil string decoded by v2" do
      v1 = %WithStringV1{id: 7, name: nil}
      binary = WithStringV1.encode(v1)

      assert {:ok, result} = WithStringV2.decode(binary)
      assert result.id == 7
      assert result.score == nil
      assert result.name == nil
    end
  end

  describe "version-aware decode with mixed types" do
    test "uuid and bool fields preserved, decimal and timestamp default to nil" do
      uuid = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
      v1 = %MixedV1{id: uuid, active: true}
      binary = MixedV1.encode(v1)

      assert {:ok, result} = MixedV2.decode(binary)
      assert result.id == uuid
      assert result.active == true
      assert result.amount == nil
      assert result.created_at == nil
    end
  end

  describe "nil values in existing fields survive evolution" do
    test "v1 fields that are nil stay nil after v2 decode" do
      v1 = %EventV1{id: nil, price: nil}
      binary = EventV1.encode(v1)

      assert {:ok, result} = EventV2.decode(binary)
      assert result.id == nil
      assert result.price == nil
      assert result.quantity == nil
    end

    test "mix of nil and non-nil v1 fields" do
      v1 = %WithStringV1AllNil{id: 42, price: nil}
      binary = WithStringV1AllNil.encode(v1)

      assert {:ok, result} = WithStringV2AllNil.decode(binary)
      assert result.id == 42
      assert result.price == nil
      assert result.quantity == nil
    end
  end

  describe "signed integer :since fields" do
    test "signed i32 and i64 fields decode as nil from v1 binary" do
      v1 = %SignedV1{id: 100}
      binary = SignedV1.encode(v1)

      assert {:ok, result} = SignedV2.decode(binary)
      assert result.id == 100
      assert result.offset == nil
      assert result.delta == nil
    end
  end

  describe "header: false path is unaffected" do
    test "payload-only decode still works normally" do
      v2 = %EventV2{id: 42, price: 1000, quantity: 50}
      payload = EventV2.encode(v2, header: false)

      assert {:ok, result} = EventV2.decode(payload, header: false)
      assert result.id == 42
      assert result.price == 1000
      assert result.quantity == 50
    end
  end

  describe "no :since fields (version-aware decode is no-op)" do
    test "normal roundtrip works without :since" do
      v1 = %NoSinceV1{id: 42, count: 10}
      binary = NoSinceV1.encode(v1)

      assert {:ok, result} = NoSinceV1.decode(binary)
      assert result.id == 42
      assert result.count == 10
    end
  end

  describe "re-encode after evolution preserves data" do
    test "decode v1 with v2, then re-encode with v2 produces valid v2 binary" do
      v1 = %EventV1{id: 42, price: 1000}
      v1_binary = EventV1.encode(v1)

      {:ok, evolved} = EventV2.decode(v1_binary)
      assert evolved.quantity == nil

      v2_binary = EventV2.encode(evolved)
      {:ok, roundtripped} = EventV2.decode(v2_binary)
      assert roundtripped.id == 42
      assert roundtripped.price == 1000
      assert roundtripped.quantity == nil
    end

    test "decode v1 with v2, set new field, re-encode" do
      v1 = %EventV1{id: 42, price: 1000}
      v1_binary = EventV1.encode(v1)

      {:ok, evolved} = EventV2.decode(v1_binary)
      updated = %{evolved | quantity: 99}

      v2_binary = EventV2.encode(updated)
      {:ok, roundtripped} = EventV2.decode(v2_binary)
      assert roundtripped.id == 42
      assert roundtripped.price == 1000
      assert roundtripped.quantity == 99
    end
  end

  describe "compile-time :since ordering validation" do
    test "out-of-order :since raises CompileError" do
      assert_raise CompileError, ~r/must be declared after all earlier-version fields/, fn ->
        defmodule BadOrdering do
          use GridCodec.Struct, template_id: 999, schema_id: 50, version: 3

          defcodec do
            field :id, :u64
            field :new_field, :u32, since: 3
            field :old_field, :u32, since: 2
          end
        end
      end
    end
  end

  # ============================================================================
  # Tests: Schema Metadata
  # ============================================================================

  describe "field_versions metadata" do
    test "fields without :since are not in field_versions" do
      schema = EventV2.__schema__()
      refute Map.has_key?(schema.field_versions, :id)
      refute Map.has_key?(schema.field_versions, :price)
    end

    test "fields with :since are tracked" do
      schema = EventV2.__schema__()
      assert schema.field_versions == %{quantity: 2}
    end

    test "multiple :since fields tracked" do
      schema = EventV3.__schema__()
      assert schema.field_versions == %{quantity: 2, discount: 3}
    end

    test "v1 codec has empty field_versions" do
      schema = EventV1.__schema__()
      assert schema.field_versions == %{}
    end
  end

  # ============================================================================
  # Tests: Version Validation
  # ============================================================================

  describe "version validation" do
    test "newer version binary rejected" do
      v2 = %EventV2{id: 42, price: 1000, quantity: 50}
      binary = EventV2.encode(v2)

      assert {:error, {:version_too_new, 2, 1}} = EventV1.decode(binary)
    end
  end

  # ============================================================================
  # Tests: Block Length Introspection
  # ============================================================================

  describe "block_length reflects all fields" do
    test "v1 block_length is sum of v1 fixed fields" do
      # u64 (8) + u32 (4) = 12
      assert EventV1.block_length() == 12
    end

    test "v2 block_length includes :since fields" do
      # u64 (8) + u32 (4) + u32 (4) = 16
      assert EventV2.block_length() == 16
    end

    test "v3 block_length includes all versions" do
      # u64 (8) + u32 (4) + u32 (4) + u16 (2) = 18
      assert EventV3.block_length() == 18
    end
  end
end
