defmodule GridCodec.Struct.Compiler do
  @moduledoc false

  import Bitwise

  @doc """
  Generates the struct definition and codec implementation at compile time.

  This module is invoked via `@before_compile` when using `GridCodec.Struct`
  and generates:

  - `defstruct` with fields and defaults from the defcodec block
  - `@enforce_keys` for fields with `presence: :required`
  - All codec functions that work with the struct type
  """

  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :gridcodec_fields) |> Enum.reverse()
    groups = Module.get_attribute(env.module, :gridcodec_groups) |> Enum.reverse()
    opts = Module.get_attribute(env.module, :gridcodec_opts) || []

    # Extract options with defaults
    version = Keyword.get(opts, :version, 1)
    schema_id = Keyword.get(opts, :schema_id, 0)
    endian = Keyword.get(opts, :endian, :little)
    align_fields = Keyword.get(opts, :align, false)
    generate_typespec = Keyword.get(opts, :generate_typespec, true)

    telemetry_enabled =
      Keyword.get(opts, :telemetry, Application.get_env(:grid_codec, :telemetry, false))

    telemetry_min_duration =
      Keyword.get(
        opts,
        :telemetry_min_duration,
        Application.get_env(:grid_codec, :telemetry_min_duration, 0)
      )

    validate_enabled =
      Keyword.get(opts, :validate, Application.get_env(:grid_codec, :validate, false))

    # Template ID: explicit or hash of module name
    template_id =
      case Keyword.get(opts, :template_id) do
        nil -> :erlang.phash2(env.module) &&& 0xFFFF
        id -> id
      end

    # Type name: explicit via :name, or full module path (safe default, no collisions)
    type_name =
      case Keyword.get(opts, :name) do
        nil ->
          env.module |> Module.split() |> Enum.join(".")

        name when is_binary(name) ->
          name

        name when is_atom(name) ->
          Atom.to_string(name)
      end

    ensure_unique_type_name!(type_name, env.module, env.file, env.line)

    # Resolve field types
    resolved_fields = resolve_types(fields)
    {fixed_fields, var_fields} = partition_fields(resolved_fields)

    # Calculate offsets
    {field_offsets, block_length} = calculate_offsets(fixed_fields, align_fields)
    block_bits = block_length * 8
    has_variable_tail = var_fields != [] or groups != []
    framed_bits = 64 + block_bits

    layout_doc =
      build_layout_typedoc(fixed_fields, var_fields, groups, field_offsets, block_length)

    framed_layout_doc =
      build_framed_layout_typedoc(
        fixed_fields,
        var_fields,
        groups,
        field_offsets,
        block_length,
        framed_bits
      )

    # Validate :since field ordering (must be non-decreasing in fixed block)
    validate_since_ordering(fixed_fields)

    # Build field_versions from :since opts
    field_versions = build_field_versions(fields)

    # Pre-compute null sentinel block for version-aware decoding
    null_fixed_block = compute_null_fixed_block(fixed_fields, field_offsets, block_length, endian)

    # Process groups — auto-generate entry codecs from field declarations when
    # entry_encoder/entry_decoder are not explicitly provided
    {processed_groups, auto_group_fns} = process_groups(groups, endian)

    # Build struct field list with defaults (includes group names with default [])
    {struct_fields, enforce_keys} = build_struct_fields(fields, groups)
    struct_type_ast = build_struct_type_ast(resolved_fields, groups)
    struct_typedoc = build_struct_typedoc(resolved_fields, groups)

    # Build schema metadata
    field_names = Enum.map(fields, fn {name, _, _} -> name end)

    schema = %{
      fields: fields,
      groups: groups,
      version: version,
      template_id: template_id,
      schema_id: schema_id,
      endian: endian,
      block_length: block_length,
      fixed_fields: Enum.map(fixed_fields, fn {name, _, _, _} -> name end),
      var_fields: Enum.map(var_fields, fn {name, _, _, _} -> name end),
      field_versions: field_versions,
      type: type_name
    }

    # Generate encoder/decoder AST (using processed_groups with auto-generated codecs)
    encoder_clauses =
      generate_encoder_clauses(fixed_fields, var_fields, processed_groups, endian)

    struct_encoder_body =
      generate_struct_encoder(fixed_fields, var_fields, processed_groups, endian, env.module)

    decoder_body = generate_decoder(fixed_fields, var_fields, processed_groups, endian)

    struct_decoder_body =
      generate_struct_decoder(fixed_fields, var_fields, processed_groups, endian, env.module)

    getter_macro = generate_getter_macro(fixed_fields, var_fields, groups, field_offsets, endian)

    compare_macro =
      generate_compare_macro(fixed_fields, var_fields, groups, field_offsets, endian)

    match_macro = generate_match_macro(fixed_fields, field_offsets, block_length, endian)
    field_macro = generate_field_macro(fixed_fields, var_fields, groups, field_offsets, endian)

    # Header: precompute the 8-byte binary at compile time
    header_opts = [
      block_length: block_length,
      template_id: template_id,
      schema_id: schema_id,
      version: version
    ]

    header_binary =
      <<block_length::little-16, template_id::little-16, schema_id::little-16,
        version::little-16>>

    module = env.module

    quote do
      # Generate @enforce_keys before defstruct
      if unquote(enforce_keys) != [] do
        @enforce_keys unquote(enforce_keys)
      end

      # Generate defstruct
      defstruct unquote(struct_fields)

      if unquote(generate_typespec) do
        @typedoc unquote(struct_typedoc)
        @type t() :: unquote(struct_type_ast)

        @typedoc unquote(layout_doc)
        @type layout() ::
                unquote(
                  if has_variable_tail do
                    quote(do: <<_::unquote(block_bits), _::_*8>>)
                  else
                    quote(do: <<_::unquote(block_bits)>>)
                  end
                )

        @typedoc unquote(framed_layout_doc)
        @type framed_layout() ::
                unquote(
                  if has_variable_tail do
                    quote(do: <<_::unquote(framed_bits), _::_*8>>)
                  else
                    quote(do: <<_::unquote(framed_bits)>>)
                  end
                )
      end

      @doc """
      Creates a new #{inspect(unquote(module))} struct with coercion and validation.

      Accepts atom keys, string keys, or a mix. Coerces string values to the
      correct types (e.g., `"100"` → integer, `"true"` → boolean,
      `"2026-01-01T00:00:00Z"` → DateTime). Then validates if `validate: true`.

      Returns `{:ok, struct}` or `{:error, %GridCodec.ValidationError{}}`.

      ## Examples

          {:ok, event} = #{inspect(unquote(module))}.new(id: 42, price: 100)
          {:ok, event} = #{inspect(unquote(module))}.new(%{"id" => "42", "price" => "100"})
          {:error, %GridCodec.ValidationError{code: :cast_error}} =
            #{inspect(unquote(module))}.new(price: "not_a_number")
      """
      if unquote(generate_typespec) do
        @spec new(map() | keyword()) ::
                {:ok, t()} | {:error, GridCodec.ValidationError.t()}
      end

      def new(attrs \\ %{})
      def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

      def new(attrs) when is_map(attrs) do
        case __cast__(attrs) do
          {:ok, coerced} ->
            struct = struct(unquote(module), coerced)

            try do
              __validate__(struct)
              {:ok, struct}
            rescue
              e in GridCodec.ValidationError -> {:error, e}
            end

          {:error, _} = error ->
            error
        end
      end

      @doc """
      Like `new/1` but raises on failure.
      """
      if unquote(generate_typespec) do
        @spec new!(map() | keyword()) :: t()
      end

      def new!(attrs \\ %{}) do
        case new(attrs) do
          {:ok, struct} -> struct
          {:error, error} -> raise error
        end
      end

      # Internal: coerce attrs map, return {:ok, coerced_map} or {:error, %ValidationError{}}
      unquote(generate_cast_fn(resolved_fields, processed_groups, env.module))

      # Content hash: deterministic SHA256 from wire format
      unquote(generate_content_hash_fn(env.module, generate_typespec))

      # Projection: decode only selected fields
      unquote(
        generate_decode_only_fn(
          fixed_fields,
          field_offsets,
          endian,
          env.module,
          generate_typespec,
          block_length
        )
      )

      # Schema introspection (hidden from ExDoc — internal API)
      @doc false
      @spec __schema__() :: map()
      def __schema__, do: unquote(Macro.escape(schema))
      @doc false
      @spec __template_id__() :: unquote(template_id)
      def __template_id__, do: unquote(template_id)
      @doc false
      @spec __schema_id__() :: unquote(schema_id)
      def __schema_id__, do: unquote(schema_id)
      @doc false
      @spec __version__() :: unquote(version)
      def __version__, do: unquote(version)
      @doc false
      @spec __type__() :: String.t()
      def __type__, do: unquote(type_name)
      @doc false
      @spec __fields__() :: [atom()]
      def __fields__, do: unquote(field_names)
      @doc false
      @spec block_length() :: unquote(block_length)
      def block_length, do: unquote(block_length)

      @doc false
      def __gridcodec_struct__?, do: true

      # Store header for encode/decode
      @__gridcodec_header_opts__ unquote(header_opts)
      @__gridcodec_header__ unquote(header_binary)
      @__gridcodec_header_size__ 8

      # Version-aware decoding: null sentinel block for padding shorter binaries
      @__null_fixed_block__ unquote(null_fixed_block)
      @__current_block_length__ unquote(block_length)

      # Auto-generated group entry codecs
      unquote_splicing(auto_group_fns)

      # Field validation (when validate: true)
      unquote(
        generate_validate_fn(resolved_fields, processed_groups, validate_enabled, env.module)
      )

      # Encode/Decode API with optional telemetry
      unquote(
        generate_encode_api(
          module,
          type_name,
          schema_id,
          template_id,
          telemetry_enabled,
          telemetry_min_duration
        )
      )

      # Internal: encode payload only (no header)
      unquote(struct_encoder_body)

      # Internal encoder that works with maps (for compatibility)
      unquote(encoder_clauses)

      @doc """
      Coerce + validate + encode in one shot — no struct allocation.

      Accepts maps (atom or string keys), keyword lists, or structs.
      Coerces string values, validates (if enabled), and returns the
      binary directly. One allocation: the output binary.

      ## Examples

          {:ok, binary} = #{inspect(unquote(module))}.new_binary(%{"price" => "100", "active" => "true"})
          {:ok, binary} = #{inspect(unquote(module))}.new_binary(price: 100, active: true)
          {:ok, binary} = #{inspect(unquote(module))}.new_binary(existing_struct)
      """
      if unquote(generate_typespec) do
        @spec new_binary(map() | keyword() | t()) ::
                {:ok, binary()} | {:error, GridCodec.ValidationError.t()}
      end

      def new_binary(%unquote(module){} = struct) do
        __validate__(struct)
        payload = encode_payload(struct)
        {:ok, <<@__gridcodec_header__::binary, payload::binary>>}
      rescue
        e in GridCodec.ValidationError -> {:error, e}
      end

      def new_binary(attrs) when is_list(attrs), do: new_binary(Map.new(attrs))

      def new_binary(attrs) when is_map(attrs) do
        case __cast__(attrs) do
          {:ok, coerced} ->
            try do
              __validate__(coerced)
              payload = encode_map(coerced)
              {:ok, <<@__gridcodec_header__::binary, payload::binary>>}
            rescue
              e in GridCodec.ValidationError -> {:error, e}
            end

          {:error, _} = error ->
            error
        end
      end

      # ========================================================================
      # Decode API
      # ========================================================================

      unquote(
        generate_decode_api(
          module,
          type_name,
          schema_id,
          template_id,
          telemetry_enabled,
          telemetry_min_duration
        )
      )

      defp decode_versioned_payload(payload, header_block_length)
           when header_block_length >= @__current_block_length__ do
        decode_payload(payload)
      end

      defp decode_versioned_payload(payload, header_block_length) do
        <<fixed_data::binary-size(header_block_length), after_fixed::binary>> = payload
        padding_size = @__current_block_length__ - header_block_length
        padding = binary_part(@__null_fixed_block__, header_block_length, padding_size)
        decode_payload(<<fixed_data::binary, padding::binary, after_fixed::binary>>)
      end

      # Internal: decode payload only (no header)
      defp decode_payload(binary) when is_binary(binary) do
        unquote(struct_decoder_body)
      end

      # Internal decoder that returns map (used for tests/introspection)
      @doc false
      def decode_map(binary) when is_binary(binary) do
        unquote(decoder_body)
      end

      defp validate_header(header) do
        cond do
          header.template_id != unquote(template_id) ->
            {:error, {:template_id_mismatch, header.template_id, unquote(template_id)}}

          header.schema_id != unquote(schema_id) ->
            {:error, {:schema_id_mismatch, header.schema_id, unquote(schema_id)}}

          header.version > unquote(version) ->
            {:error, {:version_too_new, header.version, unquote(version)}}

          true ->
            :ok
        end
      end

      # Zero-copy field access macro
      unquote(getter_macro)

      # Type-aware field comparison macro
      unquote(compare_macro)

      # Pattern matching macro
      unquote(match_macro)

      # Field spec macro for GridCodec.get/2
      unquote(field_macro)
    end
  end

  # ============================================================================
  # Struct Field Generation
  # ============================================================================

  defp build_struct_fields(fields, groups) do
    struct_fields =
      Enum.map(fields, fn {name, _type, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        default = Keyword.get(opts, :default)
        const_value = Keyword.get(opts, :value)

        field_default =
          case presence do
            :constant -> const_value
            _ -> default
          end

        {name, field_default}
      end)

    group_fields = Enum.map(groups, fn {name, _, _} -> {name, []} end)

    enforce_keys =
      fields
      |> Enum.filter(fn {_name, _type, opts} ->
        Keyword.get(opts, :presence) == :required
      end)
      |> Enum.map(fn {name, _, _} -> name end)

    {struct_fields ++ group_fields, enforce_keys}
  end

  defp ensure_unique_type_name!(type_name, module, file, line) do
    collision =
      :code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.find(fn mod ->
        mod != module and is_gridcodec_struct?(mod) and function_exported?(mod, :__type__, 0) and
          safe_type(mod) == type_name
      end)

    if collision do
      raise CompileError,
        file: file,
        line: line,
        description:
          "GridCodec type name collision: #{inspect(type_name)} is already used by " <>
            "#{inspect(collision)}. Use the :name option to assign a unique type name."
    end
  end

  defp is_gridcodec_struct?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__gridcodec_struct__?, 0) and
      function_exported?(module, :__schema_id__, 0) and
      function_exported?(module, :__template_id__, 0)
  end

  defp safe_type(module) do
    module.__type__()
  rescue
    _ -> nil
  end

  defp build_struct_type_ast(resolved_fields, groups) do
    typed_fields =
      Enum.map(resolved_fields, fn {name, type_atom, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        const_value = Keyword.get(opts, :value)
        base = base_field_type_ast(type_atom, module)

        field_type_ast =
          case presence do
            :constant -> Macro.escape(const_value)
            :required -> base
            _ -> quote(do: unquote(base) | nil)
          end

        {name, field_type_ast}
      end)

    group_fields =
      Enum.map(groups, fn {name, _block, _opts} ->
        # Encode path expects list entries; decode path returns GridCodec.Group.t().
        {name, quote(do: [map()] | GridCodec.Group.t())}
      end)

    quote do
      %__MODULE__{unquote_splicing(typed_fields ++ group_fields)}
    end
  end

  defp build_struct_typedoc(_resolved_fields, _groups),
    do: "Struct representation for this codec module."

  defp base_field_type_ast(:u8, _module), do: quote(do: non_neg_integer())
  defp base_field_type_ast(:u16, _module), do: quote(do: non_neg_integer())
  defp base_field_type_ast(:u32, _module), do: quote(do: non_neg_integer())
  defp base_field_type_ast(:u64, _module), do: quote(do: non_neg_integer())
  defp base_field_type_ast(:i8, _module), do: quote(do: integer())
  defp base_field_type_ast(:i16, _module), do: quote(do: integer())
  defp base_field_type_ast(:i32, _module), do: quote(do: integer())
  defp base_field_type_ast(:i64, _module), do: quote(do: integer())
  defp base_field_type_ast(:f32, _module), do: quote(do: float())
  defp base_field_type_ast(:f64, _module), do: quote(do: float())
  defp base_field_type_ast(:uuid, _module), do: quote(do: <<_::128>>)
  defp base_field_type_ast(:uuid_string, _module), do: quote(do: String.t())
  defp base_field_type_ast(:bool, _module), do: quote(do: boolean())
  defp base_field_type_ast(:string, _module), do: quote(do: String.t())
  defp base_field_type_ast(:string8, _module), do: quote(do: String.t())
  defp base_field_type_ast(:string16, _module), do: quote(do: String.t())
  defp base_field_type_ast(:string32, _module), do: quote(do: String.t())

  defp base_field_type_ast(type_atom, _module) when type_atom in [:timestamp_us, :timestamp_ns] do
    quote(do: integer() | DateTime.t())
  end

  defp base_field_type_ast(:decimal, _module) do
    quote(do: Decimal.t() | {integer(), integer()} | integer() | float())
  end

  defp base_field_type_ast(type_atom, module) when is_atom(type_atom) and is_atom(module) do
    if module_has_type?(module, :t, 0) do
      quote(do: unquote(module).t())
    else
      quote(do: term())
    end
  end

  defp module_has_type?(module, type_name, arity) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        case Code.Typespec.fetch_types(module) do
          {:ok, types} ->
            Enum.any?(types, fn
              {:type, {^type_name, _ast, args}} -> length(args) == arity
              {_, {^type_name, _ast, args}} -> length(args) == arity
              _ -> false
            end)

          :error ->
            false
        end

      _ ->
        false
    end
  end

  defp build_layout_typedoc(fixed_fields, var_fields, groups, _field_offsets, block_length) do
    pattern_snippet = build_payload_pattern_snippet(fixed_fields, var_fields, groups)
    variable_note = variable_note(var_fields, groups)

    """
    Binary payload layout (header: false).

    Fixed block: #{block_length} bytes.
    #{variable_note}

    Pattern sketch:

    ```elixir
    #{pattern_snippet}
    ```
    """
  end

  defp build_framed_layout_typedoc(
         fixed_fields,
         var_fields,
         groups,
         field_offsets,
         block_length,
         framed_bits
       ) do
    payload_doc =
      build_layout_typedoc(fixed_fields, var_fields, groups, field_offsets, block_length)

    framed_pattern = build_framed_pattern_snippet(fixed_fields, var_fields, groups)

    """
    Framed binary layout (includes 8-byte GridCodec header).

    Header (8 bytes): `block_length:u16, template_id:u16, schema_id:u16, version:u16`.
    Total minimum size: #{div(framed_bits, 8)} bytes.

    Pattern sketch:

    ```elixir
    #{framed_pattern}
    ```

    #{payload_doc}
    """
  end

  defp build_payload_pattern_snippet(fixed_fields, var_fields, groups) do
    fixed_segments =
      Enum.map(fixed_fields, fn {name, type, module, _opts} ->
        segment = pattern_segment_for_type(type, module)
        "#{name}::#{segment}"
      end)

    tail_segments =
      []
      |> maybe_add_group_tail(groups)
      |> maybe_add_var_tail(var_fields)

    segments = fixed_segments ++ tail_segments

    case segments do
      [] ->
        "<<>>"

      list ->
        lines = wrap_segments(list, 88)

        "<<" <>
          "\n" <>
          Enum.map_join(lines, "\n", fn line -> "  #{line}" end) <>
          "\n>>"
    end
  end

  defp build_framed_pattern_snippet(fixed_fields, var_fields, groups) do
    payload = build_payload_pattern_snippet(fixed_fields, var_fields, groups)

    header =
      "<<" <>
        "\n" <>
        "  block_length::little-unsigned-16,\n" <>
        "  template_id::little-unsigned-16,\n" <>
        "  schema_id::little-unsigned-16,\n" <>
        "  version::little-unsigned-16,"

    case payload do
      "<<>>" ->
        header <> "\n>>"

      _ ->
        payload_body =
          payload
          |> String.replace_prefix("<<\n", "")
          |> String.replace_suffix("\n>>", "")
          |> String.split("\n")
          |> Enum.map_join("\n", fn line -> "  #{line}" end)

        header <> "\n" <> payload_body <> "\n>>"
    end
  end

  defp maybe_add_var_tail(segments, []), do: segments
  defp maybe_add_var_tail(segments, _var_fields), do: segments ++ ["var_data::binary"]

  defp maybe_add_group_tail(segments, []), do: segments
  defp maybe_add_group_tail(segments, _groups), do: segments ++ ["groups::binary"]

  defp wrap_segments(segments, max_width) do
    Enum.reduce(segments, [], fn segment, acc ->
      case acc do
        [] ->
          [segment]

        [last | rest] ->
          candidate = last <> ", " <> segment

          if String.length(candidate) <= max_width do
            [candidate | rest]
          else
            [segment, last | rest]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp pattern_segment_for_type(:u8, _module), do: "unsigned-8"
  defp pattern_segment_for_type(:i8, _module), do: "signed-8"
  defp pattern_segment_for_type(:u16, _module), do: "unsigned-little-16"
  defp pattern_segment_for_type(:i16, _module), do: "signed-little-16"
  defp pattern_segment_for_type(:u32, _module), do: "unsigned-little-32"
  defp pattern_segment_for_type(:i32, _module), do: "signed-little-32"
  defp pattern_segment_for_type(:u64, _module), do: "unsigned-little-64"
  defp pattern_segment_for_type(:i64, _module), do: "signed-little-64"
  defp pattern_segment_for_type(:f32, _module), do: "float-little-32"
  defp pattern_segment_for_type(:f64, _module), do: "float-little-64"
  defp pattern_segment_for_type(:bool, _module), do: "unsigned-8"
  defp pattern_segment_for_type(:uuid, _module), do: "binary-size(16)"
  defp pattern_segment_for_type(:uuid_string, _module), do: "binary-size(16)"
  defp pattern_segment_for_type(:decimal, _module), do: "binary-size(9)"
  defp pattern_segment_for_type(:timestamp_us, _module), do: "signed-little-64"
  defp pattern_segment_for_type(:timestamp_ns, _module), do: "signed-little-64"
  defp pattern_segment_for_type(_type, module), do: "binary-size(#{module.size()})"

  defp variable_note([], []), do: "No variable section (fixed-size payload only)."

  defp variable_note(var_fields, groups) do
    parts = []
    parts = if groups != [], do: parts ++ ["contains group section"], else: parts
    parts = if var_fields != [], do: parts ++ ["contains var-data section"], else: parts
    "Variable section: " <> Enum.join(parts, " and ") <> "."
  end

  # ============================================================================
  # Type Resolution (from GridCodec.Compiler)
  # ============================================================================

  defp resolve_types(fields) do
    Enum.map(fields, fn {name, type_atom, opts} ->
      case GridCodec.Type.lookup(type_atom) do
        {:ok, module} ->
          {name, type_atom, module, opts}

        {:error, :unknown_type} ->
          raise CompileError,
            description: "Unknown type #{inspect(type_atom)} for field #{inspect(name)}"
      end
    end)
  end

  defp partition_fields(resolved_fields) do
    Enum.split_with(resolved_fields, fn {_name, _type, module, _opts} ->
      module.size() != :variable
    end)
  end

  # ============================================================================
  # Offset Calculation
  # ============================================================================

  defp calculate_offsets(fixed_fields, align_fields) do
    {offsets, total} =
      Enum.reduce(fixed_fields, {%{}, 0}, fn {name, _type, module, _opts}, {acc, offset} ->
        aligned_offset =
          if align_fields do
            GridCodec.Type.align(offset, module.alignment())
          else
            offset
          end

        size = module.size()
        {Map.put(acc, name, aligned_offset), aligned_offset + size}
      end)

    {offsets, total}
  end

  # ============================================================================
  # Schema Evolution Support
  # ============================================================================

  defp validate_since_ordering(fixed_fields) do
    since_values =
      Enum.map(fixed_fields, fn {_name, _type, _module, opts} ->
        Keyword.get(opts, :since, 1)
      end)

    unless since_values == Enum.sort(since_values) do
      labels =
        Enum.map(fixed_fields, fn {name, _type, _module, opts} ->
          "#{name} (since: #{Keyword.get(opts, :since, 1)})"
        end)

      raise CompileError,
        description:
          "Fields with :since must be declared after all earlier-version fields " <>
            "in the fixed block. Fixed field order: #{Enum.join(labels, ", ")}"
    end
  end

  defp build_field_versions(fields) do
    fields
    |> Enum.filter(fn {_, _, opts} -> Keyword.has_key?(opts, :since) end)
    |> Enum.map(fn {name, _, opts} -> {name, Keyword.get(opts, :since)} end)
    |> Map.new()
  end

  defp compute_null_fixed_block(fixed_fields, field_offsets, block_length, endian) do
    if block_length == 0 do
      <<>>
    else
      base = :binary.copy(<<0>>, block_length)

      Enum.reduce(fixed_fields, base, fn {name, _type, module, _opts}, acc ->
        offset = Map.get(field_offsets, name)
        null_bytes = null_binary_for_type(module, endian)
        size = byte_size(null_bytes)

        <<prefix::binary-size(offset), _::binary-size(size), suffix::binary>> = acc
        <<prefix::binary, null_bytes::binary, suffix::binary>>
      end)
    end
  end

  defp null_binary_for_type(module, endian) do
    if function_exported?(module, :encode_value, 1) do
      module.encode_value(nil)
    else
      null_val = module.null_value()
      size = module.size()
      encode_null_to_binary(null_val, size, endian)
    end
  end

  defp encode_null_to_binary(:nan, 4, :little), do: <<0x00, 0x00, 0xC0, 0x7F>>
  defp encode_null_to_binary(:nan, 4, :big), do: <<0x7F, 0xC0, 0x00, 0x00>>

  defp encode_null_to_binary(:nan, 8, :little),
    do: <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x7F>>

  defp encode_null_to_binary(:nan, 8, :big),
    do: <<0x7F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>

  defp encode_null_to_binary(nil, size, _endian), do: <<0::size(size * 8)>>
  defp encode_null_to_binary(val, _size, _endian) when is_binary(val), do: val

  defp encode_null_to_binary(val, size, endian) when is_integer(val) do
    bits = size * 8

    case endian do
      :little -> <<val::integer-little-size(bits)>>
      :big -> <<val::integer-big-size(bits)>>
    end
  end

  # ============================================================================
  # Auto-Generated Group Entry Codecs
  # ============================================================================

  defp process_groups(groups, endian) do
    Enum.map_reduce(groups, [], fn {name, block, opts}, acc_fns ->
      has_explicit_codecs =
        Keyword.has_key?(opts, :entry_encoder) or Keyword.has_key?(opts, :entry_decoder)

      group_fields = parse_group_fields(block)

      if has_explicit_codecs or group_fields == [] do
        {{name, block, opts}, acc_fns}
      else
        resolved = resolve_types(group_fields)

        var_fields =
          Enum.filter(resolved, fn {_n, _t, mod, _o} -> mod.size() == :variable end)

        if var_fields != [] do
          names = Enum.map(var_fields, fn {n, _, _, _} -> n end)

          raise CompileError,
            description:
              "Group :#{name} contains variable-length fields #{inspect(names)}. " <>
                "Group entries must have only fixed-size fields."
        end

        encoder_fn = generate_auto_entry_encoder(name, resolved, endian)
        decoder_fn = generate_auto_entry_decoder(name, resolved, endian)
        batch_encoder_fn = generate_auto_batch_encoder(name, resolved, endian)
        batch_decoder_fn = generate_auto_batch_decoder(name, resolved, endian)

        encoder_fn_name = :"__encode_#{name}_entry__"
        decoder_fn_name = :"__decode_#{name}_entry__"
        batch_encoder_fn_name = :"__encode_#{name}_group__"
        batch_decoder_fn_name = :"__decode_all_#{name}__"

        encoder_capture = {:&, [], [{:/, [], [{encoder_fn_name, [], Elixir}, 1]}]}
        decoder_capture = {:&, [], [{:/, [], [{decoder_fn_name, [], Elixir}, 1]}]}
        batch_decoder_capture = {:&, [], [{:/, [], [{batch_decoder_fn_name, [], Elixir}, 2]}]}

        block_length =
          Enum.reduce(resolved, 0, fn {_, _, mod, _}, acc -> acc + mod.size() end)

        updated_opts =
          opts
          |> Keyword.put(:entry_encoder, encoder_capture)
          |> Keyword.put(:entry_decoder, decoder_capture)
          |> Keyword.put(:batch_encoder, batch_encoder_fn_name)
          |> Keyword.put(:batch_decoder, batch_decoder_capture)
          |> Keyword.put(:block_length, block_length)
          |> Keyword.put(:__resolved_fields__, resolved)

        {{name, block, updated_opts},
         acc_fns ++ [encoder_fn, decoder_fn, batch_encoder_fn, batch_decoder_fn]}
      end
    end)
  end

  defp parse_group_fields(block_ast) do
    stmts =
      case block_ast do
        {:__block__, _, stmts} -> stmts
        nil -> []
        single -> [single]
      end

    Enum.flat_map(stmts, fn
      {:field, _, [name, type]} when is_atom(name) -> [{name, type, []}]
      {:field, _, [name, type, opts]} when is_atom(name) -> [{name, type, opts}]
      _ -> []
    end)
  end

  defp generate_auto_entry_encoder(group_name, resolved_fields, endian) do
    fn_name = :"__encode_#{group_name}_entry__"
    data_var = Macro.var(:entry, __MODULE__)

    binary_parts =
      Enum.map(resolved_fields, fn {name, _type, module, _opts} ->
        null_value = module.null_value()
        module.encode_ast(name, null_value, endian, data_var)
      end)

    quote do
      defp unquote(fn_name)(unquote(data_var)) when is_map(unquote(data_var)) do
        <<unquote_splicing(binary_parts)>>
      end
    end
  end

  # Generates a consolidated group encoder: direct local calls to the entry
  # encoder (JIT-inlineable), no function captures, no anonymous wrappers.
  defp generate_auto_batch_encoder(group_name, resolved_fields, _endian) do
    group_fn = :"__encode_#{group_name}_group__"
    loop_fn = :"__encode_#{group_name}_list__"
    entry_fn = :"__encode_#{group_name}_entry__"

    block_length =
      Enum.reduce(resolved_fields, 0, fn {_, _, mod, _}, acc -> acc + mod.size() end)

    quote do
      defp unquote(group_fn)([]) do
        <<0::little-16, 0::little-16>>
      end

      defp unquote(group_fn)(entries) when is_list(entries) do
        count = length(entries)
        iodata = unquote(loop_fn)(entries)

        :erlang.iolist_to_binary([
          <<unquote(block_length)::little-16, count::little-16>> | iodata
        ])
      end

      defp unquote(loop_fn)([]), do: []

      defp unquote(loop_fn)([entry | rest]) do
        [unquote(entry_fn)(entry) | unquote(loop_fn)(rest)]
      end
    end
  end

  defp generate_auto_entry_decoder(group_name, resolved_fields, endian) do
    fn_name = :"__decode_#{group_name}_entry__"

    patterns =
      Enum.map(resolved_fields, fn {name, _type, module, _opts} ->
        var = Macro.var(name, __MODULE__)
        module.decode_pattern_ast(var, endian)
      end)

    result_pairs = build_decode_result_pairs(resolved_fields)

    quote do
      defp unquote(fn_name)(<<unquote_splicing(patterns)>>) do
        {:ok, %{unquote_splicing(result_pairs)}}
      end
    end
  end

  defp generate_auto_batch_decoder(group_name, resolved_fields, endian) do
    fn_name = :"__decode_all_#{group_name}__"

    patterns =
      Enum.map(resolved_fields, fn {name, _type, module, _opts} ->
        var = Macro.var(name, __MODULE__)
        module.decode_pattern_ast(var, endian)
      end)

    result_pairs = build_decode_result_pairs(resolved_fields)

    quote do
      defp unquote(fn_name)(<<>>, acc), do: :lists.reverse(acc)

      defp unquote(fn_name)(<<unquote_splicing(patterns), rest::binary>>, acc) do
        entry = %{unquote_splicing(result_pairs)}
        unquote(fn_name)(rest, [entry | acc])
      end
    end
  end

  # Shared: build result pairs for group decoders, applying decode_as coercion
  defp build_decode_result_pairs(resolved_fields) do
    Enum.map(resolved_fields, fn {name, _type, source_module, opts} ->
      var = Macro.var(name, __MODULE__)

      value_ast =
        if function_exported?(source_module, :decode_value_ast, 1) do
          source_module.decode_value_ast(var)
        else
          var
        end

      final_ast =
        apply_decode_as(value_ast, Keyword.get(opts, :decode_as), source_module)

      {name, final_ast}
    end)
  end

  defp apply_decode_as(value_ast, nil, _source_module), do: value_ast

  defp apply_decode_as(value_ast, {type_ref, opts}, source_module) when is_list(opts) do
    target_module = resolve_decode_as_module(type_ref)

    unless function_exported?(target_module, :decode_as_ast, 2) do
      raise CompileError,
        description:
          "decode_as: {#{inspect(type_ref)}, ...} — module #{inspect(target_module)} " <>
            "does not implement decode_as_ast/2 callback"
    end

    target_module.decode_as_ast(value_ast, [{:source_module, source_module} | opts])
  end

  defp apply_decode_as(value_ast, type_ref, source_module) when is_atom(type_ref) do
    target_module = resolve_decode_as_module(type_ref)

    unless function_exported?(target_module, :decode_as_ast, 2) do
      raise CompileError,
        description:
          "decode_as: #{inspect(type_ref)} — module #{inspect(target_module)} " <>
            "does not implement decode_as_ast/2 callback"
    end

    target_module.decode_as_ast(value_ast, source_module: source_module)
  end

  defp resolve_decode_as_module(type_ref) do
    case GridCodec.Type.lookup(type_ref) do
      {:ok, module} -> module
      {:error, _} -> type_ref
    end
  end

  # ============================================================================
  # Encoder Generation
  # ============================================================================

  defp generate_encoder_clauses(fixed_fields, var_fields, groups, endian) do
    has_required =
      Enum.any?(fixed_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :required
      end)

    can_use_fast_path = not has_required and groups == [] and var_fields == []

    non_constant_fields =
      Enum.reject(fixed_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :constant
      end)

    if can_use_fast_path and not Enum.empty?(non_constant_fields) do
      fast_path = generate_fast_encoder(fixed_fields, endian)
      fallback = generate_fallback_encoder(fixed_fields, var_fields, groups, endian)

      quote do
        unquote(fast_path)
        unquote(fallback)
      end
    else
      fallback_body = generate_encoder(fixed_fields, var_fields, groups, endian)

      quote do
        defp encode_map(var!(data)) when is_map(var!(data)) do
          unquote(fallback_body)
        end
      end
    end
  end

  # Generate a struct-specific encoder that pattern matches directly on struct fields
  # This avoids the overhead of Map.from_struct() and provides optimal performance
  defp generate_struct_encoder(fixed_fields, var_fields, groups, endian, struct_module) do
    has_required =
      Enum.any?(fixed_fields ++ var_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :required
      end)

    can_use_fast_path = not has_required

    non_constant_fixed_fields =
      Enum.reject(fixed_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :constant
      end)

    has_defaults =
      Enum.any?(non_constant_fixed_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :default) != nil
      end)

    has_fields = not Enum.empty?(non_constant_fixed_fields) or not Enum.empty?(var_fields)

    cond do
      can_use_fast_path and groups != [] ->
        generate_struct_encoder_with_groups(
          fixed_fields,
          var_fields,
          groups,
          endian,
          struct_module
        )

      can_use_fast_path and has_fields and has_defaults ->
        generate_struct_encoder_with_defaults(
          fixed_fields,
          var_fields,
          non_constant_fixed_fields,
          endian,
          struct_module
        )

      can_use_fast_path and has_fields ->
        generate_struct_encoder_direct(
          fixed_fields,
          var_fields,
          non_constant_fixed_fields,
          endian,
          struct_module
        )

      true ->
        quote do
          defp encode_payload(%unquote(struct_module){} = struct) do
            data = Map.from_struct(struct)
            encode_map(data)
          end
        end
    end
  end

  # Fast path: no :default fields. Pass the struct directly as data_var to encode_ast.
  # Eliminates intermediate map allocation and redundant :maps.get calls.
  defp generate_struct_encoder_direct(
         fixed_fields,
         var_fields,
         _non_constant_fixed_fields,
         endian,
         struct_module
       ) do
    struct_var = Macro.var(:__struct__, __MODULE__)

    # Only pattern match var fields (for inline encoding); pass struct to encode_ast
    var_pattern_pairs =
      for {name, _, _, _} <- var_fields do
        var = Macro.var(name, __MODULE__)
        {name, var}
      end

    struct_pattern =
      if var_fields == [] do
        quote do: %unquote(struct_module){} = unquote(struct_var)
      else
        quote do:
                %unquote(struct_module){unquote_splicing(var_pattern_pairs)} = unquote(struct_var)
      end

    fixed_binary_parts =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        const_value = Keyword.get(opts, :value)
        null_value = module.null_value()

        case presence do
          :constant ->
            module.encode_ast(
              name,
              const_value,
              endian,
              quote(do: %{unquote(name) => unquote(const_value)})
            )

          _ ->
            module.encode_ast(name, null_value, endian, struct_var)
        end
      end)

    fixed_binary_ast =
      if fixed_binary_parts == [] do
        quote do: <<>>
      else
        quote do: <<unquote_splicing(fixed_binary_parts)>>
      end

    if var_fields == [] do
      quote do
        defp encode_payload(unquote(struct_pattern)) do
          unquote(fixed_binary_ast)
        end
      end
    else
      var_encoding_ast = generate_inline_var_encoder(var_fields)

      quote do
        defp encode_payload(unquote(struct_pattern)) do
          fixed_block = unquote(fixed_binary_ast)
          var_data = unquote(var_encoding_ast)
          <<fixed_block::binary, var_data::binary>>
        end
      end
    end
  end

  # Slower path for codecs with :default fields. Builds extracted_data map
  # to apply defaults before encoding.
  defp generate_struct_encoder_with_defaults(
         fixed_fields,
         var_fields,
         non_constant_fixed_fields,
         endian,
         struct_module
       ) do
    all_fields = non_constant_fixed_fields ++ var_fields

    pattern_pairs =
      for {name, _, _, _} <- all_fields do
        var = Macro.var(name, __MODULE__)
        {name, var}
      end

    struct_pattern = quote do: %unquote(struct_module){unquote_splicing(pattern_pairs)}

    extracted_data_pairs =
      for {name, _, _, opts} <- non_constant_fixed_fields do
        var = Macro.var(name, __MODULE__)
        default = Keyword.get(opts, :default)

        value_expr =
          if default != nil do
            quote do
              case unquote(var) do
                nil -> unquote(default)
                v -> v
              end
            end
          else
            var
          end

        {name, value_expr}
      end

    extracted_data = {:%{}, [], extracted_data_pairs}

    fixed_binary_parts =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        const_value = Keyword.get(opts, :value)
        null_value = module.null_value()

        case presence do
          :constant ->
            module.encode_ast(
              name,
              const_value,
              endian,
              quote(do: %{unquote(name) => unquote(const_value)})
            )

          _ ->
            module.encode_ast(name, null_value, endian, extracted_data)
        end
      end)

    fixed_binary_ast =
      if fixed_binary_parts == [] do
        quote do: <<>>
      else
        quote do: <<unquote_splicing(fixed_binary_parts)>>
      end

    if var_fields == [] do
      quote do
        defp encode_payload(unquote(struct_pattern)) do
          unquote(fixed_binary_ast)
        end
      end
    else
      var_encoding_ast = generate_inline_var_encoder(var_fields)

      quote do
        defp encode_payload(unquote(struct_pattern)) do
          fixed_block = unquote(fixed_binary_ast)
          var_data = unquote(var_encoding_ast)
          <<fixed_block::binary, var_data::binary>>
        end
      end
    end
  end

  # Struct encoder that pattern-matches fields directly, avoiding Map.from_struct.
  # Handles fixed fields, groups, and optionally var fields in one function.
  defp generate_struct_encoder_with_groups(
         fixed_fields,
         var_fields,
         groups,
         endian,
         struct_module
       ) do
    struct_var = Macro.var(:__struct__, __MODULE__)

    var_pattern_pairs =
      for {name, _, _, _} <- var_fields do
        {name, Macro.var(name, __MODULE__)}
      end

    struct_pattern =
      if var_fields == [] do
        quote do: %unquote(struct_module){} = unquote(struct_var)
      else
        quote do:
                %unquote(struct_module){unquote_splicing(var_pattern_pairs)} = unquote(struct_var)
      end

    fixed_binary_parts =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        const_value = Keyword.get(opts, :value)
        null_value = module.null_value()

        case presence do
          :constant ->
            module.encode_ast(
              name,
              const_value,
              endian,
              quote(do: %{unquote(name) => unquote(const_value)})
            )

          _ ->
            module.encode_ast(name, null_value, endian, struct_var)
        end
      end)

    fixed_binary_ast =
      if fixed_binary_parts == [] do
        quote do: <<>>
      else
        quote do: <<unquote_splicing(fixed_binary_parts)>>
      end

    group_encodings =
      Enum.map(groups, fn {name, _block, opts} ->
        encode_single_group_ast(name, opts, struct_var)
      end)

    body =
      cond do
        var_fields == [] and length(groups) == 1 ->
          [group_enc] = group_encodings

          quote do
            fixed_block = unquote(fixed_binary_ast)
            groups_bin = unquote(group_enc)
            <<fixed_block::binary, groups_bin::binary>>
          end

        var_fields == [] ->
          quote do
            fixed_block = unquote(fixed_binary_ast)
            groups_bin = :erlang.iolist_to_binary([unquote_splicing(group_encodings)])
            <<fixed_block::binary, groups_bin::binary>>
          end

        true ->
          var_encoding_ast = generate_inline_var_encoder(var_fields)

          quote do
            fixed_block = unquote(fixed_binary_ast)
            groups_bin = :erlang.iolist_to_binary([unquote_splicing(group_encodings)])
            var_data = unquote(var_encoding_ast)
            <<fixed_block::binary, groups_bin::binary, var_data::binary>>
          end
      end

    quote do
      defp encode_payload(unquote(struct_pattern)) do
        unquote(body)
      end
    end
  end

  # Generate inline variable field encoding using direct variable references
  defp generate_inline_var_encoder(var_fields) do
    encodings =
      Enum.map(var_fields, fn {name, type, _module, _opts} ->
        var = Macro.var(name, __MODULE__)
        encode_call_ast = var_encode_ast(type, var)
        encode_call_ast
      end)

    quote do
      IO.iodata_to_binary([unquote_splicing(encodings)])
    end
  end

  defp generate_fast_encoder(fixed_fields, endian) do
    non_constant_fields =
      Enum.reject(fixed_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :constant
      end)

    pattern_pairs =
      for {name, _, _, _} <- non_constant_fields do
        var = Macro.var(name, __MODULE__)
        {name, var}
      end

    pattern_map = {:%{}, [], pattern_pairs}

    extracted_data_pairs =
      for {name, _, _, _} <- non_constant_fields do
        var = Macro.var(name, __MODULE__)
        {name, var}
      end

    extracted_data = {:%{}, [], extracted_data_pairs}

    binary_parts =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        default = Keyword.get(opts, :default)
        const_value = Keyword.get(opts, :value)
        null_value = module.null_value()

        case presence do
          :constant ->
            module.encode_ast(
              name,
              const_value,
              endian,
              quote(do: %{unquote(name) => unquote(const_value)})
            )

          _ ->
            effective_default = if default == nil, do: null_value, else: default
            module.encode_ast(name, effective_default, endian, extracted_data)
        end
      end)

    quote do
      defp encode_map(unquote(pattern_map) = unquote(Macro.var(:_extracted_data, __MODULE__))) do
        <<unquote_splicing(binary_parts)>>
      end
    end
  end

  defp generate_fallback_encoder(fixed_fields, var_fields, groups, endian) do
    body = generate_encoder(fixed_fields, var_fields, groups, endian)

    quote do
      defp encode_map(var!(data)) when is_map(var!(data)) do
        unquote(body)
      end
    end
  end

  defp generate_encoder(fixed_fields, var_fields, groups, endian) do
    data_var = quote do: var!(data)

    required_validations = generate_required_validations(fixed_fields ++ var_fields, data_var)

    fixed_encoding =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        default = Keyword.get(opts, :default)
        const_value = Keyword.get(opts, :value)
        null_value = module.null_value()

        case presence do
          :constant ->
            module.encode_ast(
              name,
              const_value,
              endian,
              quote(do: %{unquote(name) => unquote(const_value)})
            )

          _ ->
            effective_default = if default == nil, do: null_value, else: default
            module.encode_ast(name, effective_default, endian, data_var)
        end
      end)

    fixed_binary =
      if fixed_encoding == [] do
        quote do: <<>>
      else
        quote do: <<unquote_splicing(fixed_encoding)>>
      end

    group_encoding = generate_group_encoder(groups, data_var)
    var_encoding = generate_var_encoder(var_fields, data_var)

    final_binary_ast =
      cond do
        groups == [] and var_fields == [] ->
          fixed_binary

        groups == [] ->
          quote do
            fixed_block = unquote(fixed_binary)
            var_data = unquote(var_encoding)
            <<fixed_block::binary, var_data::binary>>
          end

        var_fields == [] ->
          quote do
            fixed_block = unquote(fixed_binary)
            groups_binary = unquote(group_encoding)
            <<fixed_block::binary, groups_binary::binary>>
          end

        true ->
          quote do
            fixed_block = unquote(fixed_binary)
            groups_binary = unquote(group_encoding)
            var_data = unquote(var_encoding)
            <<fixed_block::binary, groups_binary::binary, var_data::binary>>
          end
      end

    if required_validations == [] do
      final_binary_ast
    else
      quote do
        unquote_splicing(required_validations)
        unquote(final_binary_ast)
      end
    end
  end

  defp generate_required_validations(fixed_fields, data_var) do
    fixed_fields
    |> Enum.filter(fn {_name, _type, _module, opts} ->
      Keyword.get(opts, :presence) == :required
    end)
    |> Enum.map(fn {name, _type, _module, _opts} ->
      quote do
        if :maps.get(unquote(name), unquote(data_var), nil) == nil do
          raise ArgumentError, "required field #{unquote(inspect(name))} cannot be nil"
        end
      end
    end)
  end

  defp generate_group_encoder([], _data_var), do: quote(do: <<>>)

  defp generate_group_encoder(groups, data_var) do
    encodings =
      Enum.map(groups, fn {name, _block, opts} ->
        encode_single_group_ast(name, opts, data_var)
      end)

    quote do
      :erlang.iolist_to_binary([unquote_splicing(encodings)])
    end
  end

  defp encode_single_group_ast(name, opts, data_var) do
    batch_encoder = Keyword.get(opts, :batch_encoder)
    entry_encoder = Keyword.get(opts, :entry_encoder)
    block_length = Keyword.get(opts, :block_length)

    cond do
      batch_encoder ->
        quote do
          unquote(batch_encoder)(:maps.get(unquote(name), unquote(data_var), []))
        end

      entry_encoder && block_length ->
        quote do
          GridCodec.Group.encode_fast(
            :maps.get(unquote(name), unquote(data_var), []),
            unquote(entry_encoder),
            unquote(block_length)
          )
        end

      entry_encoder ->
        quote do
          GridCodec.Group.encode(
            :maps.get(unquote(name), unquote(data_var), []),
            unquote(entry_encoder)
          )
        end

      true ->
        quote do
          :maps.get(unquote(name), unquote(data_var), <<0::little-16, 0::little-16>>)
        end
    end
  end

  defp generate_var_encoder([], _data_var), do: quote(do: <<>>)

  defp generate_var_encoder(var_fields, data_var) do
    encodings =
      Enum.map(var_fields, fn {name, type, _module, _opts} ->
        encode_call_ast = var_encode_ast(type, quote(do: value))

        quote do
          value = :maps.get(unquote(name), unquote(data_var), nil)
          unquote(encode_call_ast)
        end
      end)

    quote do
      IO.iodata_to_binary([unquote_splicing(encodings)])
    end
  end

  defp var_encode_ast(:string8, value_var),
    do: quote(do: GridCodec.Types.String.encode8(unquote(value_var)))

  defp var_encode_ast(:string16, value_var),
    do: quote(do: GridCodec.Types.String.encode16(unquote(value_var)))

  defp var_encode_ast(:string32, value_var),
    do: quote(do: GridCodec.Types.String.encode32(unquote(value_var)))

  defp var_encode_ast(:string, value_var),
    do: quote(do: GridCodec.Types.String.encode16(unquote(value_var)))

  defp var_encode_ast(_type, value_var),
    do: quote(do: GridCodec.Types.String.encode16(unquote(value_var)))

  # ============================================================================
  # Decoder Generation
  # ============================================================================

  defp generate_decoder(fixed_fields, var_fields, groups, endian) do
    fixed_patterns =
      Enum.map(fixed_fields, fn {name, _type, module, _opts} ->
        var = Macro.var(name, __MODULE__)
        module.decode_pattern_ast(var, endian)
      end)

    fixed_result_pairs =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        var = Macro.var(name, __MODULE__)
        presence = Keyword.get(opts, :presence, :optional)
        const_value = Keyword.get(opts, :value)

        value_ast =
          case presence do
            :constant ->
              Macro.escape(const_value)

            _ ->
              if function_exported?(module, :decode_value_ast, 1) do
                module.decode_value_ast(var)
              else
                var
              end
          end

        {name, value_ast}
      end)

    var_decoding = generate_var_decoder(var_fields)

    if fixed_patterns == [] and groups == [] and var_fields == [] do
      quote do
        if binary == <<>> do
          {:ok, %{}}
        else
          {:error, :expected_empty}
        end
      end
    else
      result_ast =
        cond do
          groups == [] and var_fields == [] ->
            quote do: %{unquote_splicing(fixed_result_pairs)}

          groups == [] ->
            quote do
              fixed_map = %{unquote_splicing(fixed_result_pairs)}
              var_rest = rest
              {var_map, _final_rest} = unquote(var_decoding)
              Map.merge(fixed_map, var_map)
            end

          var_fields == [] ->
            {group_steps, group_pairs, _final_rest} = generate_inline_group_steps(groups)

            quote do
              unquote_splicing(group_steps)
              %{unquote_splicing(fixed_result_pairs ++ group_pairs)}
            end

          true ->
            {group_steps, group_pairs, group_final_rest} = generate_inline_group_steps(groups)

            quote do
              unquote_splicing(group_steps)
              fixed_map = %{unquote_splicing(fixed_result_pairs ++ group_pairs)}
              var_rest = unquote(group_final_rest)
              {var_map, _final_rest} = unquote(var_decoding)
              Map.merge(fixed_map, var_map)
            end
        end

      quote do
        case binary do
          <<unquote_splicing(fixed_patterns), rest::binary>> ->
            result = unquote(result_ast)
            {:ok, result}

          _ ->
            {:error, :invalid_binary}
        end
      end
    end
  end

  # Generate a decoder that builds the struct directly (no map intermediate)
  defp generate_struct_decoder(fixed_fields, var_fields, groups, endian, struct_module) do
    fixed_patterns =
      Enum.map(fixed_fields, fn {name, _type, module, _opts} ->
        var = Macro.var(name, __MODULE__)
        module.decode_pattern_ast(var, endian)
      end)

    fixed_result_pairs =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        var = Macro.var(name, __MODULE__)
        presence = Keyword.get(opts, :presence, :optional)
        const_value = Keyword.get(opts, :value)

        value_ast =
          case presence do
            :constant ->
              Macro.escape(const_value)

            _ ->
              if function_exported?(module, :decode_value_ast, 1) do
                module.decode_value_ast(var)
              else
                var
              end
          end

        {name, value_ast}
      end)

    if fixed_patterns == [] and groups == [] and var_fields == [] do
      quote do
        if binary == <<>> do
          {:ok, %unquote(struct_module){}}
        else
          {:error, :expected_empty}
        end
      end
    else
      result_ast =
        cond do
          groups == [] and var_fields == [] ->
            quote do: %unquote(struct_module){unquote_splicing(fixed_result_pairs)}

          groups == [] ->
            generate_inline_var_struct_decoder(fixed_result_pairs, var_fields, struct_module)

          var_fields == [] ->
            {group_steps, group_pairs, _final_rest} = generate_inline_group_steps(groups)

            quote do
              unquote_splicing(group_steps)
              %unquote(struct_module){unquote_splicing(fixed_result_pairs ++ group_pairs)}
            end

          true ->
            {group_steps, group_pairs, group_final_rest} = generate_inline_group_steps(groups)

            {var_bindings, _var_final_rest} =
              Enum.reduce(var_fields, {[], group_final_rest}, fn {name, type, _module, _opts},
                                                                 {bindings, r_var} ->
                value_var = Macro.var(name, __MODULE__)
                new_rest_var = Macro.var(:"__rest_var_#{name}__", __MODULE__)
                decode_call = var_decode_ast(type, r_var)

                binding =
                  quote do
                    {unquote(value_var), unquote(new_rest_var)} = unquote(decode_call)
                  end

                {bindings ++ [binding], new_rest_var}
              end)

            var_pairs =
              for {name, _type, _module, _opts} <- var_fields do
                {name, Macro.var(name, __MODULE__)}
              end

            all_pairs = fixed_result_pairs ++ group_pairs ++ var_pairs

            quote do
              unquote_splicing(group_steps)
              unquote_splicing(var_bindings)
              %unquote(struct_module){unquote_splicing(all_pairs)}
            end
        end

      quote do
        case binary do
          <<unquote_splicing(fixed_patterns), rest::binary>> ->
            result = unquote(result_ast)
            {:ok, result}

          _ ->
            {:error, :invalid_binary}
        end
      end
    end
  end

  # Generate inline var field decoding that builds struct directly
  # This avoids Enum.reduce and struct!/2 overhead
  defp generate_inline_var_struct_decoder(fixed_result_pairs, var_fields, struct_module) do
    # Generate sequential decoding for each var field
    # Each step consumes part of 'rest' and produces a value
    {decode_bindings, final_rest_var} =
      Enum.reduce(var_fields, {[], quote(do: rest)}, fn {name, type, _module, _opts},
                                                        {bindings, rest_var} ->
        value_var = Macro.var(name, __MODULE__)
        new_rest_var = Macro.var(:"rest_after_#{name}", __MODULE__)

        decode_call = var_decode_ast(type, rest_var)

        binding =
          quote do
            {unquote(value_var), unquote(new_rest_var)} = unquote(decode_call)
          end

        {bindings ++ [binding], new_rest_var}
      end)

    # Build the var field pairs for struct creation
    var_result_pairs =
      for {name, _type, _module, _opts} <- var_fields do
        var = Macro.var(name, __MODULE__)
        {name, var}
      end

    # Combine fixed and var field pairs
    all_result_pairs = fixed_result_pairs ++ var_result_pairs

    # Suppress unused variable warning for final rest
    _ = final_rest_var

    quote do
      unquote_splicing(decode_bindings)
      %unquote(struct_module){unquote_splicing(all_result_pairs)}
    end
  end

  # Generate direct decode call (no apply!)
  defp var_decode_ast(:string8, rest_var),
    do: quote(do: GridCodec.Types.String.decode8(unquote(rest_var)))

  defp var_decode_ast(:string16, rest_var),
    do: quote(do: GridCodec.Types.String.decode16(unquote(rest_var)))

  defp var_decode_ast(:string32, rest_var),
    do: quote(do: GridCodec.Types.String.decode32(unquote(rest_var)))

  defp var_decode_ast(:string, rest_var),
    do: quote(do: GridCodec.Types.String.decode16(unquote(rest_var)))

  defp var_decode_ast(_type, rest_var),
    do: quote(do: GridCodec.Types.String.decode16(unquote(rest_var)))

  # Generates inline group parsing steps and returns components for
  # direct struct construction (no intermediate map).
  defp generate_inline_group_steps(groups) do
    {steps, final_rest_var, group_pairs} =
      Enum.reduce(groups, {[], quote(do: rest), []}, fn {name, _block, opts},
                                                        {steps, rest_var, pairs} ->
        decoder = Keyword.get(opts, :entry_decoder) || quote(do: fn b -> {:ok, b} end)
        batch_decoder = Keyword.get(opts, :batch_decoder)
        group_var = Macro.var(:"__grp_#{name}__", __MODULE__)
        new_rest = Macro.var(:"__rest_#{name}__", __MODULE__)

        step =
          if batch_decoder do
            quote do
              {unquote(group_var), unquote(new_rest)} =
                GridCodec.Group.parse_with_rest!(
                  unquote(rest_var),
                  unquote(decoder),
                  unquote(batch_decoder)
                )
            end
          else
            quote do
              {unquote(group_var), unquote(new_rest)} =
                GridCodec.Group.parse_with_rest!(unquote(rest_var), unquote(decoder))
            end
          end

        {steps ++ [step], new_rest, pairs ++ [{name, group_var}]}
      end)

    {steps, group_pairs, final_rest_var}
  end

  defp generate_var_decoder([]) do
    quote do
      {%{}, var_rest}
    end
  end

  defp generate_var_decoder(var_fields) do
    field_decoders =
      Enum.map(var_fields, fn {name, type, _module, _opts} ->
        decode_fn =
          case type do
            :string8 -> :decode8
            :string16 -> :decode16
            :string32 -> :decode32
            :string -> :decode16
            _ -> :decode16
          end

        {name, decode_fn}
      end)

    quote do
      Enum.reduce(
        unquote(Macro.escape(field_decoders)),
        {%{}, var_rest},
        fn {name, decode_fn}, {acc, binary} ->
          {value, rest} = apply(GridCodec.Types.String, decode_fn, [binary])
          {Map.put(acc, name, value), rest}
        end
      )
    end
  end

  # ============================================================================
  # Inline Getter Macro Generation
  # ============================================================================

  defp generate_getter_macro(fixed_fields, var_fields, groups, field_offsets, endian) do
    # Header size for framed binaries (encode includes header by default)
    header_size = 8

    # Build a map of field_name => {module, offset} for fixed fields
    # Offsets include header_size since encode/1 includes header by default
    fixed_field_specs =
      Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
        payload_offset = Map.get(field_offsets, name)
        # Add header size for framed binary access
        framed_offset = payload_offset + header_size
        {name, {module, framed_offset}}
      end)
      |> Map.new()

    # Also store payload-only offsets for header: false option
    payload_field_specs =
      Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
        offset = Map.get(field_offsets, name)
        {name, {module, offset}}
      end)
      |> Map.new()

    var_field_names = Enum.map(var_fields, fn {name, _, _, _} -> name end)
    group_names = Enum.map(groups, fn {name, _, _} -> name end)

    quote do
      @doc """
      Zero-copy field access macro.

      Expands at compile time to direct binary pattern matching.
      Handles null sentinel values, returning `nil` for null fields.

      By default, expects a framed binary (with header from `encode/1`).
      Use `header: false` option for payload-only binaries.

          require #{inspect(__MODULE__)}

          # Framed binary (default)
          value = #{inspect(__MODULE__)}.get(binary, :price)

          # Payload only (from encode(struct, header: false))
          value = #{inspect(__MODULE__)}.get(payload, :price, header: false)
      """
      defmacro get(binary_expr, field_name, opts \\ []) do
        # Choose offsets based on header option
        fixed_specs =
          if Keyword.get(opts, :header, true) do
            unquote(Macro.escape(fixed_field_specs))
          else
            unquote(Macro.escape(payload_field_specs))
          end

        var_fields = unquote(var_field_names)
        groups = unquote(group_names)
        endian = unquote(endian)
        module = __MODULE__

        GridCodec.Struct.Compiler.__build_inline_getter__(
          binary_expr,
          field_name,
          fixed_specs,
          var_fields,
          groups,
          endian,
          module
        )
      end
    end
  end

  @doc false
  def __build_inline_getter__(
        binary_expr,
        field_name,
        fixed_specs,
        var_fields,
        groups,
        endian,
        module
      ) do
    case field_name do
      # Literal atom - inline the binary pattern
      name when is_atom(name) ->
        cond do
          Map.has_key?(fixed_specs, name) ->
            {type_module, offset} = Map.get(fixed_specs, name)
            # Use the binary_expr directly in the pattern if it's a simple var
            # Otherwise bind it first
            getter_body = type_module.getter_ast(offset, endian, binary_expr)

            # Check if binary_expr is already a simple variable
            case binary_expr do
              {var_name, _, context} when is_atom(var_name) and is_atom(context) ->
                # Simple variable - use directly
                getter_body

              _ ->
                # Complex expression - bind to temp var first
                temp_var = Macro.var(:__binary__, __MODULE__)
                temp_body = type_module.getter_ast(offset, endian, temp_var)

                quote do
                  unquote(temp_var) = unquote(binary_expr)
                  unquote(temp_body)
                end
            end

          name in var_fields ->
            quote do
              raise ArgumentError,
                    "variable-length field #{inspect(unquote(name))} requires full decode"
            end

          name in groups ->
            quote do
              raise ArgumentError,
                    "group #{inspect(unquote(name))} requires full decode"
            end

          true ->
            quote do
              raise ArgumentError,
                    "unknown field: #{inspect(unquote(name))}"
            end
        end

      # Variable or expression - fall back to function
      _ ->
        quote do
          unquote(module).get(unquote(binary_expr), unquote(field_name))
        end
    end
  end

  defp generate_compare_macro(fixed_fields, var_fields, groups, field_offsets, endian) do
    header_size = 8

    fixed_field_specs =
      Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
        payload_offset = Map.get(field_offsets, name)
        framed_offset = payload_offset + header_size
        {name, {module, framed_offset, endian}}
      end)
      |> Map.new()

    payload_field_specs =
      Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
        offset = Map.get(field_offsets, name)
        {name, {module, offset, endian}}
      end)
      |> Map.new()

    var_field_names = Enum.map(var_fields, fn {name, _, _, _} -> name end)
    group_names = Enum.map(groups, fn {name, _, _} -> name end)

    quote do
      @doc """
      Compares a field from a binary against a value or another binary.

      Supports only fixed-size fields. Variable fields and groups require full decode.

      ## Options

      - `:header` - Binary includes header (default: `true`)
      - `:rhs` - `:value` (default) or `:binary` to compare against same field in rhs binary

      ## Examples

          require #{inspect(__MODULE__)}

          #{inspect(__MODULE__)}.compare(binary, :price, :>, 100)
          #{inspect(__MODULE__)}.compare(binary_a, :price, :<=, binary_b, rhs: :binary)
      """
      defmacro compare(binary_expr, field_name, op, rhs_expr, opts \\ []) do
        fixed_specs =
          if Keyword.get(opts, :header, true) do
            unquote(Macro.escape(fixed_field_specs))
          else
            unquote(Macro.escape(payload_field_specs))
          end

        var_fields = unquote(var_field_names)
        groups = unquote(group_names)

        GridCodec.Struct.Compiler.__build_inline_compare__(
          binary_expr,
          field_name,
          op,
          rhs_expr,
          opts,
          fixed_specs,
          var_fields,
          groups
        )
      end
    end
  end

  @doc false
  def __build_inline_compare__(
        binary_expr,
        field_name,
        op,
        rhs_expr,
        opts,
        fixed_specs,
        var_fields,
        groups
      ) do
    case field_name do
      name when is_atom(name) ->
        cond do
          Map.has_key?(fixed_specs, name) ->
            {type_module, offset, endian} = Map.get(fixed_specs, name)
            rhs_mode = Keyword.get(opts, :rhs, :value)

            lhs_binary_var = Macro.var(:__lhs_binary__, __MODULE__)
            rhs_expr_var = Macro.var(:__rhs_expr__, __MODULE__)
            lhs_value_var = Macro.var(:__lhs_value__, __MODULE__)
            rhs_value_var = Macro.var(:__rhs_value__, __MODULE__)

            rhs_value_ast =
              if rhs_mode == :binary do
                quote do
                  unless is_binary(unquote(rhs_expr_var)) do
                    raise ArgumentError,
                          "compare with rhs: :binary expects rhs to be a binary"
                  end

                  unquote(type_module).get_value(
                    unquote(rhs_expr_var),
                    unquote(offset),
                    unquote(endian)
                  )
                end
              else
                rhs_expr_var
              end

            quote do
              unquote(lhs_binary_var) = unquote(binary_expr)
              unquote(rhs_expr_var) = unquote(rhs_expr)

              unquote(lhs_value_var) =
                unquote(type_module).get_value(
                  unquote(lhs_binary_var),
                  unquote(offset),
                  unquote(endian)
                )

              unquote(rhs_value_var) = unquote(rhs_value_ast)

              GridCodec.compare_values(
                unquote(type_module),
                unquote(lhs_value_var),
                unquote(op),
                unquote(rhs_value_var)
              )
            end

          name in var_fields ->
            quote do
              raise ArgumentError,
                    "variable-length field #{inspect(unquote(name))} requires full decode"
            end

          name in groups ->
            quote do
              raise ArgumentError,
                    "group #{inspect(unquote(name))} requires full decode"
            end

          true ->
            quote do
              raise ArgumentError, "unknown field: #{inspect(unquote(name))}"
            end
        end

      _ ->
        raise CompileError,
          description:
            "compare/5 requires a literal atom field name for compile-time specialization"
    end
  end

  # ============================================================================
  # Pattern Matching Macro Generation
  # ============================================================================
  #
  # IMPORTANT: The match macro returns RAW binary values, not decoded values.
  # For nullable fields, this means sentinel values are returned, NOT nil.
  #
  # Current behavior:
  # - Literal `nil` in patterns is rewritten to the field's null sentinel bytes
  #
  # Future improvements (requires Elixir 1.17+ gradual typing):
  # - Type annotations that would make `is_nil(value)` emit a warning
  # - The matched values are never nil, so `is_nil(value)` is always false
  #
  # For null-safe access, users should use get/2 instead.
  # ============================================================================

  defp generate_match_macro(fixed_fields, field_offsets, block_length, endian) do
    field_info =
      Enum.map(fixed_fields, fn {name, type_atom, module, _opts} ->
        offset = Map.get(field_offsets, name)
        size = module.size()
        {name, type_atom, module, offset, size}
      end)

    quote do
      @doc """
      Pattern matching macro for binary data.

      By default, expects a framed binary (with header from `encode/1`).
      Use `header: false` option for payload-only binaries.

      ## ⚠️  Important: Raw Values

      **The `match` macro extracts raw binary values, NOT decoded values.**

      For nullable fields, the raw sentinel value is returned instead of `nil`:
      - For unsigned integers: all 1s (e.g., `0xFFFFFFFF` for u32)
      - For signed integers: minimum value (e.g., `-9223372036854775808` for i64)
      - For UUIDs: all zeros (`<<0::128>>`)

      If you need null-aware access, use `get/2` instead:

          # get/2 returns nil for null fields
          price = #{inspect(__MODULE__)}.get(binary, :price)  # nil if null

          # match/1 returns sentinel value for null fields
          case binary do
            #{inspect(__MODULE__)}.match(price: p) -> p  # 0xFFFFFFFFFFFFFFFF if null!
          end

      Literal `nil` in patterns is rewritten at compile time to the field's
      null sentinel representation:

          # Matches when price is encoded as null sentinel
          #{inspect(__MODULE__)}.match(price: nil)

      ## Examples

          require #{inspect(__MODULE__)}

          # Framed binary (default) - works with encode/1
          case binary do
            #{inspect(__MODULE__)}.match(id: id) when id > 100 ->
              {:high, id}
            _ ->
              :other
          end

          # Payload only - works with encode(struct, header: false)
          case payload do
            #{inspect(__MODULE__)}.match([id: id], header: false) ->
              {:found, id}
          end
      """
      defmacro match(field_bindings \\ [], opts \\ []) do
        field_info = unquote(Macro.escape(field_info))
        block_length = unquote(block_length)
        endian = unquote(endian)
        has_header = Keyword.get(opts, :header, true)

        GridCodec.Struct.Compiler.__build_match_pattern__(
          field_bindings,
          field_info,
          block_length,
          endian,
          has_header
        )
      end

      @doc """
      Encodes an Elixir value to its binary field representation.

      Use this to pre-encode values for pinning in match patterns on
      custom types (decimal, etc.) where the Elixir value differs from
      the binary encoding.

          require #{inspect(__MODULE__)}

          encoded = #{inspect(__MODULE__)}.encode_field(:price, Decimal.new("123.45"))
          case binary do
            #{inspect(__MODULE__)}.match(price: ^encoded) -> :found
            _ -> :not_found
          end
      """
      defmacro encode_field(field_name, value) do
        field_info = unquote(Macro.escape(field_info))

        GridCodec.Struct.Compiler.__build_encode_field__(field_name, value, field_info)
      end
    end
  end

  @doc false
  def __build_encode_field__(field_name, value, field_info) do
    case Enum.find(field_info, fn {name, _, _, _, _} -> name == field_name end) do
      nil ->
        raise ArgumentError, "unknown field: #{inspect(field_name)}"

      {_name, _type_atom, type_module, _offset, size} ->
        if function_exported?(type_module, :encode_value, 1) do
          quote do: unquote(type_module).encode_value(unquote(value))
        else
          quote do
            value = unquote(value)

            case unquote(size) do
              1 -> <<value::8>>
              2 -> <<value::little-16>>
              4 -> <<value::little-32>>
              8 -> <<value::little-64>>
              n -> <<value::binary-size(n)>>
            end
          end
        end
    end
  end

  @doc false
  def __build_match_pattern__(
        field_bindings,
        field_info,
        _block_length,
        endian,
        has_header \\ true
      ) do
    requested_fields = Keyword.keys(field_bindings)
    available_fields = Enum.map(field_info, fn {name, _, _, _, _} -> name end)

    unknown = requested_fields -- available_fields

    if unknown != [] do
      raise ArgumentError,
            "unknown or non-matchable fields: #{inspect(unknown)}. " <>
              "Available fixed fields: #{inspect(available_fields)}"
    end

    # Header offset: 8 bytes for framed binaries, 0 for payload-only
    header_offset = if has_header, do: 8, else: 0

    # OPTIMIZATION: Only iterate requested fields, not all fields
    # This coalesces consecutive unrequested fields into single skip segments
    requested_fields =
      field_info
      |> Enum.filter(fn {name, _, _, _, _} -> Keyword.has_key?(field_bindings, name) end)
      |> Enum.sort_by(fn {_, _, _, offset, _} -> offset end)

    {segments, _} =
      Enum.reduce(requested_fields, {[], 0}, fn {name, type_atom, type_module, offset, size},
                                                {segs, current_pos} ->
        # Add header offset to all field offsets
        adjusted_offset = offset + header_offset

        # Add single coalesced skip segment if there's a gap
        segs =
          if adjusted_offset > current_pos do
            skip_size = adjusted_offset - current_pos
            skip_seg = quote do: _ :: binary - size(unquote(skip_size))
            segs ++ [skip_seg]
          else
            segs
          end

        # Add binding or literal pattern for the requested field
        value = Keyword.fetch!(field_bindings, name)
        seg = build_typed_pattern(value, type_atom, type_module, size, endian)

        {segs ++ [seg], adjusted_offset + size}
      end)

    final_segments = segments ++ [quote(do: _ :: binary)]

    quote do
      <<unquote_splicing(final_segments)>>
    end
  end

  defp build_typed_pattern(value, type_atom, type_module, size, endian) do
    # If value is a compile-time literal, encode it and embed directly in the pattern.
    # If value is a pin (^var), pass through for primitive types or auto-encode for
    # custom types (decimal, etc.) that need conversion from Elixir values to binary.
    # If value is a variable, generate a binding pattern.
    #
    # Examples:
    #   match([is_authenticated: true])  -> <<..., 1::8, ...>>
    #   match([status: :active])         -> <<..., 0::8, ...>>   (enum at compile time)
    #   match([amount: 5000])            -> <<..., 5000::little-64, ...>>
    #   match([id: var])                 -> <<..., var::binary-16, ...>>
    #   match([status: ^s])              -> <<..., ^s::8, ...>>  (pin, primitive)
    #   match([price: ^p])               -> <<..., ^(Decimal.encode_value(p))::binary-9, ...>>
    #
    case value do
      {:^, _, [_inner]} ->
        build_binding_pattern(value, size, endian)

      _ ->
        case encode_literal_for_pattern(value, type_atom, type_module, endian) do
          {:ok, encoded} ->
            build_literal_pattern(encoded, size, endian)

          :not_literal ->
            build_binding_pattern(value, size, endian)
        end
    end
  end

  # Try to encode a literal value at compile time for pattern embedding
  defp encode_literal_for_pattern(value, type_atom, type_module, endian) do
    cond do
      # Nil literal -> encode field null sentinel bytes at compile time
      value == nil ->
        {:ok, null_binary_for_type(type_module, endian)}

      # Already an integer literal
      is_integer(value) ->
        {:ok, value}

      # Boolean literals -> encode as 1/0
      value == true ->
        {:ok, 1}

      value == false ->
        {:ok, 0}

      # Atom literal (could be enum value)
      is_atom(value) and not is_nil(value) ->
        encode_atom_for_pattern(value, type_atom, type_module)

      # Binary literal (for UUID, etc.)
      is_binary(value) ->
        {:ok, value}

      # Not a literal (probably a variable AST node)
      true ->
        :not_literal
    end
  end

  # Encode atom value using type module if it's an enum
  defp encode_atom_for_pattern(value, _type_atom, type_module) do
    # Check if the type module is an enum with to_integer/1
    if function_exported?(type_module, :to_integer, 1) do
      try do
        {:ok, type_module.to_integer(value)}
      rescue
        ArgumentError -> :not_literal
      end
    else
      :not_literal
    end
  end

  # Generate pattern with literal value embedded (zero-copy match)
  defp build_literal_pattern(value, size, endian) when is_integer(value) do
    case {size, endian} do
      {1, _} -> quote do: unquote(value) :: 8
      {2, :little} -> quote do: unquote(value) :: little - 16
      {2, :big} -> quote do: unquote(value) :: big - 16
      {4, :little} -> quote do: unquote(value) :: little - 32
      {4, :big} -> quote do: unquote(value) :: big - 32
      {8, :little} -> quote do: unquote(value) :: little - 64
      {8, :big} -> quote do: unquote(value) :: big - 64
      {16, _} -> quote do: unquote(value) :: binary - size(16)
      {_, _} -> quote do: unquote(value) :: binary - size(unquote(size))
    end
  end

  # For binary literals (UUID, etc.)
  defp build_literal_pattern(value, size, _endian) when is_binary(value) do
    if byte_size(value) == size do
      quote do: unquote(value)
    else
      raise ArgumentError,
            "Binary literal size #{byte_size(value)} doesn't match field size #{size}"
    end
  end

  # Generate pattern with variable binding (for extraction)
  defp build_binding_pattern(var, size, endian) do
    case {size, endian} do
      {1, _} -> quote do: unquote(var) :: 8
      {2, :little} -> quote do: unquote(var) :: little - 16
      {2, :big} -> quote do: unquote(var) :: big - 16
      {4, :little} -> quote do: unquote(var) :: little - 32
      {4, :big} -> quote do: unquote(var) :: big - 32
      {8, :little} -> quote do: unquote(var) :: little - 64
      {8, :big} -> quote do: unquote(var) :: big - 64
      {16, _} -> quote do: unquote(var) :: binary - size(16)
      {_, _} -> quote do: unquote(var) :: binary - size(unquote(size))
    end
  end

  # ============================================================================
  # Field Spec Macro Generation
  # ============================================================================

  defp generate_field_macro(fixed_fields, var_fields, groups, field_offsets, endian) do
    # Header size for framed binaries
    header_size = 8

    # Build field specs map: %{field_name => {type_module, offset, endian} | {:variable, name}}
    # Offsets include header_size since encode/1 includes header by default
    fixed_specs =
      Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
        payload_offset = Map.get(field_offsets, name)
        framed_offset = payload_offset + header_size
        {name, {module, framed_offset, endian}}
      end)

    var_specs =
      Enum.map(var_fields, fn {name, _type, _module, _opts} ->
        {name, {:variable, name}}
      end)

    group_specs =
      Enum.map(groups, fn {name, _block, _opts} ->
        {name, {:group, name}}
      end)

    all_specs = Map.new(fixed_specs ++ var_specs ++ group_specs)

    quote do
      @doc false
      def __field_specs__(opts \\ []) do
        fixed =
          if Keyword.get(opts, :header, true) do
            unquote(Macro.escape(Map.new(fixed_specs)))
          else
            unquote(
              Macro.escape(
                Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
                  payload_offset = Map.get(field_offsets, name)
                  {name, {module, payload_offset, endian}}
                end)
                |> Map.new()
              )
            )
          end

        var = unquote(Macro.escape(Map.new(var_specs)))
        grp = unquote(Macro.escape(Map.new(group_specs)))
        Map.merge(fixed, Map.merge(var, grp))
      end

      @doc """
      Returns a field spec for use with `GridCodec.get/2`.

      The macro expands at compile time to a tuple containing the type module,
      offset, and endianness. This enables efficient field access:

          value = GridCodec.get(binary, #{inspect(__MODULE__)}.field(:field_name))

      For fixed-size fields, returns `{type_module, offset, endian}`.
      For variable-length fields, returns `{:variable, field_name}`.
      For groups, returns `{:group, group_name}`.
      """
      defmacro field(name) do
        specs = unquote(Macro.escape(all_specs))

        case Map.get(specs, name) do
          nil ->
            raise ArgumentError,
                  "Unknown field #{inspect(name)}. Available: #{inspect(Map.keys(specs))}"

          spec ->
            Macro.escape(spec)
        end
      end
    end
  end

  # ============================================================================
  # Encode/Decode API Generation (extracted to reduce __before_compile__ complexity)
  # ============================================================================

  defp generate_encode_api(module, type_name, schema_id, template_id, telemetry?, min_duration) do
    telemetry_meta = %{
      module: module,
      type_name: type_name,
      schema_id: schema_id,
      template_id: template_id
    }

    if telemetry? do
      quote do
        @doc """
        Encodes a struct to binary.

        Emits `[:grid_codec, :encode]` telemetry event with duration and byte size.
        #{if unquote(min_duration) > 0, do: "Events with duration below #{unquote(min_duration)} native time units are skipped.", else: ""}

        ## Options

        - `:header` - Include header (default: `true`)
        """
        def encode(struct, opts \\ [])

        def encode(%unquote(module){} = struct, []) do
          __validate__(struct)
          start = :erlang.monotonic_time()
          payload = encode_payload(struct)
          binary = <<@__gridcodec_header__::binary, payload::binary>>
          duration = :erlang.monotonic_time() - start

          if duration >= unquote(min_duration) do
            :telemetry.execute(
              [:grid_codec, :encode],
              %{duration: duration, bytes: byte_size(binary)},
              unquote(Macro.escape(telemetry_meta))
            )
          end

          binary
        end

        def encode(%unquote(module){} = struct, opts) do
          __validate__(struct)
          start = :erlang.monotonic_time()

          binary =
            if Keyword.get(opts, :header, true) do
              payload = encode_payload(struct)
              <<@__gridcodec_header__::binary, payload::binary>>
            else
              encode_payload(struct)
            end

          duration = :erlang.monotonic_time() - start

          if duration >= unquote(min_duration) do
            :telemetry.execute(
              [:grid_codec, :encode],
              %{duration: duration, bytes: byte_size(binary)},
              unquote(Macro.escape(telemetry_meta))
            )
          end

          binary
        end
      end
    else
      quote do
        @doc """
        Encodes a struct to binary.

        ## Options

        - `:header` - Include header (default: `true`)
        """
        def encode(struct, opts \\ [])

        def encode(%unquote(module){} = struct, []) do
          __validate__(struct)
          payload = encode_payload(struct)
          <<@__gridcodec_header__::binary, payload::binary>>
        end

        def encode(%unquote(module){} = struct, opts) do
          __validate__(struct)

          if Keyword.get(opts, :header, true) do
            payload = encode_payload(struct)
            <<@__gridcodec_header__::binary, payload::binary>>
          else
            encode_payload(struct)
          end
        end
      end
    end
  end

  defp generate_decode_api(module, type_name, schema_id, template_id, telemetry?, min_duration) do
    telemetry_meta = %{
      module: module,
      type_name: type_name,
      schema_id: schema_id,
      template_id: template_id
    }

    if telemetry? do
      quote do
        @doc """
        Decodes binary to a struct.

        Emits `[:grid_codec, :decode]` telemetry event with duration and byte size.
        #{if unquote(min_duration) > 0, do: "Events with duration below #{unquote(min_duration)} native time units are skipped.", else: ""}

        ## Options

        - `:header` - Expect header (default: `true`)
        """
        def decode(binary, opts \\ [])

        def decode(binary, []) when is_binary(binary) do
          start = :erlang.monotonic_time()

          result =
            case GridCodec.Header.decode(binary) do
              {:ok, header, payload} ->
                with :ok <- validate_header(header) do
                  decode_versioned_payload(payload, header.block_length)
                end

              {:error, _} = error ->
                error
            end

          duration = :erlang.monotonic_time() - start

          if duration >= unquote(min_duration) do
            :telemetry.execute(
              [:grid_codec, :decode],
              %{duration: duration, bytes: byte_size(binary)},
              unquote(Macro.escape(telemetry_meta))
            )
          end

          result
        end

        def decode(binary, opts) when is_binary(binary) do
          start = :erlang.monotonic_time()

          result =
            if Keyword.get(opts, :header, true) do
              case GridCodec.Header.decode(binary) do
                {:ok, header, payload} ->
                  with :ok <- validate_header(header) do
                    decode_versioned_payload(payload, header.block_length)
                  end

                {:error, _} = error ->
                  error
              end
            else
              decode_payload(binary)
            end

          duration = :erlang.monotonic_time() - start

          if duration >= unquote(min_duration) do
            :telemetry.execute(
              [:grid_codec, :decode],
              %{duration: duration, bytes: byte_size(binary)},
              unquote(Macro.escape(telemetry_meta))
            )
          end

          result
        end
      end
    else
      quote do
        @doc """
        Decodes binary to a struct.

        ## Options

        - `:header` - Expect header (default: `true`)
        """
        def decode(binary, opts \\ [])

        def decode(binary, []) when is_binary(binary) do
          case GridCodec.Header.decode(binary) do
            {:ok, header, payload} ->
              with :ok <- validate_header(header) do
                decode_versioned_payload(payload, header.block_length)
              end

            {:error, _} = error ->
              error
          end
        end

        def decode(binary, opts) when is_binary(binary) do
          if Keyword.get(opts, :header, true) do
            case GridCodec.Header.decode(binary) do
              {:ok, header, payload} ->
                with :ok <- validate_header(header) do
                  decode_versioned_payload(payload, header.block_length)
                end

              {:error, _} = error ->
                error
            end
          else
            decode_payload(binary)
          end
        end
      end
    end
  end

  # ============================================================================
  # Field Validation Generation
  # ============================================================================

  defp generate_validate_fn(_fields, _groups, false, _module) do
    quote do
      defp __validate__(_struct), do: :ok
    end
  end

  defp generate_validate_fn(fields, _groups, true, module) do
    checks =
      fields
      |> Enum.reject(fn {_, _, _, opts} -> Keyword.get(opts, :presence) == :constant end)
      |> Enum.flat_map(fn {name, _type_atom, type_module, _opts} ->
        if function_exported?(type_module, :validate_ast, 3) do
          var = quote do: :maps.get(unquote(name), data, nil)
          ast = type_module.validate_ast(var, name, module)
          if ast, do: [ast], else: []
        else
          []
        end
      end)

    if checks == [] do
      quote do
        defp __validate__(_struct), do: :ok
      end
    else
      quote do
        defp __validate__(data) when is_map(data) do
          unquote_splicing(checks)
          :ok
        end
      end
    end
  end

  # ============================================================================
  # Cast / Coercion Generation
  # ============================================================================

  defp generate_cast_fn(fields, groups, module) do
    non_constant =
      Enum.reject(fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :constant
      end)

    field_coercions =
      Enum.map(non_constant, fn {name, type_atom, type_module, _opts} ->
        name_str = Atom.to_string(name)

        coerce_ast =
          if function_exported?(type_module, :coerce_ast, 1) do
            var = Macro.var(:raw_value, __MODULE__)
            type_module.coerce_ast(var)
          else
            nil
          end

        {name, name_str, type_atom, coerce_ast}
      end)

    group_coercions = build_group_coercions(groups, module)

    quote do
      defp __cast__(attrs) when is_map(attrs) do
        unquote(build_cast_body(field_coercions, group_coercions, module))
      end
    end
  end

  defp build_group_coercions(groups, module) do
    Enum.flat_map(groups, fn {name, _block, opts} ->
      group_fields = Keyword.get(opts, :__resolved_fields__)

      if group_fields && group_fields != [] do
        entry_coercions =
          Enum.map(group_fields, fn {fname, ftype_atom, ftype_module, _fopts} ->
            fname_str = Atom.to_string(fname)

            coerce =
              if function_exported?(ftype_module, :coerce_ast, 1) do
                var = Macro.var(:__entry_val__, __MODULE__)
                ftype_module.coerce_ast(var)
              else
                nil
              end

            {fname, fname_str, ftype_atom, coerce}
          end)

        [{name, Atom.to_string(name), entry_coercions}]
      else
        []
      end
    end)
  end

  defp build_cast_body(field_coercions, group_coercions, module) do
    field_extractions =
      Enum.map(field_coercions, fn {name, name_str, type_atom, coerce_ast} ->
        # Pattern-match for atom key first, fall back to string key only on miss.
        # Avoids eager evaluation of both Map.get calls.
        extract =
          quote do
            raw_value =
              case :maps.find(unquote(name), attrs) do
                {:ok, v} -> v
                :error -> Map.get(attrs, unquote(name_str))
              end
          end

        coerce =
          if coerce_ast do
            var = Macro.var(:raw_value, __MODULE__)

            quote do
              _ = unquote(var)

              case unquote(coerce_ast) do
                {:ok, coerced} ->
                  coerced

                {:error, reason} ->
                  throw(
                    GridCodec.ValidationError.cast_error(
                      unquote(module),
                      unquote(name),
                      unquote(type_atom),
                      raw_value,
                      reason
                    )
                  )
              end
            end
          else
            quote do: raw_value
          end

        {name, extract, coerce}
      end)

    extractions =
      Enum.map(field_extractions, fn {name, extract, coerce} ->
        field_var = Macro.var(:"__cast_#{name}__", __MODULE__)

        quote do
          unquote(extract)
          unquote(field_var) = unquote(coerce)
        end
      end)

    group_extractions =
      Enum.map(group_coercions, fn {name, name_str, entry_coercions} ->
        field_var = Macro.var(:"__cast_#{name}__", __MODULE__)

        entry_cast = build_entry_cast_ast(entry_coercions, name, module)

        quote do
          unquote(field_var) =
            case :maps.find(unquote(name), attrs) do
              {:ok, entries} when is_list(entries) ->
                Enum.map(entries, fn entry -> unquote(entry_cast) end)

              {:ok, nil} ->
                []

              :error ->
                case Map.get(attrs, unquote(name_str)) do
                  entries when is_list(entries) ->
                    Enum.map(entries, fn entry -> unquote(entry_cast) end)

                  _ ->
                    []
                end
            end
        end
      end)

    field_pairs =
      Enum.map(field_extractions, fn {name, _, _} ->
        {name, Macro.var(:"__cast_#{name}__", __MODULE__)}
      end)

    group_pairs =
      Enum.map(group_coercions, fn {name, _, _} ->
        {name, Macro.var(:"__cast_#{name}__", __MODULE__)}
      end)

    struct_pairs = field_pairs ++ group_pairs

    quote do
      try do
        unquote_splicing(extractions)
        unquote_splicing(group_extractions)
        {:ok, %{unquote_splicing(struct_pairs)}}
      catch
        %GridCodec.ValidationError{} = e -> {:error, e}
      end
    end
  end

  defp build_entry_cast_ast(entry_coercions, group_name, module) do
    field_steps =
      Enum.map(entry_coercions, fn {fname, fname_str, ftype_atom, coerce_ast} ->
        extract =
          quote do
            __entry_val__ =
              case :maps.find(unquote(fname), entry) do
                {:ok, v} -> v
                :error -> Map.get(entry, unquote(fname_str))
              end
          end

        coerced =
          if coerce_ast do
            quote do
              _ = __entry_val__

              case unquote(coerce_ast) do
                {:ok, v} ->
                  v

                {:error, reason} ->
                  throw(
                    GridCodec.ValidationError.cast_error(
                      unquote(module),
                      unquote(fname),
                      unquote(ftype_atom),
                      __entry_val__,
                      "in group #{unquote(group_name)}: " <> reason
                    )
                  )
              end
            end
          else
            quote do: __entry_val__
          end

        {fname, extract, coerced}
      end)

    steps =
      Enum.map(field_steps, fn {fname, extract, coerced} ->
        var = Macro.var(:"__ef_#{fname}__", __MODULE__)

        quote do
          unquote(extract)
          unquote(var) = unquote(coerced)
        end
      end)

    pairs =
      Enum.map(field_steps, fn {fname, _, _} ->
        {fname, Macro.var(:"__ef_#{fname}__", __MODULE__)}
      end)

    quote do
      (fn ->
         unquote_splicing(steps)
         %{unquote_splicing(pairs)}
       end).()
    end
  end

  # ============================================================================
  # Content Hash Generation
  # ============================================================================

  defp generate_decode_only_fn(
         fixed_fields,
         field_offsets,
         endian,
         module,
         generate_typespec,
         _block_length
       ) do
    payload_var = Macro.var(:__payload__, __MODULE__)

    field_clauses =
      fixed_fields
      |> Enum.map(fn {name, _type_atom, type_module, _opts} ->
        offset = Map.get(field_offsets, name)

        if offset && function_exported?(type_module, :getter_ast, 3) do
          getter = type_module.getter_ast(offset, endian, payload_var)
          {:->, [], [[name], getter]}
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    fallback = {:->, [], [[Macro.var(:_, nil)], nil]}
    all_clauses = field_clauses ++ [fallback]

    quote do
      @doc """
      Decodes only the requested fields from a binary, skipping all others.

      Uses compile-time field offsets for O(1) per-field extraction.
      Fields not in the codec are silently ignored.

      ## Example

          {:ok, view} = #{inspect(unquote(module))}.decode_only(binary, [:price, :side])
          view.price  # decoded
      """
      if unquote(generate_typespec) do
        @spec decode_only(binary(), [atom()]) :: {:ok, map()} | {:error, term()}
      end

      def decode_only(binary, fields) when is_binary(binary) and is_list(fields) do
        case GridCodec.Header.decode(binary) do
          {:ok, _header, unquote(payload_var)} ->
            result =
              Map.new(fields, fn field ->
                value = unquote({:case, [], [quote(do: field), [do: all_clauses]]})
                {field, value}
              end)

            {:ok, result}

          {:error, _} = error ->
            error
        end
      end
    end
  end

  defp generate_content_hash_fn(module, generate_typespec) do
    quote do
      @doc """
      Returns a deterministic SHA-256 hash of the struct's wire representation.

      Two structs with identical field values always produce the same hash,
      regardless of map key ordering or Decimal representation. Useful for
      deduplication, idempotency checks, and event fingerprinting.

      ## Example

          hash = #{inspect(unquote(module))}.content_hash(struct)
          # => <<32 bytes>>
      """
      if unquote(generate_typespec) do
        @spec content_hash(t()) :: <<_::256>>
      end

      def content_hash(%unquote(module){} = struct) do
        payload = encode_payload(struct)
        :crypto.hash(:sha256, payload)
      end
    end
  end
end
