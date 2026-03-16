defmodule GridCodec.Breaking.Differ do
  @moduledoc """
  Produces structural diffs between two parsed `.grid` schemas.

  Matches entities (structs, enums, types) by name and computes
  added/removed/changed sets for the breaking change rules to evaluate.
  """

  alias GridCodec.Schema.Parser.BatchDef
  alias GridCodec.Schema.Parser.Field
  alias GridCodec.Schema.Parser.Group
  alias GridCodec.Schema.Parser.Schema

  @type entity_diff :: %{
          added: map(),
          removed: map(),
          changed: [{old :: term(), new :: term()}]
        }

  @type schema_diff :: %{
          structs: entity_diff(),
          enums: entity_diff(),
          types: entity_diff(),
          schema: %{old: Schema.t(), new: Schema.t()}
        }

  @doc """
  Diffs two parsed schemas and returns a structured diff map.

  The `old` schema is the baseline and `new` is the current version.
  """
  @spec diff(Schema.t(), Schema.t()) :: schema_diff()
  def diff(%Schema{} = old, %Schema{} = new) do
    %{
      structs: diff_named_map(old.structs, new.structs),
      enums: diff_named_map(old.enums, new.enums),
      types: diff_named_map(old.types, new.types),
      schema: %{old: old, new: new}
    }
  end

  @doc """
  Diffs two field lists by position, returning per-index changes.

  Returns a list of `{index, old_field | nil, new_field | nil}` tuples
  for every position where something changed.
  """
  @spec diff_fields([Field.t()], [Field.t()]) :: [
          {non_neg_integer(), Field.t() | nil, Field.t() | nil}
        ]
  def diff_fields(old_fields, new_fields) do
    max_len = max(length(old_fields), length(new_fields))

    if max_len == 0 do
      []
    else
      old_indexed = old_fields |> Enum.with_index() |> Map.new(fn {f, i} -> {i, f} end)
      new_indexed = new_fields |> Enum.with_index() |> Map.new(fn {f, i} -> {i, f} end)

      Enum.reduce((max_len - 1)..0//-1, [], fn i, acc ->
        old_f = Map.get(old_indexed, i)
        new_f = Map.get(new_indexed, i)

        if old_f != new_f do
          [{i, old_f, new_f} | acc]
        else
          acc
        end
      end)
    end
  end

  @doc "Diffs two group lists by name."
  @spec diff_groups([Group.t()], [Group.t()]) :: entity_diff()
  def diff_groups(old_groups, new_groups) do
    old_map = Map.new(old_groups, fn g -> {g.name, g} end)
    new_map = Map.new(new_groups, fn g -> {g.name, g} end)
    diff_named_map(old_map, new_map)
  end

  @doc "Diffs two batch lists by name."
  @spec diff_batches([BatchDef.t()], [BatchDef.t()]) :: entity_diff()
  def diff_batches(old_batches, new_batches) do
    old_map = Map.new(old_batches, fn b -> {b.name, b} end)
    new_map = Map.new(new_batches, fn b -> {b.name, b} end)
    diff_named_map(old_map, new_map)
  end

  @doc "Diffs enum values (ordered list of {name, int} tuples) by name."
  @spec diff_enum_values([{atom(), integer()}], [{atom(), integer()}]) :: entity_diff()
  def diff_enum_values(old_values, new_values) do
    old_map = Map.new(old_values)
    new_map = Map.new(new_values)
    diff_named_map(old_map, new_map)
  end

  defp diff_named_map(old_map, new_map) do
    old_keys = MapSet.new(Map.keys(old_map))
    new_keys = MapSet.new(Map.keys(new_map))

    removed_keys = MapSet.difference(old_keys, new_keys)
    added_keys = MapSet.difference(new_keys, old_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    changed =
      common_keys
      |> Enum.filter(fn k -> Map.fetch!(old_map, k) != Map.fetch!(new_map, k) end)
      |> Enum.map(fn k -> {k, Map.fetch!(old_map, k), Map.fetch!(new_map, k)} end)

    %{
      added: Map.take(new_map, MapSet.to_list(added_keys)),
      removed: Map.take(old_map, MapSet.to_list(removed_keys)),
      changed: changed
    }
  end
end
