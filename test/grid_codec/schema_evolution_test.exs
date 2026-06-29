defmodule GridCodec.SchemaEvolutionTest do
  use ExUnit.Case, async: true

  alias GridCodec.TestSupport.SchemaEvo, as: SE

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

  defmodule MissingVarBaseV1 do
    use GridCodec.Struct, template_id: 906, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
    end
  end

  defmodule MissingString16V2 do
    use GridCodec.Struct, template_id: 906, schema_id: 50, version: 2

    defcodec do
      field :id, :u64
      field :configuration_json, :string16, presence: :optional, since: 2
    end
  end

  defmodule MissingString32V2 do
    use GridCodec.Struct, template_id: 908, schema_id: 50, version: 2

    defcodec do
      field :id, :u64
      field :configuration_json, :string32, presence: :optional, since: 2
    end
  end

  defmodule MissingVar32BaseV1 do
    use GridCodec.Struct, template_id: 908, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
    end
  end

  defmodule ExistingAndAppendedVarV1 do
    use GridCodec.Struct, template_id: 907, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
      field :name, :string16
    end
  end

  defmodule ExistingAndAppendedVarV2 do
    use GridCodec.Struct, template_id: 907, schema_id: 50, version: 2

    defcodec do
      field :id, :u64
      field :name, :string16
      field :configuration_json, :string16, presence: :optional, since: 2
    end
  end

  defmodule OptionalFixedNoVersionReader do
    use GridCodec.Struct, template_id: 905, schema_id: 50, version: 1

    defcodec do
      field :id, :u64
      field :count, :u32
      field :balance_after, :i64, presence: :optional
    end
  end

  # Tier 1/2 evolution codecs live in test/support/schema_evolution_fixtures.ex
  # (GridCodec.TestSupport.SchemaEvo.*) so async tests and invariant properties
  # can reference them reliably.

  # ============================================================================
  # Tests: Backward Compatibility (older binary → newer codec)
  # ============================================================================

  describe "v1 binary decoded by v2 codec" do
    test "new fixed fields decode as nil" do
      v1 = %EventV1{id: 42, price: 1000}
      {:ok, binary} = EventV1.encode(v1)

      assert {:ok, result} = EventV2.decode(binary)
      assert result.id == 42
      assert result.price == 1000
      assert result.quantity == nil
    end

    test "same-version binary decodes normally" do
      v2 = %EventV2{id: 42, price: 1000, quantity: 50}
      {:ok, binary} = EventV2.encode(v2)

      assert {:ok, result} = EventV2.decode(binary)
      assert result.id == 42
      assert result.price == 1000
      assert result.quantity == 50
    end
  end

  describe "v1 binary decoded by v3 codec (multi-version gap)" do
    test "all newer fields decode as nil" do
      v1 = %EventV1{id: 99, price: 500}
      {:ok, binary} = EventV1.encode(v1)

      assert {:ok, result} = EventV3.decode(binary)
      assert result.id == 99
      assert result.price == 500
      assert result.quantity == nil
      assert result.discount == nil
    end

    test "v2 binary decoded by v3 keeps v2 fields" do
      v2 = %EventV2{id: 99, price: 500, quantity: 25}
      {:ok, binary} = EventV2.encode(v2)

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
      {:ok, binary} = WithStringV1.encode(v1)

      assert {:ok, result} = WithStringV2.decode(binary)
      assert result.id == 7
      assert result.score == nil
      assert result.name == "hello world"
    end

    test "v1 with nil string decoded by v2" do
      v1 = %WithStringV1{id: 7, name: nil}
      {:ok, binary} = WithStringV1.encode(v1)

      assert {:ok, result} = WithStringV2.decode(binary)
      assert result.id == 7
      assert result.score == nil
      assert result.name == nil
    end
  end

  describe "missing appended variable-length fields" do
    test "optional string16 appended in v2 decodes nil when historical tail has no prefix" do
      v1 = %MissingVarBaseV1{id: 7}
      {:ok, binary} = MissingVarBaseV1.encode(v1)

      assert {:ok, result} = MissingString16V2.decode(binary)
      assert result.id == 7
      assert result.configuration_json == nil
    end

    test "optional string32 appended in v2 decodes nil when historical tail has no prefix" do
      v1 = %MissingVar32BaseV1{id: 8}
      {:ok, binary} = MissingVar32BaseV1.encode(v1)

      assert {:ok, result} = MissingString32V2.decode(binary)
      assert result.id == 8
      assert result.configuration_json == nil
    end

    test "existing variable field is preserved and appended variable field decodes nil" do
      v1 = %ExistingAndAppendedVarV1{id: 9, name: "historical"}
      {:ok, binary} = ExistingAndAppendedVarV1.encode(v1)

      assert {:ok, result} = ExistingAndAppendedVarV2.decode(binary)
      assert result.id == 9
      assert result.name == "historical"
      assert result.configuration_json == nil
    end
  end

  describe "version-aware decode with mixed types" do
    test "uuid and bool fields preserved, decimal and timestamp default to nil" do
      uuid = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
      v1 = %MixedV1{id: uuid, active: true}
      {:ok, binary} = MixedV1.encode(v1)

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
      {:ok, binary} = EventV1.encode(v1)

      assert {:ok, result} = EventV2.decode(binary)
      assert result.id == nil
      assert result.price == nil
      assert result.quantity == nil
    end

    test "mix of nil and non-nil v1 fields" do
      v1 = %WithStringV1AllNil{id: 42, price: nil}
      {:ok, binary} = WithStringV1AllNil.encode(v1)

      assert {:ok, result} = WithStringV2AllNil.decode(binary)
      assert result.id == 42
      assert result.price == nil
      assert result.quantity == nil
    end
  end

  describe "signed integer :since fields" do
    test "signed i32 and i64 fields decode as nil from v1 binary" do
      v1 = %SignedV1{id: 100}
      {:ok, binary} = SignedV1.encode(v1)

      assert {:ok, result} = SignedV2.decode(binary)
      assert result.id == 100
      assert result.offset == nil
      assert result.delta == nil
    end
  end

  describe "short fixed block without version bump" do
    test "optional fixed-width append decodes nil from historical block_length" do
      v1 = %NoSinceV1{id: 42, count: 10}
      {:ok, binary} = NoSinceV1.encode(v1)

      assert {:ok, result} = OptionalFixedNoVersionReader.decode(binary)
      assert result.id == 42
      assert result.count == 10
      assert result.balance_after == nil
    end
  end

  describe "header: false path is unaffected" do
    test "payload-only decode still works normally" do
      v2 = %EventV2{id: 42, price: 1000, quantity: 50}
      {:ok, payload} = EventV2.encode(v2, header: false)

      assert {:ok, result} = EventV2.decode(payload, header: false)
      assert result.id == 42
      assert result.price == 1000
      assert result.quantity == 50
    end
  end

  describe "no :since fields (version-aware decode is no-op)" do
    test "normal roundtrip works without :since" do
      v1 = %NoSinceV1{id: 42, count: 10}
      {:ok, binary} = NoSinceV1.encode(v1)

      assert {:ok, result} = NoSinceV1.decode(binary)
      assert result.id == 42
      assert result.count == 10
    end
  end

  describe "re-encode after evolution preserves data" do
    test "decode v1 with v2, then re-encode with v2 produces valid v2 binary" do
      v1 = %EventV1{id: 42, price: 1000}
      {:ok, v1_binary} = EventV1.encode(v1)

      {:ok, evolved} = EventV2.decode(v1_binary)
      assert evolved.quantity == nil

      {:ok, v2_binary} = EventV2.encode(evolved)
      {:ok, roundtripped} = EventV2.decode(v2_binary)
      assert roundtripped.id == 42
      assert roundtripped.price == 1000
      assert roundtripped.quantity == nil
    end

    test "decode v1 with v2, set new field, re-encode" do
      v1 = %EventV1{id: 42, price: 1000}
      {:ok, v1_binary} = EventV1.encode(v1)

      {:ok, evolved} = EventV2.decode(v1_binary)
      updated = %{evolved | quantity: 99}

      {:ok, v2_binary} = EventV2.encode(updated)
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

    test "out-of-order :since in inline group raises CompileError" do
      assert_raise CompileError, ~r/in group :items must be declared after/, fn ->
        defmodule BadGroupOrdering do
          use GridCodec.Struct, template_id: 998, schema_id: 50, version: 3

          defcodec do
            field :id, :u64

            group :items do
              field :a, :u32, since: 3
              field :b, :u32, since: 2
            end
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
      {:ok, binary} = EventV2.encode(v2)

      assert {:error, {:version_too_new, 2, 1}} = EventV1.decode(binary)
    end
  end

  describe "required fixed fields appended with :since (decode contract)" do
    test "v1 binary → v2 without :default yields required_field_absent" do
      v1 = %SE.ReqSinceV1{id: 1, price: 2}
      {:ok, bin} = SE.ReqSinceV1.encode(v1)
      assert {:error, {:required_field_absent, :qty}} = SE.ReqSinceV2NoDefault.decode(bin)
    end

    test "v1 binary → v2 with :default substitutes default for padded sentinel" do
      v1 = %SE.ReqSinceAltV1{id: 9, price: 100}
      {:ok, bin} = SE.ReqSinceAltV1.encode(v1)

      assert {:ok, out} = SE.ReqSinceAltV2WithDefault.decode(bin)
      assert out.id == 9
      assert out.price == 100
      assert out.qty == 0
    end
  end

  describe "field_defaults with :since (required + decode default)" do
    test "v1 binary → v2 applies field_defaults default on new :since field" do
      v1 = %SE.DefaultsEvolV1{id: 42}
      {:ok, bin} = SE.DefaultsEvolV1.encode(v1)

      assert {:ok, out} = SE.DefaultsEvolV2.decode(bin)
      assert out.id == 42
      assert out.score == 0
    end
  end

  describe "struct evolution preserves groups (Tier 2)" do
    test "v1 with group → v2 adds :since fixed field; entries unchanged" do
      v1 = %SE.GroupPadWriterV1{id: 7, items: [%{qty: 11}, %{qty: 22}]}
      {:ok, bin} = SE.GroupPadWriterV1.encode(v1)

      assert {:ok, out} = SE.GroupPadReqReaderV2.decode(bin)
      assert out.id == 7
      assert out.seq == nil
      assert [%{qty: 11}, %{qty: 22}] = GridCodec.Group.to_list(out.items)
    end

    test "header-stripped v1 payload with group → v2 adds :since fixed field; entries unchanged" do
      v1 = %SE.GroupPadWriterV1{id: 7, items: [%{qty: 11}, %{qty: 22}]}
      {:ok, bin} = SE.GroupPadWriterV1.encode(v1)
      {:ok, header, payload} = GridCodec.Header.decode(bin)

      assert {:ok, out} =
               SE.GroupPadReqReaderV2.decode(payload,
                 header: false,
                 __gridcodec_header__: header
               )

      assert out.id == 7
      assert out.seq == nil
      assert [%{qty: 11}, %{qty: 22}] = GridCodec.Group.to_list(out.items)
    end

    test "v1 group entry with nil qty → v2 required inner field errors when materialized" do
      v1 = %SE.GroupPadWriterV1{id: 1, items: [%{qty: nil}]}
      {:ok, bin} = SE.GroupPadWriterV1.encode(v1)

      # Fixed groups decode lazily: top-level decode succeeds, then entry decode
      # runs required-field enforcement (throws if no :default; not wrapped in
      # the struct decoder try/catch).
      assert {:ok, out} = SE.GroupPadReqReaderV2.decode(bin)

      assert catch_throw(GridCodec.Group.get_entry(out.items, 0)) ==
               {:grid_codec_required_field_absent, :qty}
    end

    test "v1 group entry with nil qty → v2 required inner field with :default decodes" do
      v1 = %SE.GroupPadWriterAltV1{id: 2, items: [%{qty: nil}]}
      {:ok, bin} = SE.GroupPadWriterAltV1.encode(v1)

      assert {:ok, out} = SE.GroupPadReqDefaultV2.decode(bin)
      assert out.id == 2
      assert out.seq == nil
      assert [%{qty: 0}] = GridCodec.Group.to_list(out.items)
    end
  end

  describe "struct evolution preserves typed_frames batches (Tier 2)" do
    test "v1 batch payload → v2 adds :since field; commands intact" do
      mid = <<1::128>>
      cmd = %SE.EvolutionTinyCmd{cmd_id: 99}

      v1 = %SE.BatchParentV1{market_id: mid, commands: [cmd]}
      {:ok, bin} = SE.BatchParentV1.encode(v1)

      assert {:ok, out} = SE.BatchParentV2.decode(bin)
      assert out.market_id == mid
      assert out.trace_id == nil
      assert GridCodec.Batch.count(out.commands) == 1

      assert [{0, 0, decoded}] = GridCodec.Batch.to_list(out.commands)
      assert decoded.cmd_id == 99
    end
  end

  describe "appended :constant field with :since (Tier 2)" do
    test "v1 binary → v2 exposes declared constant regardless of padding" do
      v1 = %SE.ConstAppendV1{id: 123}
      {:ok, bin} = SE.ConstAppendV1.encode(v1)

      assert {:ok, out} = SE.ConstAppendV2.decode(bin)
      assert out.id == 123
      assert out.lane == 3
    end
  end

  describe "wire_format + :since evolution (Tier 2)" do
    test "optional decimal i64 wire decodes nil from historical padding" do
      v1 = %SE.DecWfV1{id: 5}
      {:ok, bin} = SE.DecWfV1.encode(v1)

      assert {:ok, out} = SE.DecWfV2.decode(bin)
      assert out.id == 5
      assert out.amount == nil
    end

    test "required decimal i64 wire with :default substitutes from padding" do
      v1 = %SE.DecWfReqDefV1{id: 8}
      {:ok, bin} = SE.DecWfReqDefV1.encode(v1)

      assert {:ok, out} = SE.DecWfReqDefV2.decode(bin)
      assert out.id == 8
      assert Decimal.equal?(out.amount, Decimal.new("0"))
    end
  end

  describe "custom Enum type appended with :since (Tier 2)" do
    test "v1 binary → v2 optional enum field decodes nil" do
      v1 = %SE.EnumEvolV1{id: 1001}
      {:ok, bin} = SE.EnumEvolV1.encode(v1)

      assert {:ok, out} = SE.EnumEvolV2.decode(bin)
      assert out.id == 1001
      assert out.side == nil
    end
  end

  describe "padded_union batch + struct :since (new)" do
    test "v1 padded batch → v2 adds fixed field; heterogeneous entries preserved" do
      entries = [
        %SE.BatchPaddedTiny{x: 11},
        %SE.BatchPaddedWide{a: 22, b: 33},
        %SE.BatchPaddedTiny{x: 44}
      ]

      v1 = %SE.BatchPaddedParentV1{sid: 0xAABBCCDD, cmds: entries}
      {:ok, bin} = SE.BatchPaddedParentV1.encode(v1)

      assert {:ok, out} = SE.BatchPaddedParentV2.decode(bin)
      assert out.sid == 0xAABBCCDD
      assert out.epoch == nil
      assert GridCodec.Batch.count(out.cmds) == 3

      assert [{0, 0, d0}, {1, 1, d1}, {2, 0, d2}] = GridCodec.Batch.to_list(out.cmds)
      assert d0 == %SE.BatchPaddedTiny{x: 11}
      assert d1 == %SE.BatchPaddedWide{a: 22, b: 33}
      assert d2 == %SE.BatchPaddedTiny{x: 44}
    end
  end

  describe "scalar group + parent :since (new)" do
    test "v1 u32 list → v2 adds fixed field; scores list unchanged" do
      v1 = %SE.ScalarScoresV1{owner: 999, scores: [1, 2, 3, 4]}
      {:ok, bin} = SE.ScalarScoresV1.encode(v1)

      assert {:ok, out} = SE.ScalarScoresV2.decode(bin)
      assert out.owner == 999
      assert out.version_tag == nil
      assert out.scores == [1, 2, 3, 4]
    end
  end

  describe "payload-only decode vs version-aware padding (new)" do
    test "header:false cannot cross-decode when V2 grows the fixed block — padding needs Header.block_length" do
      v1 = %SE.ReqSinceAltV1{id: 5, price: 7}
      {:ok, payload} = SE.ReqSinceAltV1.encode(v1, header: false)

      # Version padding is applied only after Header.decode/1 supplies the writer's
      # block_length; payload-only decode expects the full V2 fixed payload.
      assert {:error, :invalid_binary} =
               SE.ReqSinceAltV2WithDefault.decode(payload, header: false)
    end

    test "same-version payload-only roundtrip still works" do
      v1 = %SE.ReqSinceAltV1{id: 11, price: 22}
      {:ok, payload} = SE.ReqSinceAltV1.encode(v1, header: false)
      assert {:ok, out} = SE.ReqSinceAltV1.decode(payload, header: false)
      assert out.id == 11
      assert out.price == 22
    end
  end

  describe "header: false versioned decode with var-data before appended fixed field" do
    test "full binary decode recovers the var-data tail" do
      v1 = %SE.VarBeforeFixedV1{id: 7, some_string: "historical"}
      {:ok, binary} = SE.VarBeforeFixedV1.encode(v1)

      assert {:ok, out} = SE.VarBeforeFixedV2.decode(binary)
      assert out.id == 7
      assert out.some_string == "historical"
      assert out.extra == nil
    end

    test "header-stripped decode recovers the var-data tail" do
      v1 = %SE.VarBeforeFixedV1{id: 7, some_string: "historical"}
      {:ok, binary} = SE.VarBeforeFixedV1.encode(v1)
      {:ok, header, payload} = GridCodec.Header.decode(binary)

      assert {:ok, out} =
               SE.VarBeforeFixedV2.decode(payload,
                 header: false,
                 __gridcodec_header__: header
               )

      assert out.id == 7
      assert out.some_string == "historical"
      assert out.extra == nil
    end

    test "header-stripped decode without a header still assumes current width" do
      v2 = %SE.VarBeforeFixedV2{id: 3, some_string: "now", extra: 99}
      {:ok, payload} = SE.VarBeforeFixedV2.encode(v2, header: false)

      assert {:ok, out} = SE.VarBeforeFixedV2.decode(payload, header: false)
      assert out.id == 3
      assert out.some_string == "now"
      assert out.extra == 99
    end
  end

  describe "appended :since group on historical payload raises catchable error" do
    # When v2 appends a typed group, a historical v1 payload has an empty tail
    # where the group header is expected. Group.parse_with_rest!/3 previously
    # lacked a short-binary guard and raised an uncatchable FunctionClauseError;
    # it now raises a catchable ArgumentError so consumers can detect the missing
    # group and synthesize/pad it (grid_codec does not yet version-gate groups).
    test "Mod.decode/1 (header path) raises catchable ArgumentError" do
      v1 = %SE.AppendedGroupV1{id: 999}
      {:ok, binary} = SE.AppendedGroupV1.encode(v1)

      assert_raise ArgumentError, ~r/Group binary too short/, fn ->
        SE.AppendedGroupV2.decode(binary)
      end
    end

    test "registry-style header-stripped decode raises catchable ArgumentError" do
      v1 = %SE.AppendedGroupV1{id: 999}
      {:ok, binary} = SE.AppendedGroupV1.encode(v1)
      {:ok, header, payload} = GridCodec.Header.decode(binary)

      assert_raise ArgumentError, ~r/Group binary too short/, fn ->
        SE.AppendedGroupV2.decode(payload, header: false, __gridcodec_header__: header)
      end
    end

    test "same-version payload with present group still decodes" do
      entries = [
        %SE.AppendedGroupEntry{a: 1, b: 2},
        %SE.AppendedGroupEntry{a: 3, b: 4}
      ]

      v2 = %SE.AppendedGroupV2{id: 7, queue: entries}
      {:ok, binary} = SE.AppendedGroupV2.encode(v2)

      assert {:ok, out} = SE.AppendedGroupV2.decode(binary)
      assert out.id == 7
      assert [%{a: 1, b: 2}, %{a: 3, b: 4}] = GridCodec.Group.to_list(out.queue)
    end
  end

  describe "version-aware fixed group entries (new)" do
    test "typed group: optional+default append decodes historical entries to the default" do
      v1 = %SE.OrderBookV1{
        market_id: 42,
        orders: [
          %SE.OrderEntryV1{price: 100, qty: 5},
          %SE.OrderEntryV1{price: 200, qty: 7}
        ]
      }

      {:ok, binary} = SE.OrderBookV1.encode(v1)

      assert {:ok, out} = SE.OrderBookV2.decode(binary)
      assert out.market_id == 42

      # `autotransfer` declares `default: false`, so historical padding decodes to
      # the concrete default rather than nil.
      # Eager to_list
      assert [first, second] = GridCodec.Group.to_list(out.orders)
      assert %{price: 100, qty: 5, autotransfer: false} = first
      assert %{price: 200, qty: 7, autotransfer: false} = second

      # Lazy get_entry / stream agree with to_list
      assert {:ok, %{price: 100, qty: 5, autotransfer: false}} =
               GridCodec.Group.get_entry(out.orders, 0)

      assert {:ok, %{price: 200, qty: 7, autotransfer: false}} =
               GridCodec.Group.get_entry(out.orders, 1)

      assert [%{autotransfer: false}, %{autotransfer: false}] =
               out.orders |> GridCodec.Group.stream() |> Enum.to_list()
    end

    test "typed group: required+default append materializes the default" do
      v1 = %SE.WarehouseV1{
        wh_id: 9,
        lots: [
          %SE.LotEntryV1{sku: 1, count: 10},
          %SE.LotEntryV1{sku: 2, count: 20},
          %SE.LotEntryV1{sku: 3, count: 30}
        ]
      }

      {:ok, binary} = SE.WarehouseV1.encode(v1)

      assert {:ok, out} = SE.WarehouseV2.decode(binary)

      assert [%{sku: 1, count: 10, grade: 7}, %{sku: 2, count: 20, grade: 7}, %{grade: 7}] =
               GridCodec.Group.to_list(out.lots)

      assert {:ok, %{sku: 2, count: 20, grade: 7}} = GridCodec.Group.get_entry(out.lots, 1)

      # The materialized default round-trips through re-encode under V2.
      lots = GridCodec.Group.to_list(out.lots)
      assert {:ok, reencoded} = SE.WarehouseV2.encode(%{out | lots: lots})
      assert {:ok, out2} = SE.WarehouseV2.decode(reencoded)
      assert Enum.map(GridCodec.Group.to_list(out2.lots), & &1.grade) == [7, 7, 7]
    end

    test "inline group: optional append decodes historical entries with nil" do
      v1 = %SE.InlineGroupV1{
        id: 1,
        items: [%{a: 10, b: 1}, %{a: 20, b: 2}, %{a: 30, b: 3}]
      }

      {:ok, binary} = SE.InlineGroupV1.encode(v1)

      assert {:ok, out} = SE.InlineGroupV2.decode(binary)

      assert [%{a: 10, b: 1, c: nil}, %{a: 20, b: 2, c: nil}, %{a: 30, b: 3, c: nil}] =
               GridCodec.Group.to_list(out.items)

      assert {:ok, %{a: 30, b: 3, c: nil}} = GridCodec.Group.get_entry(out.items, 2)
    end

    test "inline group: required+default append materializes the default" do
      v1 = %SE.InlineGroupReqV1{id: 1, items: [%{a: 11}, %{a: 22}]}
      {:ok, binary} = SE.InlineGroupReqV1.encode(v1)

      assert {:ok, out} = SE.InlineGroupReqV2.decode(binary)

      assert [%{a: 11, flag: 3}, %{a: 22, flag: 3}] = GridCodec.Group.to_list(out.items)
      assert {:ok, %{a: 22, flag: 3}} = GridCodec.Group.get_entry(out.items, 1)
    end

    test "mixed counts: striding by wire block_length keeps entry boundaries correct" do
      entries = for i <- 1..16, do: %SE.OrderEntryV1{price: i * 10, qty: i}
      v1 = %SE.OrderBookV1{market_id: 1, orders: entries}
      {:ok, binary} = SE.OrderBookV1.encode(v1)

      assert {:ok, out} = SE.OrderBookV2.decode(binary)
      decoded = GridCodec.Group.to_list(out.orders)
      assert length(decoded) == 16

      Enum.each(Enum.with_index(decoded, 1), fn {entry, i} ->
        assert entry.price == i * 10
        assert entry.qty == i
        assert entry.autotransfer == false
      end)
    end

    test "generated group lookups project over padded historical entries" do
      v1 = %SE.LookupBookV1{
        market_id: 42,
        orders: [
          %SE.OrderEntryV1{price: 100, qty: 5},
          %SE.OrderEntryV1{price: 200, qty: 7}
        ]
      }

      {:ok, binary} = SE.LookupBookV1.encode(v1)
      assert {:ok, out} = SE.LookupBookV2.decode(binary)

      # Map lookup keyed on a pre-existing field over padded entries.
      assert {:ok, by_price} = SE.LookupBookV2.orders_by_price(out)
      assert %{100 => entry100, 200 => entry200} = by_price
      assert entry100.qty == 5
      assert entry200.qty == 7

      # The appended `autotransfer` field resolves to its `false` default on the
      # padded entries, so a where-filter on that default value matches both.
      assert {:ok, filtered} = SE.LookupBookV2.no_autotransfer(out.orders)
      assert Enum.map(filtered, & &1.price) == [100, 200]
      assert Enum.all?(filtered, &(&1.autotransfer == false))
    end

    test "to_lists_parallel/2 pads historical entries like to_list/1" do
      v1 = %SE.OrderBookV1{
        market_id: 1,
        orders: for(i <- 1..8, do: %SE.OrderEntryV1{price: i * 10, qty: i})
      }

      {:ok, binary} = SE.OrderBookV1.encode(v1)
      assert {:ok, out} = SE.OrderBookV2.decode(binary)

      assert [entries] = GridCodec.Group.to_lists_parallel([out.orders])
      assert entries == GridCodec.Group.to_list(out.orders)
      assert Enum.all?(entries, &(&1.autotransfer == false))
      assert Enum.map(entries, & &1.price) == Enum.map(1..8, &(&1 * 10))
    end

    test "same-version path is byte-identical (no padding allocated)" do
      v2 = %SE.OrderBookV2{
        market_id: 7,
        orders: [%SE.OrderEntryV2{price: 1, qty: 2, autotransfer: true}]
      }

      {:ok, binary} = SE.OrderBookV2.encode(v2)
      {:ok, binary_again} = SE.OrderBookV2.encode(v2)
      assert binary == binary_again

      assert {:ok, out} = SE.OrderBookV2.decode(binary)
      assert [%{price: 1, qty: 2, autotransfer: true}] = GridCodec.Group.to_list(out.orders)
    end

    test ".grid round-trip preserves group field since/default" do
      schema = SE.OrderBookV2.__schema__()
      grid = GridCodec.Schema.Formatter.format_struct_file(schema, %{}, [])

      assert grid =~ "since: 2"

      {:ok, parsed} = GridCodec.Schema.Parser.parse(grid)
      struct_def = parsed.structs |> Map.values() |> List.first()
      group = List.first(struct_def.groups)
      autotransfer = Enum.find(group.fields, &(&1.name == :autotransfer))

      # `since` and `default` round-trip on the group field. `presence: :optional`
      # is the implicit default and is intentionally omitted by the formatter, so
      # the parsed presence is nil (still treated as optional by the loader).
      assert autotransfer.since == 2
      assert autotransfer.default == false
      refute autotransfer.presence == :required
    end
  end

  describe "lazy group iteration + required inner field (new)" do
    test "Group.stream/1 propagates required-field throw from entry decode" do
      v1 = %SE.GroupPadWriterV1{id: 1, items: [%{qty: nil}]}
      {:ok, bin} = SE.GroupPadWriterV1.encode(v1)
      assert {:ok, out} = SE.GroupPadReqReaderV2.decode(bin)

      assert catch_throw(out.items |> GridCodec.Group.stream() |> Enum.to_list()) ==
               {:grid_codec_required_field_absent, :qty}
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
