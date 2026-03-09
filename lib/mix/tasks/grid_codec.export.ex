defmodule Mix.Tasks.GridCodec.Export do
  @shortdoc "Generate .grid schema files from compiled GridCodec modules"
  @moduledoc """
  Generates `.grid` schema files from compiled `defcodec` modules.

  Scans all compiled GridCodec struct modules, groups them by `schema_id`,
  and writes one `.grid` file per schema.

  ## Usage

      # Export all schemas to priv/schemas/
      mix grid_codec.export

      # Custom output directory
      mix grid_codec.export --output-dir priv/schemas

      # Export only a specific schema_id
      mix grid_codec.export --schema-id 100

  ## Check Mode

  Use `--check` to verify `.grid` files are up to date without writing:

      mix grid_codec.export --check
      mix grid_codec.export --check --output-dir priv/schemas

  Exits with a non-zero status if any file is stale or missing.
  Intended for CI and pre-push hooks.

  ## Output

  Each schema produces a file named `{schema_name}.grid` (or `schema_{id}.grid`
  if no name is configured). The file contains all struct, enum, and group
  definitions in that schema.
  """

  use Mix.Task

  alias GridCodec.Schema.Formatter

  @switches [
    output_dir: :string,
    schema_id: :integer,
    check: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _} = OptionParser.parse(args, switches: @switches)

    Mix.Task.run("compile", [])

    output_dir = Keyword.get(opts, :output_dir, "priv/schemas")
    schema_id_filter = Keyword.get(opts, :schema_id)
    check_mode = Keyword.get(opts, :check, false)

    codecs = collect_codecs()

    if codecs == [] do
      Mix.shell().info("No GridCodec struct modules found.")
      return_ok()
    end

    grouped =
      codecs
      |> maybe_filter_schema_id(schema_id_filter)
      |> Enum.group_by(fn {_mod, schema} -> schema.schema_id end)

    if grouped == %{} do
      Mix.shell().info("No codecs match the given schema_id filter.")
      return_ok()
    end

    schemas = build_schemas(grouped, output_dir)

    if check_mode do
      check(schemas)
    else
      write(schemas)
    end
  end

  defp build_schemas(grouped, output_dir) do
    grouped
    |> Enum.map(fn {schema_id, entries} ->
      {schema_name, schema_version} = infer_schema_meta(entries)
      content = Formatter.format(schema_name, schema_id, schema_version, entries)
      filename = safe_filename(schema_name) <> ".grid"
      path = Path.join(output_dir, filename)
      {path, content, length(entries)}
    end)
    |> Map.new(fn {path, content, count} -> {path, {path, content, count}} end)
    |> Map.values()
    |> Enum.sort_by(fn {path, _, _} -> path end)
  end

  defp write(schemas) do
    Enum.each(schemas, fn {path, content, count} ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("Wrote #{path} (#{count} struct(s))")
    end)
  end

  defp check(schemas) do
    stale =
      Enum.reduce(schemas, [], fn {path, expected, _count}, acc ->
        case File.read(path) do
          {:ok, current} when current == expected -> acc
          {:ok, _stale} -> [{:stale, path} | acc]
          {:error, :enoent} -> [{:missing, path} | acc]
        end
      end)

    if stale == [] do
      total = Enum.reduce(schemas, 0, fn {_, _, c}, acc -> acc + c end)
      file_count = length(schemas)

      Mix.shell().info(
        "GridCodec .grid files are up to date (#{total} struct(s) in #{file_count} file(s))"
      )
    else
      Enum.each(Enum.reverse(stale), fn
        {:stale, path} ->
          Mix.shell().error("Out of date: #{path}")

        {:missing, path} ->
          Mix.shell().error("Missing: #{path}")
      end)

      Mix.shell().error("\nRun `mix grid_codec.export` and commit the result.")

      exit({:shutdown, 1})
    end
  end

  defp return_ok, do: :ok

  defp collect_codecs do
    build_path = Mix.Project.build_path()

    Path.wildcard(Path.join([build_path, "lib", "*", "ebin", "*.beam"]))
    |> Enum.map(fn path -> path |> Path.basename(".beam") |> String.to_atom() end)
    |> Enum.filter(&gridcodec_struct?/1)
    |> Enum.map(fn mod -> {mod, mod.__schema__()} end)
  end

  defp gridcodec_struct?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__gridcodec_struct__?, 0) and
      function_exported?(module, :__schema__, 0)
  end

  defp maybe_filter_schema_id(codecs, nil), do: codecs

  defp maybe_filter_schema_id(codecs, id) do
    Enum.filter(codecs, fn {_mod, schema} -> schema.schema_id == id end)
  end

  defp infer_schema_meta(entries) do
    versions = entries |> Enum.map(fn {_mod, s} -> s.version end) |> Enum.max()

    name =
      entries
      |> Enum.map(fn {mod, _s} -> mod |> Module.split() |> Enum.take(2) |> Enum.join(".") end)
      |> Enum.frequencies()
      |> Enum.max_by(fn {_name, count} -> count end)
      |> elem(0)
      |> String.replace(".", "")

    {name, versions}
  end

  defp safe_filename(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim_trailing("_")
  end
end
