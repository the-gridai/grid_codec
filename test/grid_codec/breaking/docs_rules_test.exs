defmodule GridCodec.Breaking.DocsRulesTest do
  use ExUnit.Case, async: true

  alias GridCodec.Breaking.Checker
  alias GridCodec.Breaking.Policy

  @path "test.grid"

  defp check(old, new, opts \\ %{}) do
    opts = Map.put_new(opts, :category, :source)
    {:ok, issues} = Checker.check_contents(old, new, @path, opts)
    issues
  end

  defp rules(issues), do: Enum.map(issues, & &1.rule)

  describe "field docs" do
    test "detects field doc added as non-blocking info by default" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, doc: "Stable identifier."
      }
      """

      issues = check(old, new)

      assert :DOC_FIELD_DOC_ADDED in rules(issues)
      assert Enum.any?(issues, &(&1.rule == :DOC_FIELD_DOC_ADDED and &1.category == :docs))
      assert Enum.any?(issues, &(&1.rule == :DOC_FIELD_DOC_ADDED and &1.severity == :info))
    end

    test "detects field doc changed" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, doc: "Old description."
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, doc: "New description."
      }
      """

      issues = check(old, new)

      assert :DOC_FIELD_DOC_CHANGED in rules(issues)
      assert Enum.any?(issues, &(&1.rule == :DOC_FIELD_DOC_CHANGED and &1.severity == :warning))
    end
  end

  describe "group docs" do
    test "detects group and group-field doc changes" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        group fills {
          doc: "Old group."
          qty: u32, doc: "Old field."
        }
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        group fills {
          doc: "New group."
          qty: u32, doc: "New field."
        }
      }
      """

      issues = check(old, new)

      assert :DOC_GROUP_DOC_CHANGED in rules(issues)
      assert :DOC_GROUP_FIELD_DOC_CHANGED in rules(issues)
    end
  end

  describe "enum docs" do
    test "detects enum value doc removed" do
      old = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1, doc: "Bid."
      }
      """

      new = """
      schema T { id: 1 }
      enum Side : u8 {
        buy = 1
      }
      """

      issues = check(old, new)

      assert :DOC_ENUM_VALUE_DOC_REMOVED in rules(issues)

      assert Enum.any?(
               issues,
               &(&1.rule == :DOC_ENUM_VALUE_DOC_REMOVED and &1.severity == :warning)
             )
    end
  end

  describe "policy controls" do
    test "include_docs false suppresses documentation issues" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, doc: "Stable identifier."
      }
      """

      assert check(old, new, %{include_docs: false}) == []
    end

    test "severity overrides are applied" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, doc: "Old description."
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, doc: "New description."
      }
      """

      issues = check(old, new, %{severity_overrides: %{DOC_FIELD_DOC_CHANGED: :error}})

      assert Enum.any?(issues, &(&1.rule == :DOC_FIELD_DOC_CHANGED and &1.severity == :error))
      assert Enum.any?(issues, &Policy.blocking?(&1, [:error]))
    end

    test "except filters documentation rules" do
      old = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string
      }
      """

      new = """
      schema T { id: 1 }
      struct Order (template_id: 1) {
        id: uuid_string, doc: "Stable identifier."
      }
      """

      assert check(old, new, %{except: [:DOC_FIELD_DOC_ADDED]}) == []
    end
  end
end
