defmodule GridCodec.Schema.FormatterTest do
  use ExUnit.Case, async: true

  alias GridCodec.Schema.Formatter
  alias GridCodec.Schema.Parser

  defmodule TestEnum do
    @moduledoc false
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:active)
      value(:inactive)
    end
  end

  defmodule DocumentedEnum do
    @moduledoc false
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:active, 0, doc: "Enabled state.")
      value(:inactive, 1, doc: "Disabled state.")
    end
  end

  defmodule TestPrefixedIdWithSchema do
    @moduledoc false
    use GridCodec.Types.PrefixedId, prefix: "test", tag: 0x10, schema: "my_events"
  end

  defmodule TestPrefixedIdNoSchema do
    @moduledoc false
    use GridCodec.Types.PrefixedId, prefix: "plain", tag: 0x11
  end

  defmodule TestCharArrayWithSchema do
    @moduledoc false
    use GridCodec.Types.CharArray, length: 8, schema: "my_events"
  end

  defmodule TestBitsetWithSchema do
    @moduledoc false
    use GridCodec.Types.Bitset, size: :u8, schema: "my_events"

    flag(:read, 0)
    flag(:write, 1)
  end

  describe "format/4" do
    test "produces valid .grid output for simple structs" do
      codecs = [
        {TestMod,
         %{
           fields: [{:id, :uuid, []}, {:price, :u64, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Order"
         }}
      ]

      output = Formatter.format("TestSchema", 100, 1, codecs)

      assert output =~ "schema TestSchema {"
      assert output =~ "id: 100"
      assert output =~ "struct Order (template_id: 1)"
      assert output =~ "id: uuid"
      assert output =~ "price: u64"
    end

    test "detects and formats enum types" do
      codecs = [
        {TestMod,
         %{
           fields: [{:status, TestEnum, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Widget"
         }}
      ]

      output = Formatter.format("TestSchema", 100, 1, codecs)

      assert output =~ "enum TestEnum : u8 {"
      assert output =~ "active = 0"
      assert output =~ "inactive = 1"
      assert output =~ "status: TestEnum"
    end

    test "formats group fields" do
      codecs = [
        {TestMod,
         %{
           fields: [{:id, :uuid, []}],
           groups: [{:fills, nil, []}],
           batches: [],
           group_fields: %{fills: [{:price, :u64}, {:qty, :u32}]},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Order"
         }}
      ]

      output = Formatter.format("TestSchema", 100, 1, codecs)

      assert output =~ "group fills {"
      assert output =~ "price: u64"
      assert output =~ "qty: u32"
    end

    test "formats field, group, and enum docs" do
      codecs = [
        {TestMod,
         %{
           fields: [{:status, DocumentedEnum, [doc: "Current status."]}],
           groups: [{:fills, nil, [doc: "Partial fills.", framing: :length_prefixed]}],
           batches: [],
           group_fields: %{fills: [{:qty, :u32, [doc: "Fill quantity."]}]},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Order"
         }}
      ]

      output = Formatter.format("TestSchema", 100, 1, codecs)

      assert output =~ ~s(status: DocumentedEnum, doc: "Current status.")
      assert output =~ ~s(active = 0, doc: "Enabled state.")
      assert output =~ ~s(inactive = 1, doc: "Disabled state.")
      assert output =~ ~s(group fills {)
      assert output =~ ~s(doc: "Partial fills.")
      assert output =~ ~s(qty: u32, doc: "Fill quantity.")
    end

    test "formats batch declarations" do
      codecs = [
        {TestMod,
         %{
           fields: [{:id, :uuid, []}],
           groups: [],
           batches: [{:commands, [PlaceOrder, CancelOrder], :padded_union}],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Container"
         }}
      ]

      output = Formatter.format("TestSchema", 100, 1, codecs)

      assert output =~ "batch commands {"
      assert output =~ "any_of: [PlaceOrder, CancelOrder]"
      assert output =~ "strategy: padded_union"
    end

    test "output parses back through the parser" do
      codecs = [
        {TestMod,
         %{
           fields: [{:id, :uuid, []}, {:price, :u64, []}, {:name, :string16, []}],
           groups: [{:fills, nil, []}],
           batches: [],
           group_fields: %{fills: [{:price, :u64}, {:qty, :u32}]},
           version: 1,
           template_id: 42,
           schema_id: 200,
           type: "Test.OrderBook"
         }}
      ]

      output = Formatter.format("TestSchema", 200, 1, codecs)
      assert {:ok, schema} = Parser.parse(output)

      assert schema.id == 200
      assert schema.name == :TestSchema

      order_book = schema.structs[:OrderBook]
      assert order_book.template_id == 42
      assert length(order_book.fields) == 3
      assert length(order_book.groups) == 1
    end

    test "multiple structs sorted by template_id" do
      codecs = [
        {ModB,
         %{
           fields: [{:id, :uuid, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 5,
           schema_id: 1,
           type: "X.Beta"
         }},
        {ModA,
         %{
           fields: [{:id, :uuid, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 1,
           type: "X.Alpha"
         }}
      ]

      output = Formatter.format("Test", 1, 1, codecs)
      alpha_pos = :binary.match(output, "Alpha") |> elem(0)
      beta_pos = :binary.match(output, "Beta") |> elem(0)
      assert alpha_pos < beta_pos
    end

    test "output is deterministic regardless of codec input order" do
      codec_a =
        {ModA,
         %{
           fields: [{:id, :uuid, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 1,
           type: "X.Alpha"
         }}

      codec_b =
        {ModB,
         %{
           fields: [{:id, :uuid, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 5,
           schema_id: 1,
           type: "X.Beta"
         }}

      assert Formatter.format("Test", 1, 1, [codec_a, codec_b]) ==
               Formatter.format("Test", 1, 1, [codec_b, codec_a])
    end
  end

  describe "custom type schema affinity" do
    test "detect_custom_types includes schema from meta" do
      codecs = [
        {TestMod,
         %{
           fields: [{:entity_id, TestPrefixedIdWithSchema, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Entity"
         }}
      ]

      types = Formatter.detect_custom_types(codecs)
      info = Map.fetch!(types, TestPrefixedIdWithSchema)

      assert info.kind == :prefixed_id
      assert info.params.schema == "my_events"
    end

    test "detect_custom_types returns nil schema when not set" do
      codecs = [
        {TestMod,
         %{
           fields: [{:entity_id, TestPrefixedIdNoSchema, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Entity"
         }}
      ]

      types = Formatter.detect_custom_types(codecs)
      info = Map.fetch!(types, TestPrefixedIdNoSchema)

      assert info.kind == :prefixed_id
      assert info.params.schema == nil
    end

    test "char_array schema affinity propagates through detect_custom_types" do
      codecs = [
        {TestMod,
         %{
           fields: [{:symbol, TestCharArrayWithSchema, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Entity"
         }}
      ]

      types = Formatter.detect_custom_types(codecs)
      info = Map.fetch!(types, TestCharArrayWithSchema)

      assert info.kind == :char_array
      assert info.params.schema == "my_events"
    end

    test "bitset schema affinity propagates through detect_custom_types" do
      codecs = [
        {TestMod,
         %{
           fields: [{:perms, TestBitsetWithSchema, []}],
           groups: [],
           batches: [],
           group_fields: %{},
           version: 1,
           template_id: 1,
           schema_id: 100,
           type: "Test.Entity"
         }}
      ]

      types = Formatter.detect_custom_types(codecs)
      info = Map.fetch!(types, TestBitsetWithSchema)

      assert info.kind == :bitset
      assert info.params.schema == "my_events"
    end
  end

  describe "inline group type formatting" do
    test "format_struct_file uses short names for inline group enum and custom types" do
      schema = %{
        fields: [{:id, :uuid, []}],
        groups: [{:rejections, nil, []}],
        batches: [],
        group_fields: %{
          rejections: [
            {:order_id, TestPrefixedIdWithSchema},
            {:status, TestEnum},
            {:symbol, TestCharArrayWithSchema}
          ]
        },
        version: 1,
        template_id: 1,
        schema_id: 100,
        type: "Test.OrderBatchProcessed"
      }

      codecs = [{TestMod, schema}]
      enums = Formatter.detect_enums(codecs)
      custom_types = Formatter.detect_custom_types(codecs)
      type_aliases = Formatter.build_type_aliases(codecs, enums, custom_types)
      output = Formatter.format_struct_file(schema, type_aliases)

      assert output =~ "order_id: TestPrefixedIdWithSchema"
      assert output =~ "status: TestEnum"
      assert output =~ "symbol: TestCharArrayWithSchema"
      refute output =~ "Elixir."
    end

    test "enum and custom type detection includes inline group fields" do
      schema = %{
        fields: [{:id, :uuid, []}],
        groups: [{:rejections, nil, []}],
        batches: [],
        group_fields: %{
          rejections: [
            {:order_id, TestPrefixedIdWithSchema},
            {:status, TestEnum},
            {:symbol, TestCharArrayWithSchema}
          ]
        },
        version: 1,
        template_id: 1,
        schema_id: 100,
        type: "Test.OrderBatchProcessed"
      }

      codecs = [{TestMod, schema}]
      enums = Formatter.detect_enums(codecs)
      custom_types = Formatter.detect_custom_types(codecs)

      assert Map.has_key?(enums, TestEnum)
      assert Map.has_key?(custom_types, TestPrefixedIdWithSchema)
      assert Map.has_key?(custom_types, TestCharArrayWithSchema)

      assert Formatter.referenced_enums(schema, enums) == [TestEnum]

      assert Enum.sort(Formatter.referenced_custom_types(schema, custom_types)) ==
               Enum.sort([TestCharArrayWithSchema, TestPrefixedIdWithSchema])
    end
  end
end
