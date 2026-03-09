defmodule Mix.Tasks.GridCodec.Export do
  @shortdoc "Generate .grid schema files from compiled GridCodec modules"
  @moduledoc """
  Generates `.grid` schema files from compiled `defcodec` modules.

  Scans all compiled GridCodec struct modules, groups them by `schema_id`,
  and writes a directory per schema containing a `schema.grid` master file
  plus individual files for each struct and enum.

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

  ## Output Structure

  Each schema_id gets a directory (named via application config or
  defaulting to `schema_{id}`). Inside:

      priv/schemas/
        events/
          schema.grid              # master — schema block + imports
          order_created.grid       # individual struct
          order_side.grid          # individual enum

  ## Configuration

  Configure schema directory names in your application config:

      config :my_app, :grid_codec,
        schemas: %{100 => "events", 99 => "bench"}

  Unconfigured schema_ids fall back to `schema_{id}`.
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

    schema_names = load_schema_names()
    files = build_files(grouped, output_dir, schema_names)

    if check_mode do
      check(files)
    else
      write(files)
    end
  end

  # ============================================================================
  # File generation
  # ============================================================================

  defp build_files(grouped, output_dir, schema_names) do
    Enum.flat_map(grouped, fn {schema_id, entries} ->
      build_schema_files(schema_id, entries, output_dir, schema_names)
    end)
    |> Enum.sort_by(fn {path, _content} -> path end)
  end

  defp build_schema_files(schema_id, entries, output_dir, schema_names) do
    dir_name = schema_dir_name(schema_id, schema_names)
    schema_dir = Path.join(output_dir, dir_name)
    schema_version = entries |> Enum.map(fn {_mod, s} -> s.version end) |> Enum.max()

    enums = Formatter.detect_enums(entries)
    type_aliases = Formatter.build_type_aliases(entries, enums)

    struct_files =
      entries
      |> Enum.sort_by(fn {_mod, schema} -> Formatter.struct_name(schema) end)
      |> Enum.map(fn {_mod, schema} ->
        rel_path = type_to_relative_path(schema.type)
        content = Formatter.format_struct_file(schema, type_aliases)
        {Path.join(schema_dir, rel_path), content}
      end)

    enum_files =
      enums
      |> Enum.sort_by(fn {_mod, info} -> info.short_name end)
      |> Enum.map(fn {_mod, info} ->
        rel_path = name_to_relative_path(info.short_name)
        content = Formatter.format_enum_file(info)
        {Path.join(schema_dir, rel_path), content}
      end)

    import_paths =
      (struct_files ++ enum_files)
      |> Enum.map(fn {full_path, _} -> Path.relative_to(full_path, schema_dir) end)
      |> Enum.sort()

    master_content =
      Formatter.format_master(dir_name, schema_id, schema_version, import_paths)

    master_file = {Path.join(schema_dir, "schema.grid"), master_content}

    [master_file | struct_files ++ enum_files]
  end

  # ============================================================================
  # Path derivation
  # ============================================================================

  @doc false
  def type_to_relative_path(type_name) when is_binary(type_name) do
    type_name
    |> String.split(".")
    |> Enum.map(&Macro.underscore/1)
    |> Path.join()
    |> Kernel.<>(".grid")
  end

  defp name_to_relative_path(short_name) when is_binary(short_name) do
    Macro.underscore(short_name) <> ".grid"
  end

  # ============================================================================
  # Config
  # ============================================================================

  defp load_schema_names do
    app = Mix.Project.config()[:app]
    config = Application.get_env(app, :grid_codec, [])
    Keyword.get(config, :schemas, %{})
  end

  defp schema_dir_name(schema_id, schema_names) do
    Map.get(schema_names, schema_id, "schema_#{schema_id}")
  end

  # ============================================================================
  # Write / Check
  # ============================================================================

  defp write(files) do
    Enum.each(files, fn {path, content} ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("Wrote #{path}")
    end)

    struct_count = Enum.count(files, fn {p, _} -> not String.ends_with?(p, "schema.grid") end)
    Mix.shell().info("Exported #{struct_count} definition(s) in #{schema_count(files)} schema(s)")
  end

  defp check(files) do
    stale =
      Enum.reduce(files, [], fn {path, expected}, acc ->
        case File.read(path) do
          {:ok, current} when current == expected -> acc
          {:ok, _stale} -> [{:stale, path} | acc]
          {:error, :enoent} -> [{:missing, path} | acc]
        end
      end)

    if stale == [] do
      file_count = length(files)

      Mix.shell().info(
        "GridCodec .grid files are up to date (#{file_count} file(s) in #{schema_count(files)} schema(s))"
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

  defp schema_count(files) do
    files
    |> Enum.count(fn {p, _} -> Path.basename(p) == "schema.grid" end)
  end

  defp return_ok, do: :ok

  # ============================================================================
  # Codec discovery
  # ============================================================================

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
end
