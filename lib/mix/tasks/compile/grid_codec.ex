defmodule Mix.Tasks.Compile.GridCodec do
  @moduledoc """
  Mix compiler for GridCodec registry consolidation.

  This compiler runs after the Elixir compiler and:
  1. Scans all loaded modules for GridCodec struct codecs
  2. Collects {schema_id, template_id} => module mappings
  3. Validates no conflicts (duplicate schema_id + template_id)
  4. Generates a consolidated `GridCodec.Registry` module with pattern-match dispatch

  ## Usage

  Add to your `mix.exs`:

      def project do
        [
          # ... other options
          compilers: Mix.compilers() ++ [:grid_codec]
        ]
      end

  ## Generated Registry

  The compiler generates `_build/<env>/lib/grid_codec/ebin/Elixir.GridCodec.Registry.beam`
  with optimized pattern-match dispatch:

      defmodule GridCodec.Registry do
        def lookup(100, 1), do: {:ok, MyApp.Order}
        def lookup(100, 2), do: {:ok, MyApp.Trade}
        def lookup(_, _), do: {:error, :unknown_codec}

        def encode(%MyApp.Order{} = s, opts \\ []), do: MyApp.Order.encode(s, opts)
        def encode(%MyApp.Trade{} = s, opts \\ []), do: MyApp.Trade.encode(s, opts)
        # ...
      end
  """

  @behaviour Mix.Task.Compiler

  @impl true
  def run(_args) do
    config = Mix.Project.config()

    # The library project itself relies on the fallback registry during tests for
    # dynamically-defined codecs. Consolidation is a consumer-app feature.
    if config[:app] == :grid_codec do
      {:ok, []}
    else
      do_run(config)
    end
  end

  defp do_run(config) do
    consolidation_path = consolidation_path(config)

    # Ensure consolidation directory exists
    File.mkdir_p!(consolidation_path)

    # Collect all GridCodec struct modules
    codecs = collect_codecs()

    # Validate no conflicts
    case validate_codecs(codecs) do
      :ok ->
        if codecs == [] do
          {:ok, []}
        else
          registry_path = Path.join(consolidation_path, "Elixir.GridCodec.Registry.beam")

          if should_regenerate?(registry_path, codecs) do
            generate_registry(codecs, registry_path)
            Mix.shell().info("Generated GridCodec.Registry with #{length(codecs)} codec(s)")
          end

          {:ok, []}
        end

      {:error, %{id_conflicts: id_conflicts, type_conflicts: type_conflicts}} ->
        for {{schema_id, template_id}, modules} <- id_conflicts do
          Mix.shell().error("""
          GridCodec conflict: Multiple codecs with same {schema_id, template_id}
            schema_id: #{schema_id}
            template_id: #{template_id}
            modules: #{inspect(modules)}
          """)
        end

        for {type_name, modules} <- type_conflicts do
          Mix.shell().error("""
          GridCodec conflict: Multiple codecs with same type name
            type_name: #{inspect(type_name)}
            modules: #{inspect(modules)}
            hint: Use the :name option to assign unique type names.
          """)
        end

        {:error, []}
    end
  end

  @impl true
  def manifests do
    [manifest_path()]
  end

  @impl true
  def clean do
    config = Mix.Project.config()
    consolidation_path = consolidation_path(config)
    registry_path = Path.join(consolidation_path, "Elixir.GridCodec.Registry.beam")

    File.rm(registry_path)
    File.rm(manifest_path())
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp consolidation_path(_config) do
    Path.join([Mix.Project.build_path(), "lib", "grid_codec", "ebin"])
  end

  defp manifest_path do
    Path.join(Mix.Project.manifest_path(), "compile.grid_codec")
  end

  defp collect_codecs do
    build_path = Mix.Project.build_path()

    # Scan all ebin directories for beam files, then check for GridCodec structs.
    # This is reliable regardless of BEAM's lazy module loading —
    # :code.all_loaded() may miss modules that haven't been referenced yet.
    Path.wildcard(Path.join([build_path, "lib", "*", "ebin", "*.beam"]))
    |> Enum.map(fn path ->
      path
      |> Path.basename(".beam")
      |> String.to_atom()
    end)
    |> Enum.filter(&is_gridcodec_struct?/1)
    |> Enum.map(fn mod ->
      %{
        module: mod,
        schema_id: mod.__schema_id__(),
        template_id: mod.__template_id__()
      }
    end)
    |> Enum.sort_by(fn %{schema_id: s, template_id: t} -> {s, t} end)
  end

  defp is_gridcodec_struct?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__gridcodec_struct__?, 0) and
      function_exported?(module, :__template_id__, 0) and
      function_exported?(module, :__schema_id__, 0)
  end

  @doc false
  def validate_codecs(codecs) do
    id_conflicts =
      codecs
      |> Enum.group_by(fn %{schema_id: s, template_id: t} -> {s, t} end)
      |> Enum.filter(fn {_key, mods} -> length(mods) > 1 end)
      |> Enum.map(fn {key, mods} -> {key, Enum.map(mods, & &1.module)} end)

    type_conflicts =
      codecs
      |> Enum.flat_map(fn %{module: mod} ->
        if Code.ensure_loaded?(mod) and function_exported?(mod, :__type__, 0) do
          [{mod.__type__(), mod}]
        else
          []
        end
      end)
      |> Enum.group_by(fn {type_name, _mod} -> type_name end, fn {_type_name, mod} -> mod end)
      |> Enum.filter(fn {_type_name, mods} -> length(mods) > 1 end)
      |> Enum.sort_by(fn {type_name, _mods} -> type_name end)

    if id_conflicts == [] and type_conflicts == [] do
      :ok
    else
      {:error, %{id_conflicts: id_conflicts, type_conflicts: type_conflicts}}
    end
  end

  defp should_regenerate?(registry_path, codecs) do
    if File.exists?(registry_path) do
      # Check if any codec module was recompiled more recently
      {:ok, %{mtime: registry_mtime}} = File.stat(registry_path)

      Enum.any?(codecs, fn %{module: mod} ->
        case :code.get_object_code(mod) do
          {^mod, _binary, beam_path} when is_list(beam_path) ->
            case File.stat(List.to_string(beam_path)) do
              {:ok, %{mtime: mod_mtime}} -> mod_mtime > registry_mtime
              _ -> true
            end

          _ ->
            true
        end
      end)
    else
      true
    end
  end

  defp generate_registry(codecs, output_path) do
    # Build the module AST
    module_ast = build_registry_ast(codecs)

    # Compile and write the beam file
    unload_compiled_module(GridCodec.Registry)
    [{GridCodec.Registry, binary}] = compile_generated_registry(module_ast)
    File.write!(output_path, binary)

    # Update manifest
    manifest = %{
      codecs: Enum.map(codecs, & &1.module),
      generated_at: DateTime.utc_now()
    }

    File.write!(manifest_path(), :erlang.term_to_binary(manifest))
  end

  defp compile_generated_registry(module_ast) do
    old_options = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Code.compile_quoted(module_ast)
    after
      Code.compiler_options(old_options)
    end
  end

  defp unload_compiled_module(module) do
    if Code.ensure_loaded?(module) do
      :code.purge(module)
      :code.delete(module)
    end

    :ok
  rescue
    _ -> :ok
  end

  @doc false
  def build_registry_ast(codecs, module_name \\ GridCodec.Registry) do
    # Generate lookup/2 clauses
    lookup_clauses =
      Enum.map(codecs, fn %{module: mod, schema_id: sid, template_id: tid} ->
        quote do
          def lookup(unquote(sid), unquote(tid)), do: {:ok, unquote(mod)}
        end
      end)

    lookup_fallback =
      quote do
        def lookup(_, _), do: {:error, :unknown_codec}
      end

    # Generate encode/2 clauses for each struct type
    encode_clauses =
      Enum.map(codecs, fn %{module: mod} ->
        quote do
          def encode(%{__struct__: unquote(mod)} = struct, opts),
            do: unquote(mod).encode(struct, opts)
        end
      end)

    encode_fallback =
      quote do
        def encode(struct, _opts) do
          raise ArgumentError,
                "Cannot encode #{inspect(struct.__struct__)} - not a registered GridCodec struct"
        end
      end

    # Generate decode/1 that parses header and dispatches
    decode_body = build_decode_body(codecs)

    # Generate list_codecs/0
    codec_modules = Enum.map(codecs, & &1.module)

    # Build type name -> module map for lookup_by_type/1
    type_map =
      codecs
      |> Enum.filter(fn %{module: mod} -> function_exported?(mod, :__type__, 0) end)
      |> Enum.map(fn %{module: mod} -> {mod.__type__(), mod} end)
      |> Map.new()

    quote do
      defmodule unquote(module_name) do
        @moduledoc """
        Auto-generated GridCodec registry.

        This module is generated by the `:grid_codec` Mix compiler
        and provides optimized dispatch for encoding/decoding.

        Do not edit this file manually - it will be regenerated.
        """

        @doc "Look up a codec module by schema_id and template_id"
        unquote_splicing(lookup_clauses)
        unquote(lookup_fallback)

        @doc "Look up a codec module by its type name"
        def lookup_by_type(type_name) when is_binary(type_name) do
          case unquote(Macro.escape(type_map)) do
            %{^type_name => module} -> {:ok, module}
            _ -> {:error, :unknown_type}
          end
        end

        @doc "Encode a struct to binary (with header by default)"
        def encode(struct, opts \\ [])
        unquote_splicing(encode_clauses)
        unquote(encode_fallback)

        @doc "Decode a binary, dispatching to the correct codec (expects header by default)"
        unquote(decode_body)

        @doc "List all registered codec modules"
        def list_codecs, do: unquote(codec_modules)

        @doc "Check if this is a consolidated registry"
        def consolidated?, do: true

        @doc "Clear cache (no-op for consolidated registry)"
        def clear_cache, do: :ok
      end
    end
  end

  defp build_decode_body(codecs) do
    all_clauses =
      Enum.map(codecs, fn %{module: mod, schema_id: sid, template_id: tid} ->
        pattern = {:{}, [], [sid, tid]}
        body = quote(do: unquote(mod).decode(payload, header: false))
        {:->, [], [[pattern], body]}
      end)

    fallback = {:->, [], [[{:_, [], nil}], {:error, :unknown_codec}]}
    all_clauses = all_clauses ++ [fallback]

    match_expr = quote(do: {header.schema_id, header.template_id})
    dispatch_case = {:case, [], [match_expr, [do: all_clauses]]}

    quote do
      def decode(binary, opts \\ [])

      def decode(binary, []) when is_binary(binary) do
        case GridCodec.Header.decode(binary) do
          {:ok, header, payload} ->
            unquote(dispatch_case)

          {:error, _} = error ->
            error
        end
      end

      def decode(binary, opts) when is_binary(binary) do
        if Keyword.get(opts, :header, true) do
          case GridCodec.Header.decode(binary) do
            {:ok, header, payload} ->
              unquote(dispatch_case)

            {:error, _} = error ->
              error
          end
        else
          case Keyword.fetch(opts, :module) do
            {:ok, module} ->
              module.decode(binary, header: false)

            :error ->
              {:error, :module_required_without_header}
          end
        end
      end
    end
  end
end
