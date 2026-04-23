# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc
defmodule GridCodec.SchemaEvolutionGenerativeTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias GridCodec.TestSupport.SchemaEvo, as: SE

  describe "generative cross-version decode (encode V1 → decode V2)" do
    property "ReqSinceAlt: padded :since field always becomes default 0" do
      check all(
              id <- integer(0..9_999_999_999_999),
              price <- integer(0..4_294_967_290)
            ) do
        v1 = %SE.ReqSinceAltV1{id: id, price: price}
        assert {:ok, bin} = SE.ReqSinceAltV1.encode(v1)
        assert {:ok, out} = SE.ReqSinceAltV2WithDefault.decode(bin)
        assert out.id == id
        assert out.price == price
        assert out.qty == 0
      end
    end

    property "DefaultsEvol: field_defaults supplies new :since score from padding" do
      check all(id <- integer(0..9_999_999_999_999_999)) do
        v1 = %SE.DefaultsEvolV1{id: id}
        assert {:ok, bin} = SE.DefaultsEvolV1.encode(v1)
        assert {:ok, out} = SE.DefaultsEvolV2.decode(bin)
        assert out.id == id
        assert out.score == 0
      end
    end

    property "EnumEvol: appended enum decodes nil for every historical payload" do
      check all(id <- integer(0..9_999_999_999_999_999)) do
        v1 = %SE.EnumEvolV1{id: id}
        assert {:ok, bin} = SE.EnumEvolV1.encode(v1)
        assert {:ok, out} = SE.EnumEvolV2.decode(bin)
        assert out.id == id
        assert out.side == nil
      end
    end

    property "ScalarScores: u32 scalar list survives parent fixed-block growth" do
      scores_gen = list_of(integer(0..4_294_967_290), min_length: 0, max_length: 24)

      check all(
              owner <- integer(0..9_999_999_999_999_999),
              scores <- scores_gen
            ) do
        v1 = %SE.ScalarScoresV1{owner: owner, scores: scores}
        assert {:ok, bin} = SE.ScalarScoresV1.encode(v1)
        assert {:ok, out} = SE.ScalarScoresV2.decode(bin)
        assert out.owner == owner
        assert out.version_tag == nil
        assert out.scores == scores
      end
    end

    property "BatchPaddedUnion: mixed tiny/wide entries round-trip through V2 reader" do
      tiny_gen = map(integer(0..9_999_999_999_999_999), fn x -> %SE.BatchPaddedTiny{x: x} end)

      wide_gen =
        map(
          tuple({integer(0..9_999_999_999_999_999), integer(0..9_999_999_999_999_999)}),
          fn {a, b} -> %SE.BatchPaddedWide{a: a, b: b} end
        )

      entry_gen = one_of([tiny_gen, wide_gen])

      check all(
              sid <- integer(0..4_294_967_290),
              entries <- list_of(entry_gen, min_length: 0, max_length: 12)
            ) do
        v1 = %SE.BatchPaddedParentV1{sid: sid, cmds: entries}
        assert {:ok, bin} = SE.BatchPaddedParentV1.encode(v1)
        assert {:ok, out} = SE.BatchPaddedParentV2.decode(bin)
        assert out.sid == sid
        assert out.epoch == nil
        assert GridCodec.Batch.count(out.cmds) == length(entries)

        decoded_entries =
          out.cmds
          |> GridCodec.Batch.to_list()
          |> Enum.map(fn {_seq, _tag, e} -> e end)

        assert length(decoded_entries) == length(entries)

        Enum.zip(entries, decoded_entries)
        |> Enum.each(fn {orig, dec} ->
          assert orig.__struct__ == dec.__struct__
          assert Map.from_struct(orig) == Map.from_struct(dec)
        end)
      end
    end
  end
end
