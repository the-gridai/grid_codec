defmodule GridCodec.Breaking.WireRulesTest do
  use ExUnit.Case, async: true

  alias GridCodec.Breaking.Checker

  @path "test.grid"

  defp check(old, new, opts \\ %{}) do
    opts = Map.put_new(opts, :category, :wire)
    {:ok, issues} = Checker.check_contents(old, new, @path, opts)
    issues
  end

  defp rules(issues), do: Enum.map(issues, & &1.rule)

  describe "WIRE_STRUCT_REMOVED" do
    test "detects struct removal" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      struct Trade (template_id: 2) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      issues = check(old, new)
      assert :WIRE_STRUCT_REMOVED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "Trade"))
    end

    test "no issue when struct added" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      struct Trade (template_id: 2) { id: uuid_string }
      """

      assert check(old, new) == []
    end
  end

  describe "WIRE_FIELD_REMOVED" do
    test "detects field removal" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
        quantity: u32
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      issues = check(old, new)
      assert :WIRE_FIELD_REMOVED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "quantity"))
    end
  end

  describe "WIRE_FIELD_TYPE_CHANGED" do
    test "detects type change with different wire size" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u32
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      issues = check(old, new)
      assert :WIRE_FIELD_TYPE_CHANGED in rules(issues)
    end

    test "no issue for same-size type change" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        value: u64
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        value: i64
      }
      """

      issues = check(old, new)
      refute :WIRE_FIELD_TYPE_CHANGED in rules(issues)
    end
  end

  describe "WIRE_TEMPLATE_ID_CHANGED" do
    test "detects template_id change" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 99) { id: uuid_string }
      """

      issues = check(old, new)
      assert :WIRE_TEMPLATE_ID_CHANGED in rules(issues)
    end
  end

  describe "WIRE_GROUP_REMOVED" do
    test "detects group removal" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        group fills {
          price: u64
          qty: u32
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      issues = check(old, new)
      assert :WIRE_GROUP_REMOVED in rules(issues)
    end
  end

  describe "WIRE_GROUP_FIELD_TYPE_CHANGED" do
    test "detects group field type change" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        group fills {
          price: u32
          qty: u32
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        group fills {
          price: u64
          qty: u32
        }
      }
      """

      issues = check(old, new)
      assert :WIRE_GROUP_FIELD_TYPE_CHANGED in rules(issues)
    end
  end

  describe "WIRE_BATCH_REMOVED" do
    test "detects batch removal" do
      old = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        id: uuid_string
        batch commands {
          any_of: [A, B]
          strategy: padded_union
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        id: uuid_string
      }
      """

      issues = check(old, new)
      assert :WIRE_BATCH_REMOVED in rules(issues)
    end
  end

  describe "WIRE_BATCH_TYPE_REMOVED" do
    test "detects type removed from any_of" do
      old = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        batch commands {
          any_of: [A, B, C]
          strategy: padded_union
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        batch commands {
          any_of: [A, C]
          strategy: padded_union
        }
      }
      """

      issues = check(old, new)
      assert :WIRE_BATCH_TYPE_REMOVED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "B"))
    end
  end

  describe "WIRE_BATCH_TYPE_REORDERED" do
    test "detects reordering of any_of types" do
      old = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        batch commands {
          any_of: [A, B, C]
          strategy: padded_union
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        batch commands {
          any_of: [C, A, B]
          strategy: padded_union
        }
      }
      """

      issues = check(old, new)
      assert :WIRE_BATCH_TYPE_REORDERED in rules(issues)
    end
  end

  describe "WIRE_BATCH_STRATEGY_CHANGED" do
    test "detects strategy change" do
      old = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        batch commands {
          any_of: [A, B]
          strategy: padded_union
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Container (template_id: 1) {
        batch commands {
          any_of: [A, B]
          strategy: typed_frames
        }
      }
      """

      issues = check(old, new)
      assert :WIRE_BATCH_STRATEGY_CHANGED in rules(issues)
    end
  end

  describe "WIRE_ENUM_VALUE_REMOVED" do
    test "detects enum value removal" do
      old = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      """

      new = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
      }
      """

      issues = check(old, new)
      assert :WIRE_ENUM_VALUE_REMOVED in rules(issues)
    end
  end

  describe "WIRE_ENUM_VALUE_CHANGED" do
    test "detects enum value integer reassignment" do
      old = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      """

      new = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 3
      }
      """

      issues = check(old, new)
      assert :WIRE_ENUM_VALUE_CHANGED in rules(issues)
    end
  end

  describe "WIRE_ENUM_UNDERLYING_CHANGED" do
    test "detects encoding type change" do
      old = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      """

      new = """
      schema T { id: 1 }
      enum Side : u16 {
        buy = 1
        sell = 2
      }
      """

      issues = check(old, new)
      assert :WIRE_ENUM_UNDERLYING_CHANGED in rules(issues)
    end
  end

  describe "no breaking changes" do
    test "identical schemas produce no issues" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      assert check(schema, schema) == []
    end

    test "adding new struct is not breaking" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      struct NewThing (template_id: 2) { id: uuid_string }
      """

      assert check(old, new) == []
    end

    test "adding new enum value is not breaking" do
      old = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      """

      new = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 2
        short_sell = 3
      }
      """

      assert check(old, new) == []
    end
  end
end
