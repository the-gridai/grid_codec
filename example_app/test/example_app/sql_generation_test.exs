defmodule ExampleApp.SQLGenerationTest do
  use ExUnit.Case, async: true

  alias ExampleApp.Events.OrderCreated
  alias ExampleApp.Views.CurrencyAccount
  alias GridCodec.SQL

  test "consumer codecs generate typed and universal PostgreSQL decoders" do
    typed_sql = SQL.generate(CurrencyAccount)

    assert typed_sql =~
             "CREATE OR REPLACE FUNCTION gridcodec.decode_exampleapp_views_currencyaccount"

    assert typed_sql =~ ~s("reservations" jsonb)
    assert typed_sql =~ "jsonb_agg("
    assert typed_sql =~ "gridcodec.read_u16(data, 0)"

    catalog_sql = SQL.generate_all([OrderCreated, CurrencyAccount])

    assert catalog_sql =~
             "WHEN type_name = 'ExampleApp.Views.CurrencyAccount' THEN " <>
               "gridcodec.decode_exampleapp_views_currencyaccount_json(data)"

    assert catalog_sql =~ "WHEN type_name = 'OrderCreated'"
  end

  test "consumer event tables can expose an indexed whole-stream decoder" do
    sql =
      SQL.generate_stream_decoder(
        function: "public.decode_gridcodec_test_stream",
        table: "public.gridcodec_test_events",
        stream_id_type: :text
      )

    assert sql =~ "target_stream_id text"
    assert sql =~ ~s(events."stream_id" = target_stream_id)
    assert sql =~ ~s(ORDER BY events."stream_version")
    assert sql =~ ~s|gridcodec.decode(events."event_type"::text, events."data")|
  end

  test "consumer event tables can retrieve raw or selectively decoded streams" do
    raw_sql =
      SQL.generate_stream_decoder(
        function: "public.read_gridcodec_test_stream",
        table: "public.gridcodec_test_events",
        stream_id_type: :text,
        decode: :raw
      )

    assert raw_sql =~ "RETURNS TABLE (stream_version bigint, event_type text, data bytea)"
    refute raw_sql =~ "gridcodec.decode("

    projected_sql =
      SQL.generate_stream_decoder(
        function: "public.read_order_stream",
        table: "public.gridcodec_test_events",
        decode: {:fields, OrderCreated, [:side, :price, :quantity]}
      )

    assert projected_sql =~ "gridcodec.read_ordercreated_side"
    assert projected_sql =~ "gridcodec.read_ordercreated_price"
    assert projected_sql =~ "gridcodec.read_ordercreated_quantity"
    refute projected_sql =~ "gridcodec.decode("
  end
end
