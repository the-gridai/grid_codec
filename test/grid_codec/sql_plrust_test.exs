defmodule GridCodec.SQL.PLRustTest do
  use ExUnit.Case, async: true

  alias GridCodec.SQL.PLRust

  describe "generate_functions/0" do
    test "generates bounds-checked native readers for fixed-width integers" do
      sql = PLRust.generate_functions()

      assert sql =~ "CREATE SCHEMA IF NOT EXISTS gridcodec_plrust"
      assert sql =~ "gridcodec_plrust.read_u8(data bytea, pos integer)"
      assert sql =~ "gridcodec_plrust.read_u16(data bytea, pos integer)"
      assert sql =~ "gridcodec_plrust.read_u32(data bytea, pos integer)"
      assert sql =~ "gridcodec_plrust.read_i32(data bytea, pos integer)"
      assert sql =~ "u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])"
      assert sql =~ "data.get(start..start + 4)"
      assert sql =~ "LANGUAGE plrust"
      assert sql =~ "IMMUTABLE STRICT PARALLEL SAFE"
    end
  end

  describe "generate_tle_install/0" do
    test "packages the readers as a versioned pg_tle extension requiring plrust" do
      sql = PLRust.generate_tle_install()

      assert sql =~ "pgtle.install_extension("
      assert sql =~ "'gridcodec_plrust'"
      assert sql =~ "'#{PLRust.version()}'"
      assert sql =~ "ARRAY['plrust']"
      assert sql =~ "pgtle.set_default_version('gridcodec_plrust', '#{PLRust.version()}')"
      assert sql =~ "$_gridcodec_tle_$"
    end
  end
end
