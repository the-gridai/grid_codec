# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc
defmodule GridCodec.RequiredFieldsInvariantTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GridCodec.Generators

  # Same core set as CodecDoctestTest, plus evolution codecs that exercise
  # :required / :default / groups / batches / wire_format / constants.
  @codec_modules [
    GridCodec.TestSupport.OrderEvent,
    GridCodec.TestSupport.OrderEventNoTypespec,
    GridCodec.TestSupport.OrderEventVar,
    GridCodec.TestSupport.RequiredTypesStruct,
    GridCodec.TestSupport.ConstantTypesStruct,
    GridCodec.TestSupport.Batch.SmallCommand,
    GridCodec.TestSupport.Batch.MediumCommand,
    GridCodec.TestSupport.Batch.LargeCommand,
    GridCodec.ZSEdge.EnumCodec,
    GridCodec.ZSEdge.BitsetCodec,
    GridCodec.ZSEdge.CharCodec,
    GridCodec.ZSEdge.AllNilCodec,
    GridCodec.ZSEdge.StringCodec,
    GridCodec.ZSEdge.IntegerCodec,
    GridCodec.ZSEdge.PosdecCodec,
    GridCodec.ZSEdge.F64Codec,
    GridCodec.TestSupport.SchemaEvo.ReqSinceAltV2WithDefault,
    GridCodec.TestSupport.SchemaEvo.DefaultsEvolV2,
    GridCodec.TestSupport.SchemaEvo.GroupPadReqReaderV2,
    GridCodec.TestSupport.SchemaEvo.GroupPadReqDefaultV2,
    GridCodec.TestSupport.SchemaEvo.BatchParentV2,
    GridCodec.TestSupport.SchemaEvo.ConstAppendV2
  ]

  defp required_top_level_fields(mod) do
    schema = mod.__schema__()

    for {name, _type, opts} <- schema.fields,
        Keyword.get(opts, :presence, :optional) == :required,
        do: name
  end

  defp assert_top_level_required_non_nil!(mod, struct) do
    for name <- required_top_level_fields(mod) do
      assert Map.fetch!(struct, name) != nil,
             "expected #{inspect(mod)} decode to set non-nil :#{name} (typespec contract)"
    end
  end

  defp assert_groups_materialized_required_non_nil!(mod, struct) do
    schema = mod.__schema__()

    Enum.each(schema.group_fields || %{}, fn {gname, gfields} ->
      group = Map.fetch!(struct, gname)

      case group do
        %GridCodec.Group{} = g ->
          entries = GridCodec.Group.to_list(g)

          req_names =
            for {fname, _t, fo} <- gfields,
                Keyword.get(fo, :presence, :optional) == :required,
                do: fname

          for entry <- entries, fname <- req_names do
            assert Map.fetch!(entry, fname) != nil,
                   "expected #{inspect(mod)} group :#{gname} entry :#{fname} non-nil after materialize"
          end

        _ ->
          :ok
      end
    end)
  end

  defp assert_batch_entries_required_non_nil!(struct) do
    mod = struct.__struct__
    schema = mod.__schema__()

    Enum.each(schema.batches || [], fn {batch_name, _any_of, _strategy} ->
      case Map.fetch(struct, batch_name) do
        {:ok, %GridCodec.Batch{} = batch} ->
          for {_seq, _tag, entry} <- GridCodec.Batch.to_list(batch),
              is_struct(entry) do
            inner_mod = entry.__struct__
            assert_top_level_required_non_nil!(inner_mod, entry)
          end

        _ ->
          :ok
      end
    end)
  end

  test "enumerated codec list stays non-empty" do
    assert length(@codec_modules) >= 12
  end

  describe "same-version encode/decode required-field contract" do
    property "decoded structs never have nil in top-level :required fields" do
      mod_attrs_gen =
        bind(member_of(@codec_modules), fn mod ->
          map(Generators.for_codec(mod), fn attrs -> {mod, attrs} end)
        end)

      check all({mod, attrs} <- mod_attrs_gen, max_runs: 80) do
        struct = struct!(mod, attrs)

        case mod.encode(struct) do
          {:ok, bin} ->
            assert {:ok, decoded} = mod.decode(bin)
            assert_top_level_required_non_nil!(mod, decoded)
            assert_groups_materialized_required_non_nil!(mod, decoded)
            assert_batch_entries_required_non_nil!(decoded)

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
