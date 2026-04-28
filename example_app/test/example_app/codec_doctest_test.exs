defmodule ExampleApp.CodecDoctestTest do
  @moduledoc false
  use ExUnit.Case, async: true

  import ExUnit.DocTest

  @app :example_app

  defp codec_modules do
    @app
    |> Application.spec(:modules)
    |> List.wrap()
    |> Enum.filter(fn mod ->
      mod
      |> Atom.to_string()
      |> String.starts_with?("Elixir.ExampleApp.")
    end)
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__gridcodec_struct__?, 0) and
        mod.__gridcodec_struct__?()
    end)
  end

  for mod <- [
        ExampleApp.Events.OrderCreated,
        ExampleApp.Events.MarketCreated,
        ExampleApp.Events.TradeExecuted,
        ExampleApp.Events.TradeSettled,
        ExampleApp.Events.OrderCreatedNoTypespec,
        ExampleApp.Events.OrderCreatedNoTypespecPlain,
        ExampleApp.Events.RequiredDecodeWarningFixture,
        ExampleApp.Events.RequiredDecodeWarningOptionalWriter,
        ExampleApp.Events.RequiredDecodeDefaultOnlyFixture,
        ExampleApp.Events.RequiredDecodeMixedDefaultFixture,
        ExampleApp.Events.RequiredInlineStringWrapperFixture,
        ExampleApp.Views.CommandEnvelope,
        ExampleApp.Views.Reservation,
        ExampleApp.Views.ReleaseReservation,
        ExampleApp.Views.PlaceReservation,
        ExampleApp.Views.CurrencyAccount,
        ExampleApp.Bench.TaggedMetric,
        ExampleApp.Bench.SmallStruct,
        ExampleApp.Bench.MediumStruct,
        ExampleApp.Bench.LargeStruct,
        ExampleApp.Bench.BinaryTraceContext,
        ExampleApp.Bench.BinaryEnvelope
      ] do
    doctest mod
  end

  test "discovered ExampleApp codec modules stay in sync with doctest allowlist" do
    discovered = codec_modules() |> MapSet.new()

    allow =
      MapSet.new([
        ExampleApp.Events.OrderCreated,
        ExampleApp.Events.MarketCreated,
        ExampleApp.Events.TradeExecuted,
        ExampleApp.Events.TradeSettled,
        ExampleApp.Events.OrderCreatedNoTypespec,
        ExampleApp.Events.OrderCreatedNoTypespecPlain,
        ExampleApp.Events.RequiredDecodeWarningFixture,
        ExampleApp.Events.RequiredDecodeWarningOptionalWriter,
        ExampleApp.Events.RequiredDecodeDefaultOnlyFixture,
        ExampleApp.Events.RequiredDecodeMixedDefaultFixture,
        ExampleApp.Events.RequiredInlineStringWrapperFixture,
        ExampleApp.Views.CommandEnvelope,
        ExampleApp.Views.Reservation,
        ExampleApp.Views.ReleaseReservation,
        ExampleApp.Views.PlaceReservation,
        ExampleApp.Views.CurrencyAccount,
        ExampleApp.Bench.TaggedMetric,
        ExampleApp.Bench.SmallStruct,
        ExampleApp.Bench.MediumStruct,
        ExampleApp.Bench.LargeStruct,
        ExampleApp.Bench.BinaryTraceContext,
        ExampleApp.Bench.BinaryEnvelope
      ])

    assert MapSet.equal?(discovered, allow),
           """
           ExampleApp codec modules changed; update codec_doctest_test allowlist (and doctest loop).

           only in app: #{inspect(MapSet.difference(discovered, allow))}
           only in list: #{inspect(MapSet.difference(allow, discovered))}
           """
  end

  test "ExampleApp codecs include iex> in generated function docs" do
    for mod <- codec_modules() do
      entries = doc_entries(mod)

      assert Enum.any?(entries, fn entry ->
               case doc_markdown(entry) do
                 bin when is_binary(bin) -> String.contains?(bin, "iex>")
                 _ -> false
               end
             end),
             "expected #{inspect(mod)} to include iex> snippets"
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
