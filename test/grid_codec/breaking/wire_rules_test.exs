defmodule GridCodec.Breaking.WireRulesTest do
  use ExUnit.Case, async: true

  alias GridCodec.Breaking.Checker
  alias GridCodec.Breaking.Policy

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

  describe "WIRE_FIELD_ADDED_REQUIRED" do
    test "flags appended :required fixed-block field (default presence)" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
        quantity: u32
      }
      """

      issues = check(old, new)
      assert :WIRE_FIELD_ADDED_REQUIRED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "quantity"))
    end

    test "flags appended explicit presence: required field" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        balance_after: decimal(scale: 8), wire_format: i64, presence: required
      }
      """

      issues = check(old, new)
      assert :WIRE_FIELD_ADDED_REQUIRED in rules(issues)
      assert Enum.any?(issues, &(&1.message =~ "balance_after"))
    end

    test "does not flag appended :optional field (presence: optional)" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        balance_after: decimal(scale: 8), wire_format: i64, presence: optional
      }
      """

      refute :WIRE_FIELD_ADDED_REQUIRED in rules(check(old, new))
    end

    test "does not flag appended optional field via trailing ? shorthand" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        notes?: u32
      }
      """

      refute :WIRE_FIELD_ADDED_REQUIRED in rules(check(old, new))
    end

    test "does not flag appended variable-length field as required fixed-block field" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        note: string16
      }
      """

      refute :WIRE_FIELD_ADDED_REQUIRED in rules(check(old, new))
    end

    test "default: suppresses the warning (decoder uses default for historical payloads)" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        counter: u32, default: 100
      }
      """

      refute :WIRE_FIELD_ADDED_REQUIRED in rules(check(old, new))
    end

    test "default: on explicit presence: required also suppresses the warning" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        counter: u32, presence: required, default: 100
      }
      """

      refute :WIRE_FIELD_ADDED_REQUIRED in rules(check(old, new))
    end

    test "since: does not suppress the warning" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1, version: 2) {
        id: uuid_string
        counter: u32, since: 2
      }
      """

      issues = check(old, new)
      assert :WIRE_FIELD_ADDED_REQUIRED in rules(issues)
    end

    test "does not flag appended :constant field (safe: decoder returns declared value regardless of wire bytes)" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        exchange: u32, presence: constant, value: 1
      }
      """

      refute :WIRE_FIELD_ADDED_REQUIRED in rules(check(old, new))
    end

    test "does not flag when no fields were added" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      refute :WIRE_FIELD_ADDED_REQUIRED in rules(check(schema, schema))
    end
  end

  describe "WIRE_FIXED_APPEND_BEFORE_TAIL" do
    test "flags fixed-block append when a group tail already exists" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: u64
        group allocations {
          qty: u32
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: u64
        auto_transfer: bool, since: 2, presence: optional
        group allocations {
          qty: u32
        }
      }
      """

      issues = check(old, new)

      assert issue = Enum.find(issues, &(&1.rule == :WIRE_FIXED_APPEND_BEFORE_TAIL))
      assert issue.severity == :warning
      assert issue.message =~ "auto_transfer"
      assert issue.message =~ "block_length"
    end

    test "flags fixed-block append when variable-length fields already exist" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: u64
        note: string16
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: u64
        note: string16
        auto_transfer: bool, since: 2, presence: optional
      }
      """

      issues = check(old, new)
      assert :WIRE_FIXED_APPEND_BEFORE_TAIL in rules(issues)
    end

    test "does not flag fixed-block append on fixed-only structs" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: u64
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: u64
        auto_transfer: bool, since: 2, presence: optional
      }
      """

      refute :WIRE_FIXED_APPEND_BEFORE_TAIL in rules(check(old, new))
    end
  end

  describe "WIRE_VAR_FIELD_ADDED" do
    test "flags appended optional variable-length field as non-blocking info by default" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1, version: 2) {
        id: uuid_string
        price: u64
        note: string16, presence: optional, since: 2
      }
      """

      issues = check(old, new)
      assert issue = Enum.find(issues, &(&1.rule == :WIRE_VAR_FIELD_ADDED))
      assert issue.severity == :info
      refute Policy.blocking?(issue, [:error])
      assert issue.message =~ "note"
      assert issue.message =~ "GridCodec 0.41.3+"
    end

    test "severity_overrides can escalate appended variable-length fields to error" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        note: string16
      }
      """

      issues = check(old, new, %{severity_overrides: %{WIRE_VAR_FIELD_ADDED: :error}})

      assert issue = Enum.find(issues, &(&1.rule == :WIRE_VAR_FIELD_ADDED))
      assert issue.severity == :error
      assert Policy.blocking?(issue, [:error])
    end

    test "flags appended default-presence variable-length field" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        note: string16
      }
      """

      assert :WIRE_VAR_FIELD_ADDED in rules(check(old, new))
    end

    test "does not flag unchanged variable-length field" do
      schema = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
        note: string16, presence: optional
      }
      """

      refute :WIRE_VAR_FIELD_ADDED in rules(check(schema, schema))
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

  describe "WIRE_SYNTAX_VERSION_CHANGED" do
    test "detects syntax version change" do
      old = """
      @syntax 1
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      new = """
      @syntax 1
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      assert check(old, new) == []
    end

    test "no issue when both lack explicit syntax" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) { id: uuid_string }
      """

      assert check(old, new) == []
    end
  end

  describe "WIRE_PREFIXED_ID_TAG_CHANGED" do
    test "detects tag change" do
      old = """
      schema T { id: 1 }
      prefixed_id UserId { prefix: "user" tag: 1 }
      """

      new = """
      schema T { id: 1 }
      prefixed_id UserId { prefix: "user" tag: 2 }
      """

      issues = check(old, new)
      assert :WIRE_PREFIXED_ID_TAG_CHANGED in rules(issues)
    end

    test "no issue when tag unchanged" do
      old = """
      schema T { id: 1 }
      prefixed_id UserId { prefix: "user" tag: 1 }
      """

      new = """
      schema T { id: 1 }
      prefixed_id UserId { prefix: "user" tag: 1 }
      """

      assert check(old, new) == []
    end
  end

  describe "SOURCE_PREFIXED_ID_PREFIX_CHANGED" do
    test "detects prefix change" do
      old = """
      schema T { id: 1 }
      prefixed_id UserId { prefix: "user" tag: 1 }
      """

      new = """
      schema T { id: 1 }
      prefixed_id UserId { prefix: "account" tag: 1 }
      """

      issues = check(old, new, %{category: :source})
      assert :SOURCE_PREFIXED_ID_PREFIX_CHANGED in rules(issues)
    end
  end

  describe "WIRE_CHAR_ARRAY_LENGTH_CHANGED" do
    test "detects length change" do
      old = """
      schema T { id: 1 }
      char_array Symbol { length: 8 }
      """

      new = """
      schema T { id: 1 }
      char_array Symbol { length: 16 }
      """

      issues = check(old, new)
      assert :WIRE_CHAR_ARRAY_LENGTH_CHANGED in rules(issues)
    end

    test "no issue when length unchanged" do
      old = """
      schema T { id: 1 }
      char_array Symbol { length: 8 }
      """

      new = """
      schema T { id: 1 }
      char_array Symbol { length: 8 }
      """

      assert check(old, new) == []
    end
  end

  describe "WIRE_BITSET rules" do
    test "detects underlying type change" do
      old = """
      schema T { id: 1 }
      bitset Perms : u8 { read = 0 write = 1 }
      """

      new = """
      schema T { id: 1 }
      bitset Perms : u16 { read = 0 write = 1 }
      """

      issues = check(old, new)
      assert :WIRE_BITSET_UNDERLYING_CHANGED in rules(issues)
    end

    test "detects flag removal" do
      old = """
      schema T { id: 1 }
      bitset Perms : u8 { read = 0 write = 1 execute = 2 }
      """

      new = """
      schema T { id: 1 }
      bitset Perms : u8 { read = 0 write = 1 }
      """

      issues = check(old, new)
      assert :WIRE_BITSET_FLAG_REMOVED in rules(issues)
    end

    test "detects flag value change" do
      old = """
      schema T { id: 1 }
      bitset Perms : u8 { read = 0 write = 1 }
      """

      new = """
      schema T { id: 1 }
      bitset Perms : u8 { read = 0 write = 3 }
      """

      issues = check(old, new)
      assert :WIRE_BITSET_FLAG_VALUE_CHANGED in rules(issues)
    end

    test "no issue when unchanged" do
      old = """
      schema T { id: 1 }
      bitset Perms : u8 { read = 0 write = 1 }
      """

      new = """
      schema T { id: 1 }
      bitset Perms : u8 { read = 0 write = 1 }
      """

      assert check(old, new) == []
    end
  end
end
