defmodule ExampleApp.SQLGenerationTest do
  use ExUnit.Case, async: true

  alias ExampleApp.Events.OrderCreated
  alias ExampleApp.SQL.Catalog
  alias ExampleApp.Views.CurrencyAccount
  alias GridCodec.SQL

  @table "public.gridcodec_test_events"

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

  test "consumer catalog exposes indexed, paged, and mixed-type stream readers" do
    sql = Enum.join(Catalog.install_statements(table: @table), "\n")

    assert sql =~ ~s("decode_event_stream")
    assert sql =~ ~s("read_event_stream")
    assert sql =~ ~s("read_order_stream")
    assert sql =~ ~s("read_typed_order_stream")
    assert sql =~ ~s("read_market_stream")
    assert sql =~ ~s("read_market_stream_version")

    assert sql =~ "start_version bigint DEFAULT 1, max_count integer DEFAULT NULL"
    assert sql =~ ~s(events."stream_version" >= start_version)
    assert sql =~ "LIMIT max_count;"
    assert sql =~ ~s|events."event_type" IN ('OrderCreated', 'TradeExecuted')|
    assert sql =~ ~s|COALESCE(MAX(events."stream_version"), 0)::bigint|
    assert sql =~ "RETURNS TABLE (stream_version bigint, event_type text, data bytea)"
    assert sql =~ ~s("order_id" uuid)
    assert sql =~ "gridcodec.read_ordercreated_side"
    assert sql =~ "gridcodec.read_ordercreated_price"
    assert sql =~ "gridcodec.read_ordercreated_quantity"
  end

  test "consumer catalog drops both stream-decoder overloads" do
    drop = Enum.join(Catalog.drop_statements(table: @table), "\n")

    assert drop =~ "DO $gridcodec$"
    assert drop =~ ~s|DROP FUNCTION IF EXISTS "public"."read_market_stream"(text)|

    assert drop =~
             ~s|DROP FUNCTION IF EXISTS "public"."read_market_stream"(text, bigint, integer)|

    assert drop =~
             ~s|DROP FUNCTION IF EXISTS "public"."read_market_stream_version"(text)|
  end
end
