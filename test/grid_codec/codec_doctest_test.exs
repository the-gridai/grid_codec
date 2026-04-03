defmodule GridCodec.CodecDoctestTest do
  @moduledoc false
  use ExUnit.Case, async: true

  import ExUnit.DocTest

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
    GridCodec.ZSEdge.F64Codec
  ]

  for mod <- @codec_modules do
    doctest mod
  end

  test "enumerated codec modules include runnable iex> in at least one function @doc" do
    for mod <- @codec_modules do
      entries = doc_entries(mod)

      assert Enum.any?(entries, fn entry ->
               case doc_markdown(entry) do
                 bin when is_binary(bin) -> String.contains?(bin, "iex>")
                 _ -> false
               end
             end),
             "expected #{inspect(mod)} to include iex> snippets (enable doc_examples or extend DocExampleValues)"
    end
  end

  defp doc_entries(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, list} when is_list(list) ->
        list

      {:docs_v1, _, _, _, list} when is_list(list) ->
        list

      _ ->
        []
    end
  end

  defp doc_markdown({_head, _anno, _sig, doc, _meta}) do
    case doc do
      :none -> nil
      :hidden -> nil
      %{"en" => md} when is_binary(md) -> md
      bin when is_binary(bin) -> bin
      _ -> nil
    end
  end
end
