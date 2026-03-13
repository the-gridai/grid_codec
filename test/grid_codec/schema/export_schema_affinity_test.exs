defmodule GridCodec.Schema.ExportSchemaAffinityTest do
  use ExUnit.Case, async: true

  alias GridCodec.Schema.Formatter

  defmodule AffinityPrefixedId do
    @moduledoc false
    use GridCodec.Types.PrefixedId, prefix: "aff", tag: 0x20, schema: "target_schema"
  end

  defmodule NoAffinityPrefixedId do
    @moduledoc false
    use GridCodec.Types.PrefixedId, prefix: "naf", tag: 0x21
  end

  describe "schema affinity in custom type home placement" do
    setup do
      schema_names = %{100 => "source_schema", 200 => "target_schema"}

      grouped = %{
        100 => [
          {SourceMod,
           %{
             fields: [
               {:entity_id, AffinityPrefixedId, []},
               {:other_id, NoAffinityPrefixedId, []}
             ],
             groups: [],
             batches: [],
             group_fields: %{},
             version: 1,
             template_id: 1,
             schema_id: 100,
             type: "Source.Event"
           }}
        ],
        200 => [
          {TargetMod,
           %{
             fields: [{:name, :string16, []}],
             groups: [],
             batches: [],
             group_fields: %{},
             version: 1,
             template_id: 2,
             schema_id: 200,
             type: "Target.Widget"
           }}
        ]
      }

      all_custom_types = Formatter.detect_all_custom_types(Map.values(grouped))
      %{grouped: grouped, schema_names: schema_names, all_custom_types: all_custom_types}
    end

    test "type with schema affinity is placed in the named schema", ctx do
      home_map =
        build_custom_type_home_map(ctx.grouped, ctx.schema_names, ctx.all_custom_types)

      affinity_home = Map.fetch!(home_map, AffinityPrefixedId)
      assert affinity_home.schema_id == 200
      assert affinity_home.dir_name == "target_schema"
    end

    test "type without schema affinity stays in lowest referencing schema", ctx do
      home_map =
        build_custom_type_home_map(ctx.grouped, ctx.schema_names, ctx.all_custom_types)

      no_affinity_home = Map.fetch!(home_map, NoAffinityPrefixedId)
      assert no_affinity_home.schema_id == 100
      assert no_affinity_home.dir_name == "source_schema"
    end

    test "unknown schema name in affinity is ignored (keeps heuristic)", _ctx do
      schema_names = %{100 => "source_schema"}

      grouped = %{
        100 => [
          {SourceMod,
           %{
             fields: [{:entity_id, AffinityPrefixedId, []}],
             groups: [],
             batches: [],
             group_fields: %{},
             version: 1,
             template_id: 1,
             schema_id: 100,
             type: "Source.Event"
           }}
        ]
      }

      all_custom_types = Formatter.detect_all_custom_types(Map.values(grouped))
      home_map = build_custom_type_home_map(grouped, schema_names, all_custom_types)

      affinity_home = Map.fetch!(home_map, AffinityPrefixedId)
      assert affinity_home.schema_id == 100, "should fall back to heuristic when name not found"
    end
  end

  # Mirror the export task's private logic for testability.
  # This duplicates the algorithm to verify correctness without
  # requiring Mix.Task infrastructure.
  defp build_custom_type_home_map(grouped, schema_names, all_custom_types) do
    default_map =
      grouped
      |> Enum.sort_by(fn {schema_id, _} -> schema_id end)
      |> Enum.flat_map(fn {schema_id, entries} ->
        dir_name = Map.get(schema_names, schema_id, "schema_#{schema_id}")
        local_types = Formatter.detect_custom_types(entries)

        Enum.map(local_types, fn {mod, info} ->
          rel_path = Macro.underscore(info.short_name) <> ".grid"
          {mod, %{schema_id: schema_id, dir_name: dir_name, rel_path: rel_path}}
        end)
      end)
      |> Enum.reduce(%{}, fn {mod, info}, acc ->
        Map.put_new(acc, mod, info)
      end)

    apply_schema_affinity(default_map, all_custom_types, schema_names)
  end

  defp apply_schema_affinity(home_map, all_custom_types, schema_names) do
    name_to_id = Map.new(schema_names, fn {id, name} -> {name, id} end)

    Enum.reduce(all_custom_types, home_map, fn {mod, info}, acc ->
      affinity = get_in(info, [:params, :schema])

      if affinity do
        case Map.get(name_to_id, affinity) do
          nil ->
            acc

          schema_id ->
            dir_name = Map.get(schema_names, schema_id, "schema_#{schema_id}")
            rel_path = Macro.underscore(info.short_name) <> ".grid"
            Map.put(acc, mod, %{schema_id: schema_id, dir_name: dir_name, rel_path: rel_path})
        end
      else
        acc
      end
    end)
  end
end
