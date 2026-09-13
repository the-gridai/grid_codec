defmodule GridCodec.SQLTest do
  use ExUnit.Case, async: false

  alias GridCodec.SQL
  alias GridCodec.TestSupport.SQLGroupsEvent

  # Generate once, reuse across all tests that need it
  @order_event_sql SQL.generate(GridCodec.TestSupport.OrderEvent)
  @helpers_sql SQL.generate_helpers()

  describe "generate_helpers/0" do
    test "produces valid SQL with all helper functions" do
      sql = @helpers_sql

      assert sql =~ "CREATE SCHEMA IF NOT EXISTS gridcodec;"
      assert sql =~ "CREATE SCHEMA IF NOT EXISTS gridcodec_enums;"
      assert sql =~ "gridcodec.read_header"
      assert sql =~ "gridcodec.read_u8"
      assert sql =~ "gridcodec.read_u16"
      assert sql =~ "gridcodec.read_u32"
      assert sql =~ "gridcodec.read_u64"
      assert sql =~ "gridcodec.read_i64"
      assert sql =~ "gridcodec.read_i64_bigint"
      assert sql =~ "gridcodec.read_uuid"
      assert sql =~ "gridcodec.read_uuid_nullable"
      assert sql =~ "gridcodec.read_decimal"
      assert sql =~ "gridcodec.read_timestamp_us"
      assert sql =~ "gridcodec.read_bool"
      assert sql =~ "gridcodec.read_string16"
    end

    test "decodes signed i64 values with native bigint arithmetic" do
      assert @helpers_sql =~
               "CREATE OR REPLACE FUNCTION gridcodec.read_i64_bigint(data bytea, pos int)"

      assert @helpers_sql =~ "(get_byte(data, pos + 7)::bigint << 56)"
      assert @helpers_sql =~ "gridcodec.read_i64_bigint(data, pos)::double precision"
    end

    test "all helper functions are IMMUTABLE STRICT" do
      function_count =
        @helpers_sql
        |> String.split("LANGUAGE sql IMMUTABLE STRICT")
        |> length()

      assert function_count >= 13
    end
  end

  describe "generate/1 with enum types" do
    test "generates enum lookup tables" do
      assert @order_event_sql =~ "CREATE TABLE IF NOT EXISTS gridcodec_enums.side"
      assert @order_event_sql =~ "INSERT INTO gridcodec_enums.side"
      assert @order_event_sql =~ "'buy'"
      assert @order_event_sql =~ "'sell'"
    end

    test "generates enum lookup tables for status" do
      assert @order_event_sql =~ "gridcodec_enums.status"
      assert @order_event_sql =~ "'open'"
      assert @order_event_sql =~ "'filled'"
      assert @order_event_sql =~ "'cancelled'"
    end
  end

  describe "generate/1 decode function" do
    test "generates decode function with correct name" do
      assert @order_event_sql =~ "gridcodec.decode_orderevent"
      assert @order_event_sql =~ "RETURNS TABLE"
    end

    test "includes all fixed fields with correct types" do
      assert @order_event_sql =~ ~s("order_id" uuid)
      assert @order_event_sql =~ ~s("side" text)
      assert @order_event_sql =~ ~s("status" text)
      assert @order_event_sql =~ ~s("price" numeric)
      assert @order_event_sql =~ ~s("quantity" bigint)
      assert @order_event_sql =~ ~s("timestamp" timestamptz)
    end

    test "uses read_uuid_nullable for uuid fields" do
      assert @order_event_sql =~ "gridcodec.read_uuid_nullable(data,"
    end

    test "uses inline enum cases for enum fields" do
      assert @order_event_sql =~ "CASE get_byte(data, 24) WHEN 0 THEN 'buy'"
      assert @order_event_sql =~ "CASE get_byte(data, 25) WHEN 0 THEN 'open'"
      refute @order_event_sql =~ "FROM gridcodec_enums.side e"
      refute @order_event_sql =~ "FROM gridcodec_enums.status e"
    end

    test "uses read_timestamp_us for timestamp fields" do
      assert @order_event_sql =~ "gridcodec.read_timestamp_us(data,"
    end

    test "null checks for u64 fields" do
      assert @order_event_sql =~
               "NULLIF(gridcodec.read_u64(data, 26), 18446744073709551615::numeric)"
    end

    test "null checks for u32 fields" do
      assert @order_event_sql =~ "NULLIF(gridcodec.read_u32(data, 34), 4294967295)"
    end

    test "decode function is IMMUTABLE STRICT" do
      assert @order_event_sql =~ "LANGUAGE sql IMMUTABLE STRICT"
    end
  end

  describe "generate/1 scalar field readers" do
    test "generates direct immutable readers for fixed fields" do
      assert @order_event_sql =~
               "CREATE OR REPLACE FUNCTION gridcodec.read_orderevent_price(data bytea)"

      assert @order_event_sql =~ "RETURNS numeric"
      assert @order_event_sql =~ "NULLIF(gridcodec.read_u64(data,"
      assert @order_event_sql =~ "LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE"
    end

    test "inlines enum values instead of querying a lookup table per row" do
      assert @order_event_sql =~
               "CREATE OR REPLACE FUNCTION gridcodec.read_orderevent_side(data bytea)"

      assert @order_event_sql =~ "CASE get_byte(data,"
      assert @order_event_sql =~ "WHEN 0 THEN 'buy'"
      assert @order_event_sql =~ "WHEN 1 THEN 'sell'"

      refute @order_event_sql =~
               "read_orderevent_side(data bytea)\nRETURNS text AS $$\n  SELECT (SELECT"
    end

    test "does not claim direct readers for variable-length fields" do
      sql = SQL.generate(GridCodec.SQLTest.MultiStringCodec)

      assert sql =~ "gridcodec.read_multistring_id(data bytea)"
      refute sql =~ "gridcodec.read_multistring_name(data bytea)"
      refute sql =~ "gridcodec.read_multistring_description(data bytea)"
    end

    test "guards versioned fields and locates variable data from the wire header" do
      module = Module.concat(__MODULE__, "SQLEvolution#{System.unique_integer([:positive])}")

      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use GridCodec.Struct, template_id: 629, schema_id: 62, version: 3

            defcodec do
              field :event_id, :u64
              field :score, :u32, since: 2
              field :risk_tier, :u16, since: 3
              field :label, :string16
            end
          end
        end
      )

      try do
        sql = SQL.generate(module)

        assert sql =~
                 "CASE WHEN gridcodec.read_u16(data, 6) < 2 THEN NULL ELSE NULLIF(gridcodec.read_u32"

        assert sql =~
                 "CASE WHEN gridcodec.read_u16(data, 6) < 3 THEN NULL ELSE NULLIF(gridcodec.read_u16"

        assert sql =~
                 "gridcodec.read_string16(data, (8 + gridcodec.read_u16(data, 0))::int)"
      after
        :code.purge(module)
        :code.delete(module)
      end
    end
  end

  describe "generate/1 with codec metadata" do
    test "includes codec module in comment" do
      assert @order_event_sql =~ "GridCodec.TestSupport.OrderEvent"
    end

    test "includes type name in comment" do
      assert @order_event_sql =~ ~s("OrderEvent")
    end

    test "includes block_length in comment" do
      assert @order_event_sql =~ "block_length:"
    end
  end

  describe "generate/1 with multiple variable-length fields" do
    defmodule MultiStringCodec do
      use GridCodec.Struct, template_id: 610, schema_id: 61, name: "MultiString"

      defcodec do
        field :id, :u64
        field :name, :string16
        field :description, :string16
        field :category, :string16
      end
    end

    test "generates chained offsets for consecutive string fields" do
      sql = SQL.generate(MultiStringCodec)

      assert sql =~ "decode_multistring"
      assert sql =~ ~s("name" text)
      assert sql =~ ~s("description" text)
      assert sql =~ ~s("category" text)

      lines = String.split(sql, "\n")

      name_line = Enum.find(lines, &String.contains?(&1, "AS \"name\""))
      desc_line = Enum.find(lines, &String.contains?(&1, "AS \"description\""))
      cat_line = Enum.find(lines, &String.contains?(&1, "AS \"category\""))

      assert name_line != nil
      assert desc_line != nil
      assert cat_line != nil

      refute desc_line == name_line
      refute cat_line == desc_line
    end

    test "each var field offset depends on previous field length" do
      sql = SQL.generate(MultiStringCodec)

      assert sql =~ "read_u16(data,"
      assert sql =~ "+ 2 + gridcodec.read_u16"
    end
  end

  describe "generate/1 with fixed repeating groups" do
    test "adds jsonb columns for inline, typed, and scalar groups" do
      sql = SQL.generate(SQLGroupsEvent)

      assert sql =~ ~s("signals" jsonb)
      assert sql =~ ~s("history" jsonb)
      assert sql =~ ~s("codes" jsonb)
      assert sql =~ "COALESCE((SELECT jsonb_agg("
      assert sql =~ "ORDER BY entry_index) FROM generate_series"
      assert sql =~ "'[]'::jsonb)"
    end

    test "decodes known group entry fields at offsets within each wire-sized entry" do
      sql = SQL.generate(SQLGroupsEvent)

      assert sql =~ "gridcodec.read_char_array(data,"
      assert sql =~ "gridcodec.read_i32(data,"
      assert sql =~ "gridcodec.read_uuid_nullable(data,"
      assert sql =~ "'symbol'"
      assert sql =~ "'score'"
      assert sql =~ "'related_id'"
    end

    test "walks multiple groups using wire block lengths and counts before var-data" do
      sql = SQL.generate(SQLGroupsEvent)

      assert sql =~ "8 + gridcodec.read_u16(data, 0)"

      assert sql =~
               "4 + gridcodec.read_u16(data, (8 + gridcodec.read_u16(data, 0))) * " <>
                 "gridcodec.read_u16(data, (8 + gridcodec.read_u16(data, 0)) + 2)"

      reason_line =
        sql
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, ~s(AS "reason")))

      assert reason_line =~ "gridcodec.read_u16(data, 0)"
      assert length(Regex.scan(~r/gridcodec\.read_u16/, reason_line)) >= 7
    end

    test "uses each preceding var field length after the group-derived start" do
      sql = SQL.generate(SQLGroupsEvent)

      detail_line =
        sql
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, ~s(AS "detail")))

      assert detail_line =~ "+ 2 + gridcodec.read_u16"
    end

    test "rejects framed groups before a variable tail" do
      module = Module.concat(__MODULE__, "FramedGroup#{System.unique_integer([:positive])}")

      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use GridCodec.Struct, template_id: 623, schema_id: 62

            defcodec do
              field :event_id, :u64
              group :entries, of: :string16
              field :tail, :string16
            end
          end
        end
      )

      try do
        assert_raise ArgumentError,
                     ~r/cannot generate PostgreSQL SQL.*length-prefixed group :entries.*variable-length field :tail/s,
                     fn ->
                       SQL.generate(module)
                     end

        generated_all = SQL.generate_all([module])
        assert generated_all =~ "-- Skipped #{inspect(module)}:"
        refute generated_all =~ "WHEN type_name = '#{module.__type__()}'"
      after
        :code.purge(module)
        :code.delete(module)
      end
    end

    test "rejects framed-only codecs instead of generating empty SQL" do
      module = Module.concat(__MODULE__, "FramedOnlyGroup#{System.unique_integer([:positive])}")

      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use GridCodec.Struct, template_id: 626, schema_id: 62

            defcodec do
              group :entries, of: :string16
            end
          end
        end
      )

      try do
        assert_raise ArgumentError,
                     ~r/cannot generate PostgreSQL SQL.*length-prefixed group :entries/s,
                     fn -> SQL.generate(module) end

        generated_all = SQL.generate_all([module])
        assert generated_all =~ "-- Skipped #{inspect(module)}:"
        refute generated_all =~ "RETURNS TABLE (\n  \n)"
        refute generated_all =~ "WHEN type_name = '#{module.__type__()}'"
      after
        :code.purge(module)
        :code.delete(module)
      end
    end

    test "preserves scaled decimal and wide-enum semantics in inline and typed groups" do
      suffix = System.unique_integer([:positive])
      wide_enum = Module.concat(__MODULE__, "WideStatus#{suffix}")
      entry = Module.concat(__MODULE__, "NumericEntry#{suffix}")
      event = Module.concat(__MODULE__, "NumericGroups#{suffix}")

      Code.compile_quoted(
        quote do
          defmodule unquote(wide_enum) do
            use GridCodec.Types.Enum, encoding: :u16

            defenum do
              value(:pending, 1)
              value(:review, 300)
            end
          end

          defmodule unquote(entry) do
            use GridCodec.Struct, template_id: 624, schema_id: 62

            defcodec do
              field :status, unquote(wide_enum)
              field :amount, {:decimal, scale: 2}, wire_format: :i64
              field :positive_amount, {:positive_decimal, scale: 2}, wire_format: :u64
            end
          end

          defmodule unquote(event) do
            use GridCodec.Struct, template_id: 625, schema_id: 62

            defcodec do
              field :event_id, :u64

              group :inline_values do
                field :status, unquote(wide_enum)
                field :amount, {:decimal, scale: 2}, wire_format: :i64
                field :positive_amount, {:positive_decimal, scale: 2}, wire_format: :u64
              end

              group :typed_values, of: unquote(entry)
            end
          end
        end
      )

      try do
        sql = SQL.generate(event)

        enum_table = wide_enum |> Module.split() |> List.last() |> Macro.underscore()

        assert sql =~ "CREATE TABLE IF NOT EXISTS gridcodec_enums.#{enum_table}"
        assert sql =~ "id integer PRIMARY KEY"
        assert sql =~ "gridcodec.read_u16(data,"
        refute sql =~ "e.id = get_byte(data,"

        assert sql =~ "gridcodec.read_i64(data,"
        assert sql =~ "gridcodec.read_u64(data,"
        assert sql =~ "power(10::numeric, -2)"
        assert sql =~ "= -9223372036854775808 THEN NULL"
        assert sql =~ "= 18446744073709551615 THEN NULL"
        refute sql =~ "gridcodec.read_decimal(data,"
      after
        for module <- [event, entry, wide_enum] do
          :code.purge(module)
          :code.delete(module)
        end
      end
    end
  end

  describe "generate/1 universal JSONB decoder" do
    test "generate_all includes universal decode function" do
      sql = SQL.generate_all([GridCodec.TestSupport.OrderEvent])

      assert sql =~ "gridcodec.decode(type_name text, data bytea)"
      assert sql =~ "RETURNS jsonb"
      assert sql =~ "WHEN type_name = 'OrderEvent'"
    end

    test "generates per-codec JSON helper functions" do
      sql = SQL.generate_all([GridCodec.TestSupport.OrderEvent])

      assert sql =~ "gridcodec.decode_orderevent_json(data bytea)"
      assert sql =~ "jsonb_build_object"
    end

    test "JSON function includes all field names as keys" do
      sql = SQL.generate_all([GridCodec.TestSupport.OrderEvent])

      assert sql =~ "'order_id'"
      assert sql =~ "'side'"
      assert sql =~ "'status'"
      assert sql =~ "'price'"
      assert sql =~ "'quantity'"
      assert sql =~ "'timestamp'"
    end

    test "unknown type returns error object" do
      sql = SQL.generate_all([GridCodec.TestSupport.OrderEvent])

      assert sql =~ "unknown type"
    end

    test "includes fixed groups as ordered JSON arrays" do
      sql = SQL.generate_all([SQLGroupsEvent])

      assert sql =~ "gridcodec.decode_sqlgroupsevent_json(data bytea)"
      assert sql =~ "'signals', COALESCE((SELECT jsonb_agg("
      assert sql =~ "'history', COALESCE((SELECT jsonb_agg("
      assert sql =~ "'codes', COALESCE((SELECT jsonb_agg("
      assert sql =~ "ORDER BY entry_index) FROM generate_series"
      assert sql =~ "'[]'::jsonb)"
    end
  end

  describe "generate_stream_decoder/1" do
    test "generates an index-friendly set-returning stream decoder" do
      sql =
        SQL.generate_stream_decoder(
          function: "risk.decode_user_stream",
          table: "risk.recorded_events",
          stream_id_type: :uuid,
          stream_id_column: :stream_uuid
        )

      assert sql =~
               ~s|CREATE OR REPLACE FUNCTION "risk"."decode_user_stream"(target_stream_id uuid, start_version bigint DEFAULT 1, max_count integer DEFAULT NULL)|

      assert sql =~ "RETURNS TABLE (stream_version bigint, event_type text, decoded jsonb)"
      assert sql =~ ~s(FROM "risk"."recorded_events" AS events)
      assert sql =~ ~s(events."stream_uuid" = target_stream_id)
      assert sql =~ ~s(events."stream_version" >= start_version)
      assert sql =~ ~s(ORDER BY events."stream_version")
      assert sql =~ "LIMIT max_count;"

      assert sql =~
               ~s|gridcodec.decode(events."event_type"::text, events."data") AS decoded|

      refute sql =~ ~s(events."stream_uuid"::text)
      assert sql =~ "LANGUAGE sql STABLE ROWS 1000"
    end

    test "can return raw indexed stream data without JSONB materialization" do
      sql =
        SQL.generate_stream_decoder(
          function: "risk.read_user_stream",
          table: "risk.recorded_events",
          stream_id_type: :uuid,
          stream_id_column: :stream_uuid,
          decode: :raw
        )

      assert sql =~ "RETURNS TABLE (stream_version bigint, event_type text, data bytea)"
      assert sql =~ ~s(events."data" AS data)
      refute sql =~ "gridcodec.decode("
    end

    test "can project selected fixed fields without building JSONB" do
      sql =
        SQL.generate_stream_decoder(
          function: "public.read_order_stream",
          table: "public.events",
          decode: {:fields, GridCodec.TestSupport.OrderEvent, [:side, :price, :quantity]}
        )

      assert sql =~
               ~s|RETURNS TABLE (stream_version bigint, event_type text, "side" text, "price" numeric, "quantity" bigint)|

      assert sql =~ "gridcodec.read_orderevent_side(events.\"data\") AS \"side\""
      assert sql =~ "gridcodec.read_orderevent_price(events.\"data\") AS \"price\""
      assert sql =~ "events.\"event_type\" = 'OrderEvent'"
      refute sql =~ "gridcodec.decode("
    end

    test "can decode every top-level field into native columns in one set-based query" do
      sql =
        SQL.generate_stream_decoder(
          function: "public.read_typed_order_stream",
          table: "public.events",
          decode: {:typed, GridCodec.TestSupport.OrderEvent}
        )

      assert sql =~
               ~s|RETURNS TABLE (stream_version bigint, event_type text, "order_id" uuid, "side" text, "status" text, "price" numeric, "quantity" bigint, "timestamp" timestamptz)|

      assert sql =~ ~s|gridcodec.read_uuid_nullable(events."data", 8) AS "order_id"|
      assert sql =~ ~s|gridcodec.read_u32(events."data",|
      assert sql =~ "events.\"event_type\" = 'OrderEvent'"
      refute sql =~ "gridcodec.read_orderevent_"
      refute sql =~ "gridcodec.decode("
      refute sql =~ "jsonb"

      variable_sql =
        SQL.generate_stream_decoder(
          function: "public.read_typed_variable_stream",
          table: "public.events",
          decode: {:typed, GridCodec.TestSupport.OrderEventVar}
        )

      assert variable_sql =~ ~s|gridcodec.read_string16(events."data",|
      assert variable_sql =~ ~s|gridcodec.read_u16(events."data", 0)|
    end

    test "rejects native typed projection for codecs with repeating groups" do
      assert_raise ArgumentError, ~r/repeating groups/, fn ->
        SQL.generate_stream_decoder(
          function: "public.read_grouped_stream",
          table: "public.events",
          decode: {:typed, SQLGroupsEvent}
        )
      end
    end

    test "rejects direct projections of variable and unknown fields" do
      assert_raise ArgumentError, ~r/fixed fields/, fn ->
        SQL.generate_stream_decoder(
          function: "public.read_strings",
          table: "public.events",
          decode: {:fields, GridCodec.SQLTest.MultiStringCodec, [:name]}
        )
      end

      assert_raise ArgumentError, ~r/unknown field/, fn ->
        SQL.generate_stream_decoder(
          function: "public.read_orders",
          table: "public.events",
          decode: {:fields, GridCodec.TestSupport.OrderEvent, [:missing]}
        )
      end
    end

    test "supports common envelope column names and stream id types" do
      sql =
        SQL.generate_stream_decoder(
          function: "public.decode_account_events",
          table: "public.account_events",
          stream_id_type: :bigint,
          stream_id_column: :account_id,
          stream_version_column: :position,
          event_type_column: :type,
          data_column: :payload
        )

      assert sql =~ "target_stream_id bigint"
      assert sql =~ ~s(events."account_id" = target_stream_id)
      assert sql =~ ~s(events."position"::bigint AS stream_version)
      assert sql =~ ~s(events."type"::text AS event_type)
      assert sql =~ ~s|gridcodec.decode(events."type"::text, events."payload")|
    end

    test "filters mixed types while keeping the raw or JSONB payload shape" do
      raw_sql =
        SQL.generate_stream_decoder(
          function: "risk.read_mixed_stream",
          table: "risk.recorded_events",
          stream_id_type: :uuid,
          decode: {:raw, [GridCodec.TestSupport.OrderEvent, GridCodec.TestSupport.OrderEventVar]}
        )

      assert raw_sql =~ "RETURNS TABLE (stream_version bigint, event_type text, data bytea)"
      assert raw_sql =~ ~s(events."data" AS data)

      assert raw_sql =~
               ~s|events."event_type" IN ('OrderEvent', 'OrderEventVar')|

      refute raw_sql =~ "gridcodec.decode("

      jsonb_sql =
        SQL.generate_stream_decoder(
          function: "risk.decode_mixed_stream",
          table: "risk.recorded_events",
          decode:
            {:jsonb, [GridCodec.TestSupport.OrderEvent, GridCodec.TestSupport.OrderEventVar]}
        )

      assert jsonb_sql =~ "RETURNS TABLE (stream_version bigint, event_type text, decoded jsonb)"
      assert jsonb_sql =~ ~s|events."event_type" IN ('OrderEvent', 'OrderEventVar')|
      assert jsonb_sql =~ "gridcodec.decode("
    end

    test "can filter mixed types by schema and template identity columns" do
      sql =
        SQL.generate_stream_decoder(
          function: "risk.read_mixed_stream",
          table: "risk.recorded_events",
          schema_id_column: :schema_id,
          event_type_id_column: :event_type_id,
          decode: {:raw, [GridCodec.TestSupport.OrderEvent, GridCodec.TestSupport.OrderEventVar]}
        )

      assert sql =~
               ~s|(events."schema_id", events."event_type_id") IN ((60, 600), (60, 602))|

      refute sql =~ ~s(events."event_type" IN)
    end

    test "treats a single-item typed list as the existing native projection" do
      sql =
        SQL.generate_stream_decoder(
          function: "public.read_typed_order_stream",
          table: "public.events",
          decode: {:typed, [GridCodec.TestSupport.OrderEvent]}
        )

      assert sql =~ ~s("order_id" uuid)
      assert sql =~ "events.\"event_type\" = 'OrderEvent'"
    end

    test "rejects mixed native typed projections" do
      assert_raise ArgumentError, ~r/native columns are per-type/, fn ->
        SQL.generate_stream_decoder(
          function: "public.read_typed_mixed_stream",
          table: "public.events",
          decode:
            {:typed, [GridCodec.TestSupport.OrderEvent, GridCodec.TestSupport.OrderEventVar]}
        )
      end
    end

    test "rejects an empty mixed-type codec list" do
      assert_raise ArgumentError, ~r/codec list cannot be empty/, fn ->
        SQL.generate_stream_decoder(
          function: "public.read_mixed_stream",
          table: "public.events",
          decode: {:raw, []}
        )
      end
    end

    test "rejects identity columns unless both are set" do
      assert_raise ArgumentError, ~r/must be set together/, fn ->
        SQL.generate_stream_decoder(
          function: "public.read_mixed_stream",
          table: "public.events",
          schema_id_column: :schema_id,
          decode: {:raw, [GridCodec.TestSupport.OrderEvent]}
        )
      end
    end

    test "generates an unfiltered stream-version companion function" do
      sql =
        SQL.generate_stream_version(
          function: "risk.read_user_stream_version",
          table: "risk.recorded_events",
          stream_id_type: :uuid,
          stream_id_column: :stream_uuid
        )

      assert sql =~
               ~s|CREATE OR REPLACE FUNCTION "risk"."read_user_stream_version"(target_stream_id uuid)|

      assert sql =~ "RETURNS bigint"
      assert sql =~ ~s|COALESCE(MAX(events."stream_version"), 0)::bigint|
      assert sql =~ ~s(FROM "risk"."recorded_events" AS events)
      assert sql =~ ~s(events."stream_uuid" = target_stream_id)
      refute sql =~ "event_type"
    end

    test "generates an idempotent drop for a consumer-owned stream decoder" do
      drop =
        SQL.drop_stream_decoder_statement(
          function: "risk.read_typed_stream",
          stream_id_type: :uuid
        )

      assert drop =~ "DO $gridcodec$"
      assert drop =~ ~s|DROP FUNCTION IF EXISTS "risk"."read_typed_stream"(uuid)|
      assert drop =~ ~s|DROP FUNCTION IF EXISTS "risk"."read_typed_stream"(uuid, bigint, integer)|

      assert SQL.drop_stream_version_statement(
               function: "risk.read_user_stream_version",
               stream_id_type: :uuid
             ) ==
               ~s|DROP FUNCTION IF EXISTS "risk"."read_user_stream_version"(uuid);|
    end

    test "rejects unsafe identifiers and unsupported stream id types" do
      assert_raise ArgumentError, ~r/invalid SQL identifier/, fn ->
        SQL.generate_stream_decoder(
          function: "risk.decode_stream; DROP TABLE users",
          table: "risk.events"
        )
      end

      assert_raise ArgumentError, ~r/unsupported stream_id_type/, fn ->
        SQL.generate_stream_decoder(
          function: "risk.decode_stream",
          table: "risk.events",
          stream_id_type: "uuid); DROP TABLE users; --"
        )
      end
    end
  end

  @generate_all_sql SQL.generate_all()

  describe "generate_all/0" do
    test "includes helpers and at least one codec" do
      assert @generate_all_sql =~ "CREATE SCHEMA IF NOT EXISTS gridcodec;"
      assert @generate_all_sql =~ "gridcodec.read_header"
      assert @generate_all_sql =~ "gridcodec.decode_"
    end
  end

  describe "generate_drop_all/1" do
    test "drops shape-dependent catalog functions before a migration refresh" do
      sql = SQL.generate_drop_all([GridCodec.TestSupport.OrderEvent])

      assert sql =~ "CREATE SCHEMA IF NOT EXISTS gridcodec"
      assert sql =~ "DROP FUNCTION IF EXISTS gridcodec.decode(text, bytea)"
      assert sql =~ "DROP FUNCTION IF EXISTS gridcodec.decode_orderevent(bytea)"
      assert sql =~ "DROP FUNCTION IF EXISTS gridcodec.decode_orderevent_json(bytea)"
      assert sql =~ "DROP FUNCTION IF EXISTS gridcodec.read_orderevent_price(bytea)"
      assert sql =~ "DROP FUNCTION IF EXISTS gridcodec.read_orderevent_quantity(bytea)"
    end

    test "returns individually executable drop and install statements" do
      drops = SQL.drop_statements([GridCodec.TestSupport.OrderEvent])
      installs = SQL.generate_all_statements([GridCodec.TestSupport.OrderEvent])

      assert "DROP FUNCTION IF EXISTS gridcodec.decode_orderevent(bytea);" in drops

      assert Enum.any?(installs, fn statement ->
               statement =~
                 "CREATE OR REPLACE FUNCTION gridcodec.read_orderevent_quantity(data bytea)"
             end)

      assert Enum.any?(installs, &String.contains?(&1, "PARALLEL SAFE"))
      assert Enum.all?(installs, &String.ends_with?(&1, ";"))
    end

    test "does not split semicolons inside comments, literals, or function bodies" do
      sql = """
      -- comment with a semicolon;
      CREATE OR REPLACE FUNCTION gridcodec.example(data text)
      RETURNS text AS $body$
        SELECT 'value;still-in-body' || data;
      $body$ LANGUAGE sql IMMUTABLE STRICT;
      INSERT INTO example_values (name) VALUES ('literal;value');
      """

      assert [function, insert] = SQL.split_statements(sql)
      assert function =~ "comment with a semicolon;"
      assert function =~ "'value;still-in-body'"
      assert insert == "INSERT INTO example_values (name) VALUES ('literal;value');"
    end
  end

  describe "generate_all_to_file/1" do
    test "writes SQL to file" do
      path =
        Path.join(System.tmp_dir!(), "gridcodec_test_#{System.unique_integer([:positive])}.sql")

      try do
        assert {:ok, ^path} = SQL.generate_all_to_file(path)
        assert File.exists?(path)

        content = File.read!(path)
        assert content =~ "CREATE SCHEMA IF NOT EXISTS gridcodec;"
        assert content =~ "gridcodec.decode_"
      after
        File.rm(path)
      end
    end
  end
end
