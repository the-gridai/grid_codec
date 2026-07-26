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
end
