defmodule GridCodec.SQL.PLRust do
  @moduledoc """
  Generates an optional PL/Rust Trusted Language Extension accelerator.

  The accelerator contains bounds-checked native integer readers for PostgreSQL
  13 through 17 installations that provide both `pg_tle` and `plrust`. The
  regular `GridCodec.SQL` output remains the portable fallback, including for
  PostgreSQL 18 where Amazon RDS no longer supports PL/Rust.
  """

  @extension_name "gridcodec_plrust"
  @version "0.1.0"

  @doc "Returns the current optional accelerator extension version."
  def version, do: @version

  @doc """
  Generates the PL/Rust function definitions without pg_tle packaging.

  This form is useful for local verification on a PostgreSQL instance with the
  `plrust` language installed.
  """
  def generate_functions do
    """
    CREATE SCHEMA IF NOT EXISTS gridcodec_plrust;

    #{integer_reader("read_u8", "smallint", "i16", 1, "bytes[0] as i16")}
    #{integer_reader("read_u16",
    "integer",
    "i32",
    2,
    "u16::from_le_bytes([bytes[0], bytes[1]]) as i32")}
    #{integer_reader("read_u32",
    "bigint",
    "i64",
    4,
    "u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as i64")}
    #{integer_reader("read_i8", "smallint", "i16", 1, "i8::from_le_bytes([bytes[0]]) as i16")}
    #{integer_reader("read_i16",
    "integer",
    "i32",
    2,
    "i16::from_le_bytes([bytes[0], bytes[1]]) as i32")}
    #{integer_reader("read_i32",
    "bigint",
    "i64",
    4,
    "i32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as i64")}
    """
  end

  @doc """
  Packages the accelerator as a pg_tle extension.

  Installing the returned SQL registers `gridcodec_plrust`; consumers then run
  `CREATE EXTENSION gridcodec_plrust`. The database must preload and install
  both `pg_tle` and `plrust` first.
  """
  def generate_tle_install do
    """
    SELECT pgtle.install_extension(
      '#{@extension_name}',
      '#{@version}',
      'Native GridCodec fixed-width readers implemented with PL/Rust',
    $_gridcodec_tle_$
    #{generate_functions()}
    $_gridcodec_tle_$,
      ARRAY['plrust']
    );

    SELECT pgtle.set_default_version('#{@extension_name}', '#{@version}');
    """
  end

  defp integer_reader(name, sql_type, rust_type, width, decode_expression) do
    """
    CREATE OR REPLACE FUNCTION gridcodec_plrust.#{name}(data bytea, pos integer)
    RETURNS #{sql_type}
    LANGUAGE plrust
    IMMUTABLE STRICT PARALLEL SAFE
    AS $plrust$
      if pos < 0 {
        return Ok(None);
      }
      let start = pos as usize;
      let bytes = match data.get(start..start + #{width}) {
        Some(bytes) => bytes,
        None => return Ok(None),
      };
      let value: #{rust_type} = #{decode_expression};
      Ok(Some(value))
    $plrust$;
    """
  end
end
