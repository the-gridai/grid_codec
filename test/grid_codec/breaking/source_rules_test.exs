defmodule GridCodec.Breaking.SourceRulesTest do
  use ExUnit.Case, async: true

  alias GridCodec.Breaking.Checker

  @path "test.grid"

  defp check(old, new, opts \\ %{}) do
    opts = Map.put_new(opts, :category, :source)
    {:ok, issues} = Checker.check_contents(old, new, @path, opts)
    issues
  end

  defp rules(issues), do: Enum.map(issues, & &1.rule)

  describe "SOURCE_SCHEMA_ID_CHANGED" do
    test "detects schema ID change" do
      old = """
      schema Trading { id: 100 }
      """

      new = """
      schema Trading { id: 200 }
      """

      issues = check(old, new)
      assert :SOURCE_SCHEMA_ID_CHANGED in rules(issues)
    end

    test "no issue when schema ID unchanged" do
      old = """
      schema Trading { id: 100 }
      """

      assert check(old, old) == []
    end
  end

  describe "SOURCE_STRUCT_RENAMED" do
    test "detects struct rename (same template_id)" do
      old = """
      schema T { id: 1 }
      struct OrderCreated (template_id: 1) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct OrderPlaced (template_id: 1) { id: uuid_string }
      """

      issues = check(old, new)
      assert :SOURCE_STRUCT_RENAMED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "OrderCreated"))
      assert Enum.any?(issues, &(&1.message =~ "OrderPlaced"))
    end
  end

  describe "SOURCE_FIELD_RENAMED" do
    test "detects field rename (same position, same type)" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        symbol: u64
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        sym: u64
      }
      """

      issues = check(old, new)
      assert :SOURCE_FIELD_RENAMED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "symbol"))
      assert Enum.any?(issues, &(&1.message =~ "sym"))
    end

    test "no rename if type also changed" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        value: u32
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        amount: u64
      }
      """

      issues = check(old, new)
      refute :SOURCE_FIELD_RENAMED in rules(issues)
    end
  end

  describe "SOURCE_ENUM_RENAMED" do
    test "detects enum rename (same values and underlying type)" do
      old = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      """

      new = """
      schema T { id: 1 }
      enum Direction : u8 {
        buy = 1
        sell = 2
      }
      """

      issues = check(old, new)
      assert :SOURCE_ENUM_RENAMED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "Side"))
      assert Enum.any?(issues, &(&1.message =~ "Direction"))
    end
  end

  describe "SOURCE_ENUM_VALUE_RENAMED" do
    test "detects enum value atom rename (same integer)" do
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
        long = 1
        short = 2
      }
      """

      issues = check(old, new)
      assert :SOURCE_ENUM_VALUE_RENAMED in rules(issues)
    end
  end

  describe "SOURCE_TYPE_RENAMED" do
    test "detects composite type rename (same fields)" do
      old = """
      schema T { id: 1 }
      type Price {
        mantissa: i64
        exponent: i8
      }
      """

      new = """
      schema T { id: 1 }
      type Amount {
        mantissa: i64
        exponent: i8
      }
      """

      issues = check(old, new)
      assert :SOURCE_TYPE_RENAMED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "Price"))
      assert Enum.any?(issues, &(&1.message =~ "Amount"))
    end
  end

  describe "category filtering" do
    test "wire-only mode excludes SOURCE rules" do
      old = """
      schema T { id: 1 }
      struct OrderCreated (template_id: 1) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct OrderPlaced (template_id: 1) { id: uuid_string }
      """

      issues = check(old, new, %{category: :wire})
      refute :SOURCE_STRUCT_RENAMED in rules(issues)
    end

    test "source mode includes both WIRE and SOURCE rules" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 99) {
        id: uuid_string
        amount: u64
      }
      """

      issues = check(old, new, %{category: :source})
      assert :WIRE_TEMPLATE_ID_CHANGED in rules(issues)
      assert :SOURCE_FIELD_RENAMED in rules(issues)
    end
  end

  describe "except filtering" do
    test "excluded rules are filtered out" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        symbol: u64
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        sym: u64
      }
      """

      issues = check(old, new, %{category: :source, except: [:SOURCE_FIELD_RENAMED]})
      refute :SOURCE_FIELD_RENAMED in rules(issues)
    end
  end
end
