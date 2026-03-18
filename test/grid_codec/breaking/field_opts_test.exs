defmodule GridCodec.Breaking.FieldOptsTest do
  use ExUnit.Case, async: true

  alias GridCodec.Breaking.Checker
  alias GridCodec.Schema.Parser

  @path "test.grid"

  # ============================================================================
  # Parser tests: parameterized types and field options
  # ============================================================================

  describe "parser: parameterized types" do
    test "parses type with params" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        price: decimal(scale: 8)
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.type == :decimal
      assert field.type_params == [scale: 8]
    end

    test "parses type with multiple params" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        data: char_array(length: 32, on_overflow: truncate)
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.type == :char_array
      assert field.type_params == [length: 32, on_overflow: :truncate]
    end

    test "plain type has empty params" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: u64
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.type_params == []
    end
  end

  describe "parser: field options" do
    test "parses wire_format" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        price: decimal(scale: 8), wire_format: i64
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.wire_format == :i64
      assert field.type_params == [scale: 8]
    end

    test "parses since" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        notes: string16, since: 2
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [_id, notes] = parsed.structs[:Order].fields
      assert notes.since == 2
    end

    test "parses default" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        quantity: u32, default: 0
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.default == 0
    end

    test "parses presence: constant with value" do
      schema = ~s"""
      schema T { id: 1 }
      struct Order (template_id: 1) {
        exchange: string8, presence: constant, value: "NYSE"
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.presence == :constant
      assert field.value == "NYSE"
    end

    test "parses presence: required" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, presence: required
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.presence == :required
    end

    test "parses multiple options" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        price: decimal(scale: 8), wire_format: i64, since: 2
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.type == :decimal
      assert field.type_params == [scale: 8]
      assert field.wire_format == :i64
      assert field.since == 2
    end

    test "fields without options have nil opts" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [field] = parsed.structs[:Order].fields
      assert field.wire_format == nil
      assert field.since == nil
      assert field.default == nil
      assert field.presence == nil
      assert field.value == nil
    end

    test "field options work alongside groups and batches" do
      schema = """
      schema T { id: 1 }
      struct Cmd1 (template_id: 10) { id: u64 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64, wire_format: i64

        group fills {
          price: u64
          qty: u32
        }

        batch commands {
          any_of: [Cmd1]
          strategy: padded_union
        }
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      order = parsed.structs[:Order]
      [_id, price] = order.fields
      assert price.wire_format == :i64
      assert length(order.groups) == 1
      assert length(order.batches) == 1
    end

    test "group fields can have options" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string

        group fills {
          price: u64, wire_format: i64
          qty: u32
        }
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      [group] = parsed.structs[:Order].groups
      [price, _qty] = group.fields
      assert price.wire_format == :i64
    end
  end

  describe "parser: struct version in header" do
    test "parses version in struct header" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1, version: 3) {
        id: uuid_string
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      assert parsed.structs[:Order].version == 3
    end
  end

  # ============================================================================
  # Formatter round-trip tests
  # ============================================================================

  describe "formatter round-trip" do
    test "field options survive parse -> format -> parse" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        price: decimal(scale: 8), wire_format: i64, since: 2
        quantity: u32, default: 0
      }
      """

      assert {:ok, parsed1} = Parser.parse(schema)

      formatted =
        GridCodec.Schema.Formatter.format(
          "T",
          1,
          1,
          [
            {OrderMock,
             %{
               template_id: 1,
               version: 1,
               type: "Test.Order",
               fields: [
                 {:price, {:decimal, scale: 8}, wire_format: :i64, since: 2},
                 {:quantity, :u32, default: 0}
               ],
               groups: [],
               batches: [],
               group_fields: %{}
             }}
          ]
        )

      assert {:ok, parsed2} = Parser.parse(formatted)
      [p1, q1] = parsed1.structs[:Order].fields
      [p2, q2] = parsed2.structs[:Order].fields
      assert p1.type == p2.type
      assert p1.type_params == p2.type_params
      assert p1.wire_format == p2.wire_format
      assert p1.since == p2.since
      assert q1.default == q2.default
    end
  end

  # ============================================================================
  # Breaking change rule tests for new rules
  # ============================================================================

  defp check(old, new, opts \\ %{}) do
    {:ok, issues} = Checker.check_contents(old, new, @path, opts)
    issues
  end

  defp wire_check(old, new), do: check(old, new, %{category: :wire})

  defp rules(issues), do: Enum.map(issues, & &1.rule)

  describe "WIRE_FIELD_WIRE_FORMAT_CHANGED" do
    test "detects wire_format change" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 8), wire_format: i64 }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 8), wire_format: i32 }
      """

      assert :WIRE_FIELD_WIRE_FORMAT_CHANGED in rules(wire_check(old, new))
    end

    test "detects wire_format added" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 8) }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 8), wire_format: i64 }
      """

      assert :WIRE_FIELD_WIRE_FORMAT_CHANGED in rules(wire_check(old, new))
    end

    test "no issue when wire_format unchanged" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 8), wire_format: i64 }
      """

      assert wire_check(old, old) == []
    end
  end

  describe "WIRE_FIELD_SINCE_CHANGED" do
    test "detects since version change" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        notes: string16, since: 2
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        notes: string16, since: 3
      }
      """

      assert :WIRE_FIELD_SINCE_CHANGED in rules(wire_check(old, new))
    end

    test "detects since added" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        notes: string16
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        notes: string16, since: 2
      }
      """

      assert :WIRE_FIELD_SINCE_CHANGED in rules(wire_check(old, new))
    end
  end

  describe "WIRE_FIELD_PRESENCE_CHANGED" do
    test "detects presence change" do
      old = ~s"""
      schema T { id: 1 }
      struct Order (template_id: 1) {
        exchange: string8, presence: constant, value: "NYSE"
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        exchange: string8
      }
      """

      issues = wire_check(old, new)
      assert :WIRE_FIELD_PRESENCE_CHANGED in rules(issues)

      assert Enum.any?(
               issues,
               &(&1.message == ~s(Field "exchange" presence changed from constant to optional.))
             )
    end
  end

  describe "WIRE_FIELD_CONSTANT_VALUE_CHANGED" do
    test "detects constant value change" do
      old = ~s"""
      schema T { id: 1 }
      struct Order (template_id: 1) {
        exchange: string8, presence: constant, value: "NYSE"
      }
      """

      new = ~s"""
      schema T { id: 1 }
      struct Order (template_id: 1) {
        exchange: string8, presence: constant, value: "CBOE"
      }
      """

      assert :WIRE_FIELD_CONSTANT_VALUE_CHANGED in rules(wire_check(old, new))
    end
  end

  describe "WIRE_FIELD_TYPE_PARAMS_CHANGED" do
    test "detects scale change" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 8) }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 4) }
      """

      assert :WIRE_FIELD_TYPE_PARAMS_CHANGED in rules(wire_check(old, new))
    end

    test "no issue when params unchanged" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { price: decimal(scale: 8) }
      """

      assert wire_check(old, old) == []
    end
  end

  describe "SOURCE_FIELD_DEFAULT_CHANGED" do
    test "detects default value change" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { quantity: u32, default: 0 }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { quantity: u32, default: 100 }
      """

      issues = check(old, new)
      assert :SOURCE_FIELD_DEFAULT_CHANGED in rules(issues)
    end

    test "detects default removed" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { quantity: u32, default: 0 }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { quantity: u32 }
      """

      issues = check(old, new)
      assert :SOURCE_FIELD_DEFAULT_CHANGED in rules(issues)
    end

    test "no issue when default unchanged" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { quantity: u32, default: 0 }
      """

      assert check(old, old) == []
    end
  end

  describe "SOURCE_FIELD_MADE_REQUIRED" do
    test "detects optional to required" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string, presence: required }
      """

      issues = check(old, new)
      assert :SOURCE_FIELD_MADE_REQUIRED in rules(issues)
      assert Enum.any?(issues, &(&1.message == ~s(Field "id" changed from optional to required.)))
    end

    test "no issue when required stays required" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string, presence: required }
      """

      assert check(old, old) == []
    end

    test "no issue for required to optional (relaxation)" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string, presence: required }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      issues = check(old, new)
      refute :SOURCE_FIELD_MADE_REQUIRED in rules(issues)
    end
  end
end
