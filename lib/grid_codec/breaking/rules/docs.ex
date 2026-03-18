defmodule GridCodec.Breaking.Rules.Docs do
  @moduledoc """
  Documentation drift rules for `.grid` schema files.

  These rules track declaration-level documentation changes that affect schema
  usability and generated docs without changing the wire format.
  """

  alias GridCodec.Breaking.Differ
  alias GridCodec.Breaking.Issue

  @doc "Runs all documentation rules against a schema diff and returns a list of issues."
  @spec check(Differ.schema_diff(), String.t()) :: [Issue.t()]
  def check(schema_diff, path) do
    []
    |> check_struct_field_docs(schema_diff, path)
    |> check_group_docs(schema_diff, path)
    |> check_group_field_docs(schema_diff, path)
    |> check_enum_value_docs(schema_diff, path)
    |> Enum.reverse()
  end

  defp check_struct_field_docs(issues, %{structs: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_struct, new_struct}, acc ->
      old_struct.fields
      |> Differ.diff_fields(new_struct.fields)
      |> Enum.reduce(acc, fn {_idx, old_f, new_f}, acc2 ->
        if old_f != nil and new_f != nil and old_f.name == new_f.name do
          maybe_add_doc_issue(
            acc2,
            doc_transition_rule(old_f.doc, new_f.doc, :field),
            field_doc_message(new_f.name, old_f.doc, new_f.doc),
            path,
            %{struct: new_struct.name, field: new_f.name}
          )
        else
          acc2
        end
      end)
    end)
  end

  defp check_group_docs(issues, %{structs: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_struct, new_struct}, acc ->
      old_groups = Map.new(old_struct.groups, &{&1.name, &1})
      new_groups = Map.new(new_struct.groups, &{&1.name, &1})

      Map.keys(old_groups)
      |> Enum.filter(&Map.has_key?(new_groups, &1))
      |> Enum.reduce(acc, fn group_name, acc2 ->
        old_group = Map.fetch!(old_groups, group_name)
        new_group = Map.fetch!(new_groups, group_name)

        maybe_add_doc_issue(
          acc2,
          doc_transition_rule(old_group.doc, new_group.doc, :group),
          group_doc_message(group_name, old_group.doc, new_group.doc),
          path,
          %{struct: new_struct.name, group: group_name}
        )
      end)
    end)
  end

  defp check_group_field_docs(issues, %{structs: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_struct, new_struct}, acc ->
      old_groups = Map.new(old_struct.groups, &{&1.name, &1})
      new_groups = Map.new(new_struct.groups, &{&1.name, &1})

      Map.keys(old_groups)
      |> Enum.filter(&Map.has_key?(new_groups, &1))
      |> Enum.reduce(acc, fn group_name, acc2 ->
        old_group = Map.fetch!(old_groups, group_name)
        new_group = Map.fetch!(new_groups, group_name)

        old_group.fields
        |> Differ.diff_fields(new_group.fields)
        |> Enum.reduce(acc2, fn {_idx, old_f, new_f}, acc3 ->
          if old_f != nil and new_f != nil and old_f.name == new_f.name do
            maybe_add_doc_issue(
              acc3,
              doc_transition_rule(old_f.doc, new_f.doc, :group_field),
              group_field_doc_message(group_name, new_f.name, old_f.doc, new_f.doc),
              path,
              %{struct: new_struct.name, group: group_name, field: new_f.name}
            )
          else
            acc3
          end
        end)
      end)
    end)
  end

  defp check_enum_value_docs(issues, %{enums: %{changed: changed}}, path) do
    Enum.reduce(changed, issues, fn {_name, old_enum, new_enum}, acc ->
      old_values = enum_doc_map(old_enum.values)
      new_values = enum_doc_map(new_enum.values)

      Map.keys(old_values)
      |> Enum.filter(&Map.has_key?(new_values, &1))
      |> Enum.reduce(acc, fn value_name, acc2 ->
        {old_int, old_doc} = Map.fetch!(old_values, value_name)
        {new_int, new_doc} = Map.fetch!(new_values, value_name)

        if old_int == new_int do
          maybe_add_doc_issue(
            acc2,
            doc_transition_rule(old_doc, new_doc, :enum_value),
            enum_value_doc_message(new_enum.name, value_name, old_doc, new_doc),
            path,
            %{enum: new_enum.name, value: value_name}
          )
        else
          acc2
        end
      end)
    end)
  end

  defp enum_doc_map(values) do
    Map.new(values, fn
      {name, int} -> {name, {int, nil}}
      {name, int, doc} -> {name, {int, doc}}
    end)
  end

  defp doc_transition_rule(old_doc, new_doc, prefix) do
    cond do
      blank_doc?(old_doc) and blank_doc?(new_doc) ->
        nil

      old_doc == new_doc ->
        nil

      blank_doc?(old_doc) ->
        rule(prefix, :ADDED)

      blank_doc?(new_doc) ->
        rule(prefix, :REMOVED)

      true ->
        rule(prefix, :CHANGED)
    end
  end

  defp rule(:field, suffix), do: :"DOC_FIELD_DOC_#{suffix}"
  defp rule(:group, suffix), do: :"DOC_GROUP_DOC_#{suffix}"
  defp rule(:group_field, suffix), do: :"DOC_GROUP_FIELD_DOC_#{suffix}"
  defp rule(:enum_value, suffix), do: :"DOC_ENUM_VALUE_DOC_#{suffix}"

  defp maybe_add_doc_issue(issues, nil, _message, _path, _location), do: issues

  defp maybe_add_doc_issue(issues, rule, message, path, location) do
    [
      %Issue{rule: rule, category: :docs, message: message, path: path, location: location}
      | issues
    ]
  end

  defp field_doc_message(field_name, old_doc, new_doc) do
    ~s(Field "#{field_name}" documentation #{doc_transition_text(old_doc, new_doc)}.)
  end

  defp group_doc_message(group_name, old_doc, new_doc) do
    ~s(Group "#{group_name}" documentation #{doc_transition_text(old_doc, new_doc)}.)
  end

  defp group_field_doc_message(group_name, field_name, old_doc, new_doc) do
    ~s(Group field "#{group_name}.#{field_name}" documentation #{doc_transition_text(old_doc, new_doc)}.)
  end

  defp enum_value_doc_message(enum_name, value_name, old_doc, new_doc) do
    ~s(Enum value "#{enum_name}.#{value_name}" documentation #{doc_transition_text(old_doc, new_doc)}.)
  end

  defp doc_transition_text(old_doc, new_doc) do
    cond do
      blank_doc?(old_doc) and not blank_doc?(new_doc) ->
        "was added"

      not blank_doc?(old_doc) and blank_doc?(new_doc) ->
        "was removed"

      true ->
        ~s(changed from #{inspect(old_doc)} to #{inspect(new_doc)})
    end
  end

  defp blank_doc?(doc), do: doc in [nil, ""]
end
