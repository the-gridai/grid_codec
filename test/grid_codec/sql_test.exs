defmodule GridCodec.SQLTest do
  use ExUnit.Case, async: true

  alias GridCodec.SQL

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
      assert sql =~ "gridcodec.read_uuid"
      assert sql =~ "gridcodec.read_uuid_nullable"
      assert sql =~ "gridcodec.read_decimal"
      assert sql =~ "gridcodec.read_timestamp_us"
      assert sql =~ "gridcodec.read_bool"
      assert sql =~ "gridcodec.read_string16"
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

    test "uses enum lookup for enum fields" do
      assert @order_event_sql =~ "FROM gridcodec_enums.side e WHERE e.id = get_byte"
      assert @order_event_sql =~ "FROM gridcodec_enums.status e WHERE e.id = get_byte"
    end

    test "uses read_timestamp_us for timestamp fields" do
      assert @order_event_sql =~ "gridcodec.read_timestamp_us(data,"
    end

    test "null checks for u64 fields" do
      assert @order_event_sql =~ "18446744073709551615 THEN NULL"
    end

    test "null checks for u32 fields" do
      assert @order_event_sql =~ "4294967295 THEN NULL"
    end

    test "decode function is IMMUTABLE STRICT" do
      assert @order_event_sql =~ "LANGUAGE sql IMMUTABLE STRICT"
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
  end

  @generate_all_sql SQL.generate_all()

  describe "generate_all/0" do
    test "includes helpers and at least one codec" do
      assert @generate_all_sql =~ "CREATE SCHEMA IF NOT EXISTS gridcodec;"
      assert @generate_all_sql =~ "gridcodec.read_header"
      assert @generate_all_sql =~ "gridcodec.decode_"
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
