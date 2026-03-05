defmodule GridCodec.Match do
  @moduledoc """
  Compile-time matchspec-like binary filtering with native guards.

  Generates efficient predicate functions that extract fields at compile-time
  known offsets and evaluate guard expressions without full decode.

  ## Usage

      defmodule SpanFilters do
        use GridCodec.Match

        # Simple field check
        defmatch :sampled?, BinaryEnvelope do
          where flags == 1
        end

        # Bitwise guards (Bitwise is auto-imported)
        defmatch :trace_sampled?, BinaryEnvelope do
          where band(flags, 0x01) == 1
        end

        # Cross-field comparison
        defmatch :slow?, BinaryTraceContext do
          where end_time_ns - start_time_ns > 1_000_000_000
        end

        # Multiple conditions (ANDed)
        defmatch :sampled_server?, BinaryTraceContext do
          where band(flags, 1) == 1
          where kind == 3
        end

        # With field selection — returns extracted field values on match
        defmatch :extract_timing, BinaryTraceContext, select: [:trace_id, :start_time_ns] do
          where band(flags, 1) == 1
        end
      end

      SpanFilters.sampled?(binary)        #=> true | false
      SpanFilters.slow?(binary)           #=> true | false
      SpanFilters.extract_timing(binary)  #=> {:match, %{trace_id: ..., start_time_ns: ...}} | :no_match

  ## How it works

  At compile time, `defmatch` resolves field offsets from the codec module and
  generates a function that:

  1. Extracts only the referenced fields at their known binary offsets
  2. Evaluates the guard expression on the extracted values
  3. Returns `true`/`false` (or selected fields on match)

  No full decode is performed. Each field access is an O(1) sub-binary read.

  ## Guard-compatible types

  All integer types (`u8`–`u64`, `i8`–`i64`), floats (`f32`, `f64`),
  booleans, and timestamps work in guard expressions. Types that decode to
  structs or binaries (decimal, UUID, etc.) can be extracted in `select:`
  but cannot appear in `where` arithmetic/comparison guards.
  """

  defmacro __using__(_opts) do
    quote do
      import GridCodec.Match, only: [defmatch: 3, defmatch: 4]
      import Bitwise
    end
  end

  @doc """
  Marker macro for conditions inside `defmatch`. Only valid within a `defmatch` block.
  """
  defmacro where(_expr) do
    raise CompileError,
      description: "where/1 can only be used inside defmatch"
  end

  @doc """
  Defines a compiled match predicate on a GridCodec binary.

  The generated function extracts only the fields referenced in `where`
  expressions and evaluates the guard — no full decode is performed.

  ## Options

  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `select:` | `[atom()]` | `[]` | Fields to extract and return on match. When set, the function returns `{:match, map}` or `:no_match` instead of `true`/`false`. |
  | `header:` | `boolean()` | `true` | Whether the binary includes the 8-byte GridCodec header. Set to `false` for payload-only binaries. |

  ## Examples

      # Predicate (returns true/false)
      defmatch :sampled?, BinaryEnvelope do
        where band(flags, 0x01) == 1
      end

      # Cross-field comparison
      defmatch :slow?, BinaryTraceContext do
        where end_time_ns - start_time_ns > 1_000_000_000
      end

      # Multiple conditions (ANDed)
      defmatch :target?, BinaryTraceContext do
        where band(flags, 1) == 1
        where kind == 3
      end

      # Field selection
      defmatch :extract_ctx, BinaryEnvelope, select: [:trace_id, :span_id] do
        where flags == 1
      end
  """
  defmacro defmatch(name, codec, opts \\ [], do_block)

  defmacro defmatch(name, codec, opts, do: block) do
    codec_module = Macro.expand(codec, __CALLER__)
    validate_codec!(codec_module)

    meta = codec_module.__match_meta__()
    field_names = MapSet.new(Map.keys(meta))
    conditions = parse_conditions(block)
    select_fields = Keyword.get(opts, :select, [])
    header = Keyword.get(opts, :header, true)

    where_refs =
      conditions
      |> Enum.flat_map(&find_field_refs(&1, field_names))
      |> Enum.uniq()

    all_refs = Enum.uniq(where_refs ++ select_fields)

    for ref <- all_refs do
      unless Map.has_key?(meta, ref) do
        raise CompileError,
          description:
            "Field #{inspect(ref)} not found in #{inspect(codec_module)}. " <>
              "Available: #{inspect(Map.keys(meta))}"
      end
    end

    binary_var = Macro.var(:__gc_bin__, __MODULE__)

    extraction_bindings =
      for field_name <- all_refs do
        field_meta = Map.fetch!(meta, field_name)
        wire_mod = field_meta.wire_module
        offset = if header, do: field_meta.offset, else: field_meta.payload_offset
        endian = field_meta.endian
        var = Macro.var(field_name, __MODULE__)
        ast = wire_mod.getter_ast(offset, endian, binary_var)

        quote do
          unquote(var) = unquote(ast)
        end
      end

    guard_ast =
      conditions
      |> Enum.map(&rewrite_field_refs(&1, field_names))
      |> Enum.reduce(fn right, left ->
        quote(do: unquote(left) and unquote(right))
      end)

    body =
      if select_fields == [] do
        # Predicate mode: return true/false
        quote do
          unquote_splicing(extraction_bindings)
          unquote(guard_ast)
        end
      else
        select_map =
          {:%{}, [],
           Enum.map(select_fields, fn f ->
             {f, Macro.var(f, __MODULE__)}
           end)}

        quote do
          unquote_splicing(extraction_bindings)

          if unquote(guard_ast) do
            {:match, unquote(select_map)}
          else
            :no_match
          end
        end
      end

    if select_fields == [] do
      quote do
        def unquote(name)(unquote(binary_var)) when is_binary(unquote(binary_var)) do
          unquote(body)
        end

        def unquote(name)(_), do: false
      end
    else
      quote do
        def unquote(name)(unquote(binary_var)) when is_binary(unquote(binary_var)) do
          unquote(body)
        end

        def unquote(name)(_), do: :no_match
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers (compile-time only, run inside the macro body)
  # ---------------------------------------------------------------------------

  @doc false
  def validate_codec!(mod) do
    unless function_exported?(mod, :__match_meta__, 0) do
      raise CompileError,
        description:
          "#{inspect(mod)} does not export __match_meta__/0. " <>
            "Ensure it uses GridCodec.Struct and is compiled before this module."
    end
  end

  @doc false
  def parse_conditions({:__block__, _, stmts}), do: Enum.map(stmts, &unwrap_where/1)
  def parse_conditions(single), do: [unwrap_where(single)]

  defp unwrap_where({:where, _, [expr]}), do: expr
  defp unwrap_where(expr), do: expr

  @doc false
  def find_field_refs(ast, field_set) do
    {_ast, refs} =
      Macro.prewalk(ast, [], fn
        {name, _meta, ctx} = node, acc when is_atom(name) and is_nil(ctx) ->
          if MapSet.member?(field_set, name), do: {node, [name | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(refs)
  end

  @doc false
  def rewrite_field_refs(ast, field_set) do
    Macro.prewalk(ast, fn
      {name, _meta, nil} = _node when is_atom(name) ->
        if MapSet.member?(field_set, name) do
          Macro.var(name, __MODULE__)
        else
          {name, [], nil}
        end

      node ->
        node
    end)
  end
end
