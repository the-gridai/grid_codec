defmodule GridCodec.Breaking.Rules.Source do
  @moduledoc """
  SOURCE category breaking change rules.

  These detect changes that break Elixir API compatibility -- callers need
  code changes even though the wire format may be unchanged.
  """

  alias GridCodec.Breaking.{Issue, Differ}
  alias GridCodec.Schema.Parser.{StructDef, EnumDef}

  @doc "Runs all SOURCE rules against a schema diff and returns a list of issues."
  @spec check(Differ.schema_diff(), String.t()) :: [Issue.t()]
  def check(schema_diff, path) do
    []
    |> check_schema_id(schema_diff, path)
    |> check_struct_renames(schema_diff, path)
    |> check_field_renames(schema_diff, path)
    |> check_field_default_changes(schema_diff, path)
    |> check_field_made_required(schema_diff, path)
    |> check_enum_renames(schema_diff, path)
    |> check_enum_value_renames(schema_diff, path)
    |> check_type_renames(schema_diff, path)
    |> Enum.reverse()
  end

  # ============================================================================
  # Schema-level
  # ============================================================================

  defp check_schema_id(issues, %{schema: %{old: old, new: new}}, path) do
    if old.id != nil and new.id != nil and old.id != new.id do
      [
        %Issue{
          rule: :SOURCE_SCHEMA_ID_CHANGED,
          category: :source,
          message: "Schema ID changed from #{old.id} to #{new.id}.",
          path: path,
          location: %{schema: new.name || old.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  # ============================================================================
  # Struct renames: removed + added with same template_id
  # ============================================================================

  defp check_struct_renames(issues, %{structs: %{removed: removed, added: added}}, path) do
    removed_by_tid =
      removed
      |> Enum.filter(fn {_name, s} -> s.template_id != nil end)
      |> Map.new(fn {_name, s} -> {s.template_id, s} end)

    Enum.reduce(added, issues, fn {_name, new_struct}, acc ->
      case Map.get(removed_by_tid, new_struct.template_id) do
        %StructDef{} = old_struct ->
          [
            %Issue{
              rule: :SOURCE_STRUCT_RENAMED,
              category: :source,
              message:
                "Struct appears renamed from \"#{old_struct.name}\" to " <>
                  "\"#{new_struct.name}\" (same template_id #{new_struct.template_id}).",
              path: path,
              location: %{struct: new_struct.name}
            }
            | acc
          ]

        nil ->
          acc
      end
    end)
  end

  # ============================================================================
  # Field renames: same position + same type, different name
  # ============================================================================

  defp check_field_renames(issues, %{structs: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_struct, new_struct}, acc ->
      field_diffs = Differ.diff_fields(old_struct.fields, new_struct.fields)

      Enum.reduce(field_diffs, acc, fn {_idx, old_f, new_f}, acc2 ->
        if old_f != nil and new_f != nil and
             old_f.name != new_f.name and old_f.type == new_f.type do
          [
            %Issue{
              rule: :SOURCE_FIELD_RENAMED,
              category: :source,
              message:
                "Field appears renamed from \"#{old_f.name}\" to " <>
                  "\"#{new_f.name}\" (same position, same type #{old_f.type}).",
              path: path,
              location: %{struct: new_struct.name, field: new_f.name}
            }
            | acc2
          ]
        else
          acc2
        end
      end)
    end)
  end

  # ============================================================================
  # Field default changes: default value changed or removed
  # ============================================================================

  defp check_field_default_changes(issues, %{structs: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_struct, new_struct}, acc ->
      field_diffs = Differ.diff_fields(old_struct.fields, new_struct.fields)

      Enum.reduce(field_diffs, acc, fn {_idx, old_f, new_f}, acc2 ->
        if old_f != nil and new_f != nil and
             old_f.name == new_f.name and
             old_f.default != new_f.default and
             not (old_f.default == nil and new_f.default == nil) do
          [
            %Issue{
              rule: :SOURCE_FIELD_DEFAULT_CHANGED,
              category: :source,
              message:
                ~s(Field "#{new_f.name}" default changed ) <>
                  "from #{inspect(old_f.default)} to #{inspect(new_f.default)}.",
              path: path,
              location: %{struct: new_struct.name, field: new_f.name}
            }
            | acc2
          ]
        else
          acc2
        end
      end)
    end)
  end

  # ============================================================================
  # Field made required: optional -> required
  # ============================================================================

  defp check_field_made_required(issues, %{structs: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_struct, new_struct}, acc ->
      field_diffs = Differ.diff_fields(old_struct.fields, new_struct.fields)

      Enum.reduce(field_diffs, acc, fn {_idx, old_f, new_f}, acc2 ->
        old_required = old_f != nil and old_f.presence == :required
        new_required = new_f != nil and new_f.presence == :required

        if old_f != nil and new_f != nil and
             old_f.name == new_f.name and
             not old_required and new_required do
          [
            %Issue{
              rule: :SOURCE_FIELD_MADE_REQUIRED,
              category: :source,
              message:
                ~s(Field "#{new_f.name}" changed from ) <>
                  "#{old_f.presence || :optional} to required.",
              path: path,
              location: %{struct: new_struct.name, field: new_f.name}
            }
            | acc2
          ]
        else
          acc2
        end
      end)
    end)
  end

  # ============================================================================
  # Enum renames: removed + added with same underlying type and same values
  # ============================================================================

  defp check_enum_renames(issues, %{enums: %{removed: removed, added: added}}, path) do
    removed_list = Map.values(removed)

    Enum.reduce(added, issues, fn {_name, new_enum}, acc ->
      match =
        Enum.find(removed_list, fn old_enum ->
          old_enum.underlying_type == new_enum.underlying_type and
            old_enum.values == new_enum.values
        end)

      case match do
        %EnumDef{} = old_enum ->
          [
            %Issue{
              rule: :SOURCE_ENUM_RENAMED,
              category: :source,
              message:
                "Enum appears renamed from \"#{old_enum.name}\" to " <>
                  "\"#{new_enum.name}\" (same underlying type and values).",
              path: path,
              location: %{enum: new_enum.name}
            }
            | acc
          ]

        nil ->
          acc
      end
    end)
  end

  # ============================================================================
  # Enum value renames: same integer value, different atom name
  # ============================================================================

  defp check_enum_value_renames(issues, %{enums: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_enum, new_enum}, acc ->
      old_by_int = Map.new(old_enum.values, fn {name, int} -> {int, name} end)
      new_by_int = Map.new(new_enum.values, fn {name, int} -> {int, name} end)

      common_ints =
        MapSet.intersection(MapSet.new(Map.keys(old_by_int)), MapSet.new(Map.keys(new_by_int)))

      Enum.reduce(common_ints, acc, fn int_val, acc2 ->
        old_name = Map.fetch!(old_by_int, int_val)
        new_name = Map.fetch!(new_by_int, int_val)

        if old_name != new_name do
          [
            %Issue{
              rule: :SOURCE_ENUM_VALUE_RENAMED,
              category: :source,
              message:
                "Enum value in \"#{new_enum.name}\" at integer #{int_val} " <>
                  "renamed from :#{old_name} to :#{new_name}.",
              path: path,
              location: %{enum: new_enum.name, value: new_name}
            }
            | acc2
          ]
        else
          acc2
        end
      end)
    end)
  end

  # ============================================================================
  # Type renames: removed + added composite types with same fields
  # ============================================================================

  defp check_type_renames(issues, %{types: %{removed: removed, added: added}}, path) do
    removed_list = Map.values(removed)

    Enum.reduce(added, issues, fn {_name, new_type}, acc ->
      match =
        Enum.find(removed_list, fn old_type ->
          old_type.fields == new_type.fields
        end)

      case match do
        nil ->
          acc

        old_type ->
          [
            %Issue{
              rule: :SOURCE_TYPE_RENAMED,
              category: :source,
              message:
                "Type appears renamed from \"#{old_type.name}\" to " <>
                  "\"#{new_type.name}\" (same fields).",
              path: path,
              location: %{type: new_type.name}
            }
            | acc
          ]
      end
    end)
  end
end
