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

  ## Check Mode

  Use `--check` to verify the file is up to date without writing:

      mix gridcodec.sql --check
      mix gridcodec.sql --check --output path/to/custom.sql

  Exits with a non-zero status if the file is stale or missing.
  Intended for CI and pre-push hooks.

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

    {opts, _, _} =
      OptionParser.parse(args, switches: [output: :string, check: :boolean])

    output_path = Keyword.get(opts, :output, "priv/gridcodec_functions.sql")

    if Keyword.get(opts, :check, false) do
      check(output_path)
    else
      generate(output_path)
    end
  end

  defp generate(output_path) do
    File.mkdir_p!(Path.dirname(output_path))
    {:ok, path} = GridCodec.SQL.generate_all_to_file(output_path)
    Mix.shell().info("Generated #{path} with #{codec_count()} codec(s)")
  end

  defp check(output_path) do
    expected = GridCodec.SQL.generate_all()

    case File.read(output_path) do
      {:ok, current} when current == expected ->
        Mix.shell().info("GridCodec SQL is up to date (#{codec_count()} codecs)")

      {:ok, _stale} ->
        Mix.shell().error("""
        GridCodec SQL is out of date: #{output_path}
        Run `mix gridcodec.sql` and commit the result.
        """)

        exit({:shutdown, 1})

      {:error, :enoent} ->
        Mix.shell().error("""
        GridCodec SQL file not found: #{output_path}
        Run `mix gridcodec.sql` to generate it.
        """)

        exit({:shutdown, 1})
    end
  end

  defp codec_count do
    :code.all_loaded()
    |> Enum.count(fn {mod, _} ->
      Code.ensure_loaded?(mod) and
        function_exported?(mod, :__gridcodec_struct__?, 0) and
        function_exported?(mod, :__field_specs__, 0)
    end)
  end
end
