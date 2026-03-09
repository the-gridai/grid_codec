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

      # Target a specific .grid syntax version
      mix grid_codec.export --syntax 1

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
          order_created.grid       # individual struct (imports its type deps)
          order_side.grid          # individual enum

  Individual struct files import the types they reference, making each
  file self-contained. The master file imports everything.

  ## Configuration

  Configure schema directory names and syntax version in your
  application config:

      config :my_app, :grid_codec,
        schemas: %{100 => "events", 99 => "bench"},
        syntax: 1

  Unconfigured schema_ids fall back to `schema_{id}`.

  Syntax version precedence: `--syntax` flag > config > latest.
  """

  use Mix.Task

  alias GridCodec.Schema.Formatter

  @switches [
    output_dir: :string,
    schema_id: :integer,
    check: :boolean,
    syntax: :integer
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _} = OptionParser.parse(args, switches: @switches)

    Mix.Task.run("compile", [])

    output_dir = Keyword.get(opts, :output_dir, "priv/schemas")
    schema_id_filter = Keyword.get(opts, :schema_id)
    check_mode = Keyword.get(opts, :check, false)
    fmt_opts = [syntax: resolve_syntax(opts)]

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
    all_enums = Formatter.detect_all_enums(Map.values(grouped))
    files = build_files(grouped, output_dir, schema_names, all_enums, fmt_opts)

    if check_mode do
      check(files)
    else
      write(files)
    end
  end

  # ============================================================================
  # File generation
  # ============================================================================

  defp build_files(grouped, output_dir, schema_names, all_enums, fmt_opts) do
    type_aliases = Formatter.build_type_aliases(List.flatten(Map.values(grouped)), all_enums)

    enum_home = build_enum_home_map(grouped, schema_names)

    Enum.flat_map(grouped, fn {schema_id, entries} ->
      build_schema_files(
        schema_id,
        entries,
        output_dir,
        schema_names,
        all_enums,
        type_aliases,
        enum_home,
        fmt_opts
      )
    end)
    |> Enum.sort_by(fn {path, _content} -> path end)
  end

  defp build_enum_home_map(grouped, schema_names) do
    grouped
    |> Enum.sort_by(fn {schema_id, _} -> schema_id end)
    |> Enum.flat_map(fn {schema_id, entries} ->
      dir_name = schema_dir_name(schema_id, schema_names)
      local_enums = Formatter.detect_enums(entries)

      Enum.map(local_enums, fn {mod, info} ->
        rel_path = name_to_relative_path(info.short_name)
        {mod, %{schema_id: schema_id, dir_name: dir_name, rel_path: rel_path}}
      end)
    end)
    |> Enum.reduce(%{}, fn {mod, info}, acc ->
      Map.put_new(acc, mod, info)
    end)
  end

  defp build_schema_files(
         schema_id,
         entries,
         output_dir,
         schema_names,
         all_enums,
         type_aliases,
         enum_home,
         fmt_opts
       ) do
    dir_name = schema_dir_name(schema_id, schema_names)
    schema_dir = Path.join(output_dir, dir_name)
    schema_version = entries |> Enum.map(fn {_mod, s} -> s.version end) |> Enum.max()

    local_enums =
      all_enums
      |> Enum.filter(fn {mod, _info} ->
        home = Map.get(enum_home, mod)
        home && home.schema_id == schema_id
      end)
      |> Map.new()

    struct_files =
      entries
      |> Enum.sort_by(fn {_mod, schema} -> Formatter.struct_name(schema) end)
      |> Enum.map(fn {_mod, schema} ->
        rel_path = type_to_relative_path(schema.type)
        struct_abs_dir = Path.dirname(Path.join(schema_dir, rel_path))

        import_paths =
          struct_type_imports(schema, all_enums, enum_home, schema_id, schema_dir, struct_abs_dir)

        struct_opts = Keyword.merge(fmt_opts, imports: import_paths)
        content = Formatter.format_struct_file(schema, type_aliases, struct_opts)
        {Path.join(schema_dir, rel_path), content}
      end)

    enum_files =
      local_enums
      |> Enum.sort_by(fn {_mod, info} -> info.short_name end)
      |> Enum.map(fn {_mod, info} ->
        rel_path = name_to_relative_path(info.short_name)
        content = Formatter.format_enum_file(info, fmt_opts)
        {Path.join(schema_dir, rel_path), content}
      end)

    all_local_files = struct_files ++ enum_files

    cross_imports = cross_schema_imports(entries, all_enums, enum_home, schema_id, schema_dir)

    import_paths =
      all_local_files
      |> Enum.map(fn {full_path, _} -> Path.relative_to(full_path, schema_dir) end)
      |> Kernel.++(cross_imports)
      |> Enum.sort()

    master_content =
      Formatter.format_master(dir_name, schema_id, schema_version, import_paths, fmt_opts)

    master_file = {Path.join(schema_dir, "schema.grid"), master_content}

    [master_file | all_local_files]
  end

  defp struct_type_imports(schema, all_enums, enum_home, schema_id, schema_dir, struct_abs_dir) do
    Formatter.referenced_enums(schema, all_enums)
    |> Enum.map(fn mod ->
      home = Map.get(enum_home, mod)

      if home && home.schema_id == schema_id do
        enum_abs = Path.join(schema_dir, home.rel_path)
        Path.relative_to(enum_abs, struct_abs_dir)
      else
        if home do
          output_dir = Path.dirname(schema_dir)
          enum_abs = Path.join([output_dir, home.dir_name, home.rel_path])
          Path.relative_to(enum_abs, struct_abs_dir)
        end
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp cross_schema_imports(entries, all_enums, enum_home, schema_id, schema_dir) do
    output_dir = Path.dirname(schema_dir)

    entries
    |> Enum.flat_map(fn {_mod, schema} -> Formatter.referenced_enums(schema, all_enums) end)
    |> Enum.uniq()
    |> Enum.filter(fn mod ->
      home = Map.get(enum_home, mod)
      home && home.schema_id != schema_id
    end)
    |> Enum.map(fn mod ->
      home = Map.fetch!(enum_home, mod)
      enum_abs = Path.join([output_dir, home.dir_name, home.rel_path])
      Path.relative_to(enum_abs, schema_dir)
    end)
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

  defp resolve_syntax(opts) do
    if Keyword.has_key?(opts, :syntax) do
      Keyword.fetch!(opts, :syntax)
    else
      app = Mix.Project.config()[:app]
      config = Application.get_env(app, :grid_codec, [])
      Keyword.get(config, :syntax, Formatter.current_syntax())
    end
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
