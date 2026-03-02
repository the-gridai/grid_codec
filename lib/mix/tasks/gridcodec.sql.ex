defmodule Mix.Tasks.Gridcodec.Sql do
  @shortdoc "Generate PostgreSQL functions for decoding GridCodec bytea columns"
  @moduledoc """
  Generates a SQL file with PostgreSQL functions that decode GridCodec
  binaries stored as `bytea` columns.

  ## Usage

      mix gridcodec.sql

  By default writes to `priv/gridcodec_functions.sql`. Use `--output` to
  change the path:

      mix gridcodec.sql --output path/to/output.sql

  ## What It Generates

  - Schema `gridcodec` with shared helper functions (`read_u64`, `read_decimal`, etc.)
  - Schema `gridcodec_enums` with enum lookup tables
  - Per-codec decode functions: `gridcodec.decode_<type_name>(bytea)`
  - Header parser: `gridcodec.read_header(bytea)`

  ## Example

  After running the generated SQL against your database:

      SELECT (gridcodec.decode_ordercreated(data)).*
      FROM events
      WHERE event_type = 'OrderCreated'
      LIMIT 10;
  """

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("compile")

    {opts, _, _} = OptionParser.parse(args, switches: [output: :string])
    output_path = Keyword.get(opts, :output, "priv/gridcodec_functions.sql")

    File.mkdir_p!(Path.dirname(output_path))

    {:ok, path} = GridCodec.SQL.generate_all_to_file(output_path)

    codecs =
      :code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(fn mod ->
        Code.ensure_loaded?(mod) and
          function_exported?(mod, :__gridcodec_struct__?, 0) and
          function_exported?(mod, :__field_specs__, 0)
      end)

    Mix.shell().info("Generated #{path} with #{length(codecs)} codec(s)")
  end
end
