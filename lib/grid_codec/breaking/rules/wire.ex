defmodule GridCodec.Breaking.Rules.Wire do
  @moduledoc """
  WIRE category breaking change rules.

  These detect changes that break binary wire compatibility: an old reader
  would fail to decode messages produced by the new schema, or the `.grid`
  schema itself would no longer be safely consumable by older tooling.

  Use this category to answer: "Can the old wire readers keep consuming data
  written by the new schema?"

  ## Versioning Model

  For an existing message type:

  - keep the same `{schema_id, template_id}`
  - bump `version`
  - add new fields with `since: <version>`

  Changes like field removal, type changes, field reordering, enum integer
  reassignment, and batch tag reordering are wire-breaking and should usually be
  modeled as a new message type instead of an in-place edit.

  ## Rules

  ### Schema and struct identity

  | Rule | Meaning |
  |------|---------|
  | `WIRE_SYNTAX_VERSION_CHANGED` | `.grid` `@syntax` changed |
  | `WIRE_STRUCT_REMOVED` | Struct definition removed |
  | `WIRE_TEMPLATE_ID_CHANGED` | Existing struct changed `template_id` |

  ### Fields

  | Rule | Meaning |
  |------|---------|
  | `WIRE_FIELD_REMOVED` | Field removed from struct |
  | `WIRE_FIELD_ADDED_REQUIRED` | `:required` fixed-block field appended without `default:` (historical events decode to `{:error, {:required_field_absent, field}}`); add `default:` to make the append safe |
  | `WIRE_VAR_FIELD_ADDED` | Variable-length field added (historical events have no var-data bytes for the new field) |
  | `WIRE_FIELD_REORDERED` | Fixed field order changed incompatibly |
  | `WIRE_FIELD_WIRE_FORMAT_CHANGED` | `wire_format` changed |
  | `WIRE_FIELD_SINCE_CHANGED` | `since` metadata changed |
  | `WIRE_FIELD_PRESENCE_CHANGED` | Presence mode changed |
  | `WIRE_FIELD_CONSTANT_VALUE_CHANGED` | Constant field value changed |
  | `WIRE_FIELD_TYPE_PARAMS_CHANGED` | Parameterized type options changed |
  | `WIRE_FIELD_TYPE_CHANGED` | Field type changed incompatibly |

  ### Groups and batches

  | Rule | Meaning |
  |------|---------|
  | `WIRE_GROUP_REMOVED` | Group removed |
  | `WIRE_GROUP_FIELD_REMOVED` | Field removed from group entry |
  | `WIRE_GROUP_FIELD_TYPE_CHANGED` | Group field type changed |
  | `WIRE_GROUP_FIELD_REORDERED` | Group field layout changed incompatibly |
  | `WIRE_BATCH_REMOVED` | Batch removed |
  | `WIRE_BATCH_STRATEGY_CHANGED` | Batch encoding strategy changed |
  | `WIRE_BATCH_TYPE_REMOVED` | Type removed from batch `any_of` |
  | `WIRE_BATCH_TYPE_REORDERED` | Batch `any_of` order changed, reassigning tags |

  ### Enums and custom types

  | Rule | Meaning |
  |------|---------|
  | `WIRE_ENUM_UNDERLYING_CHANGED` | Enum backing integer type changed |
  | `WIRE_ENUM_VALUE_REMOVED` | Enum value removed |
  | `WIRE_ENUM_VALUE_CHANGED` | Enum integer changed |
  | `WIRE_PREFIXED_ID_TAG_CHANGED` | `PrefixedId` tag byte changed |
  | `WIRE_CHAR_ARRAY_LENGTH_CHANGED` | `CharArray` length changed |
  | `WIRE_BITSET_UNDERLYING_CHANGED` | Bitset backing type changed |
  | `WIRE_BITSET_FLAG_REMOVED` | Bitset flag removed |
  | `WIRE_BITSET_FLAG_VALUE_CHANGED` | Bitset bit position changed |

  See `docs/schema-evolution.md` for the practical guidance that goes with
  these rules, including what to do when you want to remove a field or change a
  field type.
  """

  alias GridCodec.Breaking.Differ
  alias GridCodec.Breaking.Issue
  alias GridCodec.Breaking.WireSizes
  alias GridCodec.Schema.Parser.EnumDef
  alias GridCodec.Schema.Parser.StructDef

  @doc "Runs all WIRE rules against a schema diff and returns a list of issues."
  @spec check(Differ.schema_diff(), String.t()) :: [Issue.t()]
  def check(schema_diff, path) do
    []
    |> check_syntax_version(schema_diff, path)
    |> check_structs(schema_diff, path)
    |> check_enums(schema_diff, path)
    |> check_custom_types(schema_diff, path)
    |> Enum.reverse()
  end

  # ============================================================================
  # Syntax version
  # ============================================================================

  defp check_syntax_version(issues, %{schema: %{old: old, new: new}}, path) do
    old_syntax = old.syntax
    new_syntax = new.syntax

    if old_syntax != nil and new_syntax != nil and old_syntax != new_syntax do
      [
        %Issue{
          rule: :WIRE_SYNTAX_VERSION_CHANGED,
          category: :wire,
          message:
            "Schema @syntax version changed from #{old_syntax} to #{new_syntax}. " <>
              "Consumers on older parsers may fail to read the file.",
          path: path,
          location: %{}
        }
        | issues
      ]
    else
      issues
    end
  end

  # ============================================================================
  # Struct-level rules
  # ============================================================================

  defp check_structs(issues, %{structs: struct_diff, schema: %{new: new_schema}}, path) do
    issues
    |> check_struct_removed(struct_diff, path)
    |> check_struct_changes(struct_diff, new_schema, path)
  end

  defp check_struct_removed(issues, %{removed: removed}, path) do
    Enum.reduce(removed, issues, fn {name, _struct_def}, acc ->
      [
        %Issue{
          rule: :WIRE_STRUCT_REMOVED,
          category: :wire,
          message: "Struct \"#{name}\" was removed.",
          path: path,
          location: %{struct: name}
        }
        | acc
      ]
    end)
  end

  defp check_struct_changes(issues, %{changed: changed}, new_schema, path) do
    Enum.reduce(changed, issues, fn {_name, old_struct, new_struct}, acc ->
      acc
      |> check_template_id(old_struct, new_struct, path)
      |> check_fields(old_struct, new_struct, new_schema, path)
      |> check_groups(old_struct, new_struct, new_schema, path)
      |> check_batches(old_struct, new_struct, path)
    end)
  end

  defp check_template_id(issues, %StructDef{} = old, %StructDef{} = new, path) do
    if old.template_id != nil and new.template_id != nil and old.template_id != new.template_id do
      [
        %Issue{
          rule: :WIRE_TEMPLATE_ID_CHANGED,
          category: :wire,
          message: "template_id changed from #{old.template_id} to #{new.template_id}.",
          path: path,
          location: %{struct: new.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  # ============================================================================
  # Field-level rules
  # ============================================================================

  defp check_fields(issues, %StructDef{} = old, %StructDef{} = new, new_schema, path) do
    field_diffs = Differ.diff_fields(old.fields, new.fields)

    field_diffs
    |> Enum.reduce(issues, fn {idx, old_f, new_f}, acc ->
      cond do
        old_f != nil and new_f == nil ->
          [
            %Issue{
              rule: :WIRE_FIELD_REMOVED,
              category: :wire,
              message: "Field \"#{old_f.name}\" was removed.",
              path: path,
              location: %{struct: new.name, field: old_f.name}
            }
            | acc
          ]

        old_f == nil and new_f != nil ->
          check_field_added(acc, new, new_f, new_schema, path)

        old_f != nil and new_f != nil and old_f.type != new_f.type ->
          check_field_type_change(acc, old, new, old_f, new_f, idx, new_schema, path)

        old_f != nil and new_f != nil and old_f.name != new_f.name ->
          old_size = WireSizes.resolve(old_f.type, new_schema.types)
          new_size = WireSizes.resolve(new_f.type, new_schema.types)

          if old_size == new_size and old_f.type == new_f.type do
            acc
          else
            [
              %Issue{
                rule: :WIRE_FIELD_REORDERED,
                category: :wire,
                message:
                  "Field at position #{idx} changed from \"#{old_f.name}\" to \"#{new_f.name}\".",
                path: path,
                location: %{struct: new.name, field: new_f.name}
              }
              | acc
            ]
          end

        old_f != nil and new_f != nil ->
          check_field_opts(acc, new, old_f, new_f, path)

        true ->
          acc
      end
    end)
    |> check_var_fields_added(old, new, new_schema, path)
  end

  # Flags variable-length fields that were not present in the baseline.
  #
  # Historical payloads have no var-data bytes for the new field. Unlike the
  # fixed block, the decoder cannot synthesize a missing length prefix from
  # `@__null_fixed_block__`, so appending even an optional `:string16` can raise
  # while decoding old events.
  defp check_var_fields_added(issues, %StructDef{} = old, %StructDef{} = new, new_schema, path) do
    old_var_names =
      old.fields
      |> Enum.filter(&variable_length_field?(&1, new_schema))
      |> MapSet.new(& &1.name)

    new.fields
    |> Enum.filter(&variable_length_field?(&1, new_schema))
    |> Enum.reject(&MapSet.member?(old_var_names, &1.name))
    |> Enum.reduce(issues, fn field, acc ->
      [
        %Issue{
          rule: :WIRE_VAR_FIELD_ADDED,
          category: :wire,
          message:
            ~s(Variable-length field "#{field.name}" was added. Historical events ) <>
              "written before this change have no var-data bytes for the field, so " <>
              "the decoder may fail while reading its length prefix. Introduce a new " <>
              "message type, keep the field out of the existing schema, or add a " <>
              "deserializer-level compatibility shim.",
          path: path,
          location: %{struct: new.name, field: field.name}
        }
        | acc
      ]
    end)
  end

  # Flags appended fixed-block fields with effective presence `:required` and
  # no `:default`.
  #
  # Historical payloads (written before the append) are shorter than the new
  # block length. `decode_versioned_payload/2` pads them from
  # `@__null_fixed_block__`, which is synthesized from each type's null
  # sentinel (zeros for integers, NaN for floats, i64_min for decimals backed
  # by i64, etc.). For a `:required` field, that sentinel would decode as
  # `nil`, violating the typespec — so the runtime now rejects the decode
  # with `{:error, {:required_field_absent, field}}` unless the field
  # declares a `:default` for the decoder to substitute.
  #
  # Safe appends:
  #   * `presence: :required, default: <value>` — historical events decode
  #     with the default (round-trippable via encode).
  #   * `presence: :optional` on fixed-block fields — historical events decode
  #     as `nil` (the typespec already admits `nil`).
  #   * Introduce a new message type.
  defp check_field_added(issues, struct, new_f, new_schema, path) do
    cond do
      variable_length_field?(new_f, new_schema) ->
        issues

      effective_presence(new_f) != :required ->
        issues

      new_f.default != nil ->
        issues

      true ->
        [
          %Issue{
            rule: :WIRE_FIELD_ADDED_REQUIRED,
            category: :wire,
            message:
              ~s(Field "#{new_f.name}" was appended as a required fixed-block field ) <>
                "without a :default. Historical events written before this change decode " <>
                "to {:error, {:required_field_absent, :#{new_f.name}}} because the type's " <>
                "null sentinel would otherwise surface as nil and violate the typespec. " <>
                "Declare a :default to supply a decode-time fallback, or use presence: " <>
                ":optional, or introduce a new message type.",
            path: path,
            location: %{struct: struct.name, field: new_f.name}
          }
          | issues
        ]
    end
  end

  # Effective presence combines the explicit `presence:` option with the
  # trailing `?` shorthand. Default (neither set) is `:required`.
  defp effective_presence(%{presence: presence})
       when presence in [:required, :optional, :constant],
       do: presence

  defp effective_presence(%{optional: true}), do: :optional
  defp effective_presence(_field), do: :required

  # A field is variable-length if its resolved wire size is `:variable`.
  # Unknown types (e.g. enums, unresolved custom types) are conservatively
  # treated as fixed-block, since they participate in the same null-padding
  # path on short historical payloads.
  defp variable_length_field?(%{type: type}, schema) do
    WireSizes.resolve(type, schema.types) == :variable
  end

  defp check_field_opts(issues, new_struct, old_f, new_f, path) do
    issues
    |> check_wire_format_changed(new_struct, old_f, new_f, path)
    |> check_since_changed(new_struct, old_f, new_f, path)
    |> check_presence_changed(new_struct, old_f, new_f, path)
    |> check_constant_value_changed(new_struct, old_f, new_f, path)
    |> check_type_params_changed(new_struct, old_f, new_f, path)
  end

  defp check_wire_format_changed(issues, struct, old_f, new_f, path) do
    if old_f.wire_format != new_f.wire_format and
         not (old_f.wire_format == nil and new_f.wire_format == nil) do
      [
        %Issue{
          rule: :WIRE_FIELD_WIRE_FORMAT_CHANGED,
          category: :wire,
          message:
            ~s(Field "#{new_f.name}" wire_format changed ) <>
              "from #{inspect(old_f.wire_format)} to #{inspect(new_f.wire_format)}.",
          path: path,
          location: %{struct: struct.name, field: new_f.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_since_changed(issues, struct, old_f, new_f, path) do
    if old_f.since != new_f.since and
         not (old_f.since == nil and new_f.since == nil) do
      [
        %Issue{
          rule: :WIRE_FIELD_SINCE_CHANGED,
          category: :wire,
          message:
            ~s(Field "#{new_f.name}" since version changed ) <>
              "from #{inspect(old_f.since)} to #{inspect(new_f.since)}.",
          path: path,
          location: %{struct: struct.name, field: new_f.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_presence_changed(issues, struct, old_f, new_f, path) do
    old_p = old_f.presence
    new_p = new_f.presence

    if old_p != new_p and not (old_p == nil and new_p == nil) do
      [
        %Issue{
          rule: :WIRE_FIELD_PRESENCE_CHANGED,
          category: :wire,
          message:
            ~s(Field "#{new_f.name}" presence changed ) <>
              "from #{presence_label(old_p)} to #{presence_label(new_p)}.",
          path: path,
          location: %{struct: struct.name, field: new_f.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp presence_label(nil), do: "optional"
  defp presence_label(presence) when is_atom(presence), do: Atom.to_string(presence)

  defp check_constant_value_changed(issues, struct, old_f, new_f, path) do
    if old_f.presence == :constant and new_f.presence == :constant and
         old_f.value != new_f.value do
      [
        %Issue{
          rule: :WIRE_FIELD_CONSTANT_VALUE_CHANGED,
          category: :wire,
          message:
            ~s(Constant field "#{new_f.name}" value changed ) <>
              "from #{inspect(old_f.value)} to #{inspect(new_f.value)}.",
          path: path,
          location: %{struct: struct.name, field: new_f.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_type_params_changed(issues, struct, old_f, new_f, path) do
    if old_f.type_params != new_f.type_params and
         not (old_f.type_params == [] and new_f.type_params == []) do
      [
        %Issue{
          rule: :WIRE_FIELD_TYPE_PARAMS_CHANGED,
          category: :wire,
          message:
            ~s(Field "#{new_f.name}" type parameters changed ) <>
              "from #{inspect(old_f.type_params)} to #{inspect(new_f.type_params)}.",
          path: path,
          location: %{struct: struct.name, field: new_f.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_field_type_change(
         issues,
         _old_struct,
         new_struct,
         old_f,
         new_f,
         _idx,
         new_schema,
         path
       ) do
    old_size = WireSizes.resolve(old_f.type, new_schema.types)
    new_size = WireSizes.resolve(new_f.type, new_schema.types)

    if old_size != new_size or old_size == :unknown do
      [
        %Issue{
          rule: :WIRE_FIELD_TYPE_CHANGED,
          category: :wire,
          message: "Field \"#{new_f.name}\" type changed from #{old_f.type} to #{new_f.type}.",
          path: path,
          location: %{struct: new_struct.name, field: new_f.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  # ============================================================================
  # Group-level rules
  # ============================================================================

  defp check_groups(issues, %StructDef{} = old, %StructDef{} = new, new_schema, path) do
    group_diff = Differ.diff_groups(old.groups, new.groups)

    issues
    |> check_group_removed(group_diff, new.name, path)
    |> check_group_changes(group_diff, new, new_schema, path)
  end

  defp check_group_removed(issues, %{removed: removed}, struct_name, path) do
    Enum.reduce(removed, issues, fn {name, _group}, acc ->
      [
        %Issue{
          rule: :WIRE_GROUP_REMOVED,
          category: :wire,
          message: "Group \"#{name}\" was removed.",
          path: path,
          location: %{struct: struct_name, group: name}
        }
        | acc
      ]
    end)
  end

  defp check_group_changes(issues, %{changed: changed}, new_struct, new_schema, path) do
    Enum.reduce(changed, issues, fn {_name, old_group, new_group}, acc ->
      field_diffs = Differ.diff_fields(old_group.fields, new_group.fields)

      Enum.reduce(field_diffs, acc, fn {_idx, old_f, new_f}, acc2 ->
        cond do
          old_f != nil and new_f == nil ->
            [
              %Issue{
                rule: :WIRE_GROUP_FIELD_REMOVED,
                category: :wire,
                message: "Field \"#{old_f.name}\" removed from group \"#{new_group.name}\".",
                path: path,
                location: %{struct: new_struct.name, group: new_group.name, field: old_f.name}
              }
              | acc2
            ]

          old_f != nil and new_f != nil and old_f.type != new_f.type ->
            old_size = WireSizes.resolve(old_f.type, new_schema.types)
            new_size = WireSizes.resolve(new_f.type, new_schema.types)

            if old_size != new_size or old_size == :unknown do
              [
                %Issue{
                  rule: :WIRE_GROUP_FIELD_TYPE_CHANGED,
                  category: :wire,
                  message:
                    ~s(Field "#{new_f.name}" in group "#{new_group.name}" ) <>
                      "type changed from #{old_f.type} to #{new_f.type}.",
                  path: path,
                  location: %{struct: new_struct.name, group: new_group.name, field: new_f.name}
                }
                | acc2
              ]
            else
              acc2
            end

          old_f != nil and new_f != nil and old_f.name != new_f.name ->
            [
              %Issue{
                rule: :WIRE_GROUP_FIELD_REORDERED,
                category: :wire,
                message:
                  "Field in group \"#{new_group.name}\" changed from " <>
                    "\"#{old_f.name}\" to \"#{new_f.name}\".",
                path: path,
                location: %{struct: new_struct.name, group: new_group.name, field: new_f.name}
              }
              | acc2
            ]

          true ->
            acc2
        end
      end)
    end)
  end

  # ============================================================================
  # Batch-level rules
  # ============================================================================

  defp check_batches(issues, %StructDef{} = old, %StructDef{} = new, path) do
    batch_diff = Differ.diff_batches(old.batches, new.batches)

    issues
    |> check_batch_removed(batch_diff, new.name, path)
    |> check_batch_changes(batch_diff, new.name, path)
  end

  defp check_batch_removed(issues, %{removed: removed}, struct_name, path) do
    Enum.reduce(removed, issues, fn {name, _batch}, acc ->
      [
        %Issue{
          rule: :WIRE_BATCH_REMOVED,
          category: :wire,
          message: "Batch \"#{name}\" was removed.",
          path: path,
          location: %{struct: struct_name, batch: name}
        }
        | acc
      ]
    end)
  end

  defp check_batch_changes(issues, %{changed: changed}, struct_name, path) do
    Enum.reduce(changed, issues, fn {_name, old_batch, new_batch}, acc ->
      acc
      |> check_batch_strategy(old_batch, new_batch, struct_name, path)
      |> check_batch_types(old_batch, new_batch, struct_name, path)
    end)
  end

  defp check_batch_strategy(issues, old_batch, new_batch, struct_name, path) do
    if old_batch.strategy != new_batch.strategy do
      [
        %Issue{
          rule: :WIRE_BATCH_STRATEGY_CHANGED,
          category: :wire,
          message:
            "Batch \"#{new_batch.name}\" strategy changed " <>
              "from #{old_batch.strategy} to #{new_batch.strategy}.",
          path: path,
          location: %{struct: struct_name, batch: new_batch.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_batch_types(issues, old_batch, new_batch, struct_name, path) do
    old_set = MapSet.new(old_batch.any_of)
    new_set = MapSet.new(new_batch.any_of)
    removed = MapSet.difference(old_set, new_set)

    issues =
      Enum.reduce(removed, issues, fn type_name, acc ->
        [
          %Issue{
            rule: :WIRE_BATCH_TYPE_REMOVED,
            category: :wire,
            message: "Type \"#{type_name}\" removed from batch \"#{new_batch.name}\" any_of.",
            path: path,
            location: %{struct: struct_name, batch: new_batch.name}
          }
          | acc
        ]
      end)

    if old_batch.any_of != new_batch.any_of and MapSet.equal?(old_set, new_set) do
      [
        %Issue{
          rule: :WIRE_BATCH_TYPE_REORDERED,
          category: :wire,
          message: "Type order changed in batch \"#{new_batch.name}\" any_of (tag reassignment).",
          path: path,
          location: %{struct: struct_name, batch: new_batch.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  # ============================================================================
  # Enum-level rules
  # ============================================================================

  defp check_enums(issues, %{enums: enum_diff}, path) do
    issues
    |> check_enum_changes(enum_diff, path)
  end

  defp check_enum_changes(issues, %{changed: changed}, path) do
    Enum.reduce(changed, issues, fn {_name, old_enum, new_enum}, acc ->
      acc
      |> check_enum_underlying(old_enum, new_enum, path)
      |> check_enum_values(old_enum, new_enum, path)
    end)
  end

  defp check_enum_underlying(issues, %EnumDef{} = old, %EnumDef{} = new, path) do
    if old.underlying_type != new.underlying_type do
      [
        %Issue{
          rule: :WIRE_ENUM_UNDERLYING_CHANGED,
          category: :wire,
          message:
            "Enum \"#{new.name}\" underlying type changed " <>
              "from #{old.underlying_type} to #{new.underlying_type}.",
          path: path,
          location: %{enum: new.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_enum_values(issues, %EnumDef{} = old, %EnumDef{} = new, path) do
    value_diff = Differ.diff_enum_values(old.values, new.values)

    issues =
      Enum.reduce(value_diff.removed, issues, fn {name, _val}, acc ->
        [
          %Issue{
            rule: :WIRE_ENUM_VALUE_REMOVED,
            category: :wire,
            message: "Enum value \"#{name}\" removed from \"#{new.name}\".",
            path: path,
            location: %{enum: new.name, value: name}
          }
          | acc
        ]
      end)

    Enum.reduce(value_diff.changed, issues, fn {value_name, old_int, new_int}, acc ->
      [
        %Issue{
          rule: :WIRE_ENUM_VALUE_CHANGED,
          category: :wire,
          message:
            ~s(Enum value "#{value_name}" in "#{new.name}" ) <>
              "changed from #{old_int} to #{new_int}.",
          path: path,
          location: %{enum: new.name, value: value_name}
        }
        | acc
      ]
    end)
  end

  # ============================================================================
  # Custom type rules (prefixed_id, char_array, bitset)
  # ============================================================================

  defp check_custom_types(issues, %{types: type_diff}, path) do
    Enum.reduce(type_diff.changed, issues, fn {_name, old_type, new_type}, acc ->
      check_custom_type_change(acc, old_type, new_type, path)
    end)
  end

  defp check_custom_type_change(
         issues,
         %{kind: :prefixed_id} = old,
         %{kind: :prefixed_id} = new,
         path
       ) do
    issues =
      if old.params[:tag] != new.params[:tag] do
        [
          %Issue{
            rule: :WIRE_PREFIXED_ID_TAG_CHANGED,
            category: :wire,
            message:
              "PrefixedId \"#{new.name}\" tag changed from #{old.params[:tag]} to #{new.params[:tag]}.",
            path: path,
            location: %{type: new.name}
          }
          | issues
        ]
      else
        issues
      end

    if old.params[:prefix] != new.params[:prefix] do
      [
        %Issue{
          rule: :SOURCE_PREFIXED_ID_PREFIX_CHANGED,
          category: :source,
          message:
            "PrefixedId \"#{new.name}\" prefix changed " <>
              "from \"#{old.params[:prefix]}\" to \"#{new.params[:prefix]}\".",
          path: path,
          location: %{type: new.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_custom_type_change(
         issues,
         %{kind: :char_array} = old,
         %{kind: :char_array} = new,
         path
       ) do
    if old.params[:length] != new.params[:length] do
      [
        %Issue{
          rule: :WIRE_CHAR_ARRAY_LENGTH_CHANGED,
          category: :wire,
          message:
            "CharArray \"#{new.name}\" length changed from #{old.params[:length]} to #{new.params[:length]}.",
          path: path,
          location: %{type: new.name}
        }
        | issues
      ]
    else
      issues
    end
  end

  defp check_custom_type_change(issues, %{kind: :bitset} = old, %{kind: :bitset} = new, path) do
    issues =
      if old.underlying_type != new.underlying_type do
        [
          %Issue{
            rule: :WIRE_BITSET_UNDERLYING_CHANGED,
            category: :wire,
            message:
              "Bitset \"#{new.name}\" underlying type changed " <>
                "from #{old.underlying_type} to #{new.underlying_type}.",
            path: path,
            location: %{type: new.name}
          }
          | issues
        ]
      else
        issues
      end

    flag_diff = Differ.diff_enum_values(old.values, new.values)

    issues =
      Enum.reduce(flag_diff.removed, issues, fn {name, _val}, acc ->
        [
          %Issue{
            rule: :WIRE_BITSET_FLAG_REMOVED,
            category: :wire,
            message: "Bitset flag \"#{name}\" removed from \"#{new.name}\".",
            path: path,
            location: %{type: new.name, flag: name}
          }
          | acc
        ]
      end)

    Enum.reduce(flag_diff.changed, issues, fn {flag_name, old_bit, new_bit}, acc ->
      [
        %Issue{
          rule: :WIRE_BITSET_FLAG_VALUE_CHANGED,
          category: :wire,
          message:
            ~s(Bitset flag "#{flag_name}" in "#{new.name}" ) <>
              "bit position changed from #{old_bit} to #{new_bit}.",
          path: path,
          location: %{type: new.name, flag: flag_name}
        }
        | acc
      ]
    end)
  end

  defp check_custom_type_change(issues, _old, _new, _path), do: issues
end
