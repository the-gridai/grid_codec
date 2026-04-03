defmodule Mix.Tasks.GridCodec.Export do
  @shortdoc "Generate .grid schema files from compiled GridCodec modules"
  @moduledoc """
  Generates `.grid` schema files from compiled `defcodec` modules.

  Scans all compiled GridCodec struct modules, groups them by `schema_id`,
  and writes a directory per schema containing a `schema.grid` master file
  plus individual files for each struct and enum.

  Only codecs that set an explicit schema namespace (`schema_id:` or `schema:`
  on `use GridCodec.Struct`) are exported. Structs that omit both still default
  to `schema_id: 0` on the wire but are skipped here so they can be used as
  encode/decode utilities without polluting generated schema trees.

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

  Exits with a non-zero status if any file is stale, missing, or unexpected.
  Intended for CI and pre-push hooks.

  ## Prune Mode

  Use `--prune` during generation to remove unexpected `.grid` files from the
  output directory, such as files left behind after deleting a source struct:

      mix grid_codec.export --prune
      mix grid_codec.export --output-dir priv/schemas --prune

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
    syntax: :integer,
    prune: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _} = OptionParser.parse(args, switches: @switches)

    Mix.Task.run("compile", [])

    output_dir = Keyword.get(opts, :output_dir, "priv/schemas")
    schema_id_filter = Keyword.get(opts, :schema_id)
    check_mode = Keyword.get(opts, :check, false)
    prune_mode = Keyword.get(opts, :prune, false)
    fmt_opts = [syntax: resolve_syntax(opts)]

    all_codecs = collect_codecs()

    codecs =
      Enum.filter(all_codecs, fn {_mod, schema} -> schema[:grid_schema_export] == true end)

    if all_codecs == [] do
      Mix.shell().info("No GridCodec struct modules found.")
    else
      if codecs == [] do
        Mix.shell().info(
          "No codecs are marked for `.grid` export. " <>
            "Add `schema_id:` or `schema:` to `use GridCodec.Struct` for codecs that should appear in exported schemas."
        )
      else
        grouped =
          codecs
          |> maybe_filter_schema_id(schema_id_filter)
          |> Enum.group_by(fn {_mod, schema} -> schema.schema_id end)

        if grouped == %{} do
          Mix.shell().info("No codecs match the given schema_id filter.")
        else
          schema_names = load_schema_names()
          all_enums = Formatter.detect_all_enums(Map.values(grouped))
          all_custom_types = Formatter.detect_all_custom_types(Map.values(grouped))

          files =
            build_files(grouped, output_dir, schema_names, all_enums, all_custom_types, fmt_opts)

          if check_mode do
            check(files, output_dir)
          else
            write(files, output_dir, prune_mode)
          end
        end
      end
    end

    :ok
  end

  # ============================================================================
  # File generation
  # ============================================================================

  defp build_files(grouped, output_dir, schema_names, all_enums, all_custom_types, fmt_opts) do
    type_aliases =
      Formatter.build_type_aliases(
        List.flatten(Map.values(grouped)),
        all_enums,
        all_custom_types
      )

    enum_home = build_enum_home_map(grouped, schema_names)
    custom_type_home = build_custom_type_home_map(grouped, schema_names, all_custom_types)

    ctx = %{
      output_dir: output_dir,
      schema_names: schema_names,
      all_enums: all_enums,
      all_custom_types: all_custom_types,
      type_aliases: type_aliases,
      enum_home: enum_home,
      custom_type_home: custom_type_home,
      fmt_opts: fmt_opts
    }

    Enum.flat_map(grouped, fn {schema_id, entries} ->
      build_schema_files(schema_id, entries, ctx)
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

  defp build_custom_type_home_map(grouped, schema_names, all_custom_types) do
    default_map =
      grouped
      |> Enum.sort_by(fn {schema_id, _} -> schema_id end)
      |> Enum.flat_map(fn {schema_id, entries} ->
        dir_name = schema_dir_name(schema_id, schema_names)
        local_types = Formatter.detect_custom_types(entries)

        Enum.map(local_types, fn {mod, info} ->
          rel_path = name_to_relative_path(info.short_name)
          {mod, %{schema_id: schema_id, dir_name: dir_name, rel_path: rel_path}}
        end)
      end)
      |> Enum.reduce(%{}, fn {mod, info}, acc ->
        Map.put_new(acc, mod, info)
      end)

    apply_schema_affinity(default_map, all_custom_types, schema_names)
  end

  defp apply_schema_affinity(home_map, all_custom_types, schema_names) do
    name_to_id = Map.new(schema_names, fn {id, name} -> {name, id} end)

    Enum.reduce(all_custom_types, home_map, fn {mod, info}, acc ->
      affinity = get_in(info, [:params, :schema])

      if affinity do
        case Map.get(name_to_id, affinity) do
          nil ->
            acc

          schema_id ->
            dir_name = schema_dir_name(schema_id, schema_names)
            rel_path = name_to_relative_path(info.short_name)
            Map.put(acc, mod, %{schema_id: schema_id, dir_name: dir_name, rel_path: rel_path})
        end
      else
        acc
      end
    end)
  end

  defp build_schema_files(schema_id, entries, ctx) do
    %{
      output_dir: output_dir,
      schema_names: schema_names,
      all_enums: all_enums,
      all_custom_types: all_custom_types,
      type_aliases: type_aliases,
      enum_home: enum_home,
      custom_type_home: custom_type_home,
      fmt_opts: fmt_opts
    } = ctx

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

    local_custom_types =
      all_custom_types
      |> Enum.filter(fn {mod, _info} ->
        home = Map.get(custom_type_home, mod)
        home && home.schema_id == schema_id
      end)
      |> Map.new()

    struct_files =
      entries
      |> Enum.sort_by(fn {_mod, schema} -> Formatter.struct_name(schema) end)
      |> Enum.map(fn {_mod, schema} ->
        rel_path = type_to_relative_path(schema.type)
        struct_abs_dir = Path.dirname(Path.join(schema_dir, rel_path))

        enum_imports =
          struct_type_imports(schema, all_enums, enum_home, schema_id, schema_dir, struct_abs_dir)

        ct_imports =
          struct_custom_type_imports(
            schema,
            all_custom_types,
            custom_type_home,
            schema_id,
            schema_dir,
            struct_abs_dir
          )

        struct_opts = Keyword.merge(fmt_opts, imports: enum_imports ++ ct_imports)
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

    custom_type_files =
      local_custom_types
      |> Enum.sort_by(fn {_mod, info} -> info.short_name end)
      |> Enum.map(fn {_mod, info} ->
        rel_path = name_to_relative_path(info.short_name)
        content = Formatter.format_custom_type_file(info, fmt_opts)
        {Path.join(schema_dir, rel_path), content}
      end)

    all_local_files = struct_files ++ enum_files ++ custom_type_files

    cross_imports = cross_schema_imports(entries, all_enums, enum_home, schema_id, schema_dir)

    cross_ct_imports =
      cross_schema_custom_type_imports(
        entries,
        all_custom_types,
        custom_type_home,
        schema_id,
        schema_dir
      )

    import_paths =
      all_local_files
      |> Enum.map(fn {full_path, _} -> Path.relative_to(full_path, schema_dir) end)
      |> Kernel.++(cross_imports)
      |> Kernel.++(cross_ct_imports)
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

  defp struct_custom_type_imports(
         schema,
         all_custom_types,
         custom_type_home,
         schema_id,
         schema_dir,
         struct_abs_dir
       ) do
    Formatter.referenced_custom_types(schema, all_custom_types)
    |> Enum.map(fn mod ->
      home = Map.get(custom_type_home, mod)

      if home && home.schema_id == schema_id do
        ct_abs = Path.join(schema_dir, home.rel_path)
        Path.relative_to(ct_abs, struct_abs_dir)
      else
        if home do
          output_dir = Path.dirname(schema_dir)
          ct_abs = Path.join([output_dir, home.dir_name, home.rel_path])
          Path.relative_to(ct_abs, struct_abs_dir)
        end
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp cross_schema_custom_type_imports(
         entries,
         all_custom_types,
         custom_type_home,
         schema_id,
         schema_dir
       ) do
    output_dir = Path.dirname(schema_dir)

    entries
    |> Enum.flat_map(fn {_mod, schema} ->
      Formatter.referenced_custom_types(schema, all_custom_types)
    end)
    |> Enum.uniq()
    |> Enum.filter(fn mod ->
      home = Map.get(custom_type_home, mod)
      home && home.schema_id != schema_id
    end)
    |> Enum.map(fn mod ->
      home = Map.fetch!(custom_type_home, mod)
      ct_abs = Path.join([output_dir, home.dir_name, home.rel_path])
      Path.relative_to(ct_abs, schema_dir)
    end)
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

  defp write(files, output_dir, prune_mode) do
    Enum.each(files, fn {path, content} ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("Wrote #{path}")
    end)

    if prune_mode do
      prune_unexpected_files(files, output_dir)
    end

    struct_count = Enum.count(files, fn {p, _} -> not String.ends_with?(p, "schema.grid") end)
    Mix.shell().info("Exported #{struct_count} definition(s) in #{schema_count(files)} schema(s)")
  end

  defp check(files, output_dir) do
    stale =
      Enum.reduce(files, [], fn {path, expected}, acc ->
        case File.read(path) do
          {:ok, current} when current == expected -> acc
          {:ok, _stale} -> [{:stale, path} | acc]
          {:error, :enoent} -> [{:missing, path} | acc]
        end
      end)

    unexpected =
      output_dir
      |> unexpected_files(files)
      |> Enum.map(&{:unexpected, &1})

    issues = stale ++ unexpected

    if issues == [] do
      file_count = length(files)

      Mix.shell().info(
        "GridCodec .grid files are up to date (#{file_count} file(s) in #{schema_count(files)} schema(s))"
      )
    else
      Enum.each(Enum.reverse(issues), fn
        {:stale, path} ->
          Mix.shell().error("Out of date: #{path}")

        {:missing, path} ->
          Mix.shell().error("Missing: #{path}")

        {:unexpected, path} ->
          Mix.shell().error("Unexpected: #{path}")
      end)

      Mix.shell().error("\nRun `mix grid_codec.export` and commit the result.")

      exit({:shutdown, 1})
    end
  end

  defp schema_count(files) do
    files
    |> Enum.count(fn {p, _} -> Path.basename(p) == "schema.grid" end)
  end

  defp prune_unexpected_files(files, output_dir) do
    output_dir
    |> unexpected_files(files)
    |> Enum.each(fn path ->
      File.rm!(path)
      cleanup_empty_parent_dirs(Path.dirname(path), output_dir)
      Mix.shell().info("Removed #{path}")
    end)
  end

  defp unexpected_files(output_dir, files) do
    expected_paths = MapSet.new(Enum.map(files, fn {path, _content} -> path end))

    output_dir
    |> Path.join("**/*.grid")
    |> Path.wildcard()
    |> Enum.reject(&MapSet.member?(expected_paths, &1))
    |> Enum.sort()
  end

  defp cleanup_empty_parent_dirs(dir, output_dir) do
    cond do
      dir == output_dir ->
        :ok

      File.ls!(dir) == [] ->
        File.rmdir!(dir)
        cleanup_empty_parent_dirs(Path.dirname(dir), output_dir)

      true ->
        :ok
    end
  end

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
