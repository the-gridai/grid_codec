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
    custom_types = Keyword.get(opts, :types, []) |> Enum.into(%{})
    align_fields = Keyword.get(opts, :align, false)

    # Template ID: explicit or hash of module name
    template_id =
      case Keyword.get(opts, :template_id) do
        nil -> :erlang.phash2(env.module) &&& 0xFFFF
        id -> id
      end

    # Resolve field types
    resolved_fields = resolve_types(fields, custom_types)
    {fixed_fields, var_fields} = partition_fields(resolved_fields)

    # Calculate offsets
    {field_offsets, block_length} = calculate_offsets(fixed_fields, align_fields)

    # Build struct field list with defaults
    {struct_fields, enforce_keys} = build_struct_fields(fields)

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
      field_versions: %{}
    }

    # Generate encoder/decoder AST
    encoder_clauses = generate_encoder_clauses(fixed_fields, var_fields, groups, endian)
    # Direct struct encoder - pattern matches struct fields directly, no Map.from_struct
    struct_encoder_body =
      generate_struct_encoder(fixed_fields, var_fields, groups, endian, env.module)

    # Map-based decoder (for decode_map function)
    decoder_body = generate_decoder(fixed_fields, var_fields, groups, endian)
    # Direct struct decoder - builds struct directly, avoiding map->struct conversion
    struct_decoder_body =
      generate_struct_decoder(fixed_fields, var_fields, groups, endian, env.module)

    getter_clauses = generate_getters(fixed_fields, var_fields, groups, field_offsets, endian)
    getter_macro = generate_getter_macro(fixed_fields, var_fields, groups, field_offsets, endian)
    match_macro = generate_match_macro(fixed_fields, field_offsets, block_length, endian)
    field_macro = generate_field_macro(fixed_fields, var_fields, groups, field_offsets, endian)

    # Header options for framed messages
    header_opts = [
      block_length: block_length,
      template_id: template_id,
      schema_id: schema_id,
      version: version
    ]

    module = env.module

    quote do
      # Generate @enforce_keys before defstruct
      if unquote(enforce_keys) != [] do
        @enforce_keys unquote(enforce_keys)
      end

      # Generate defstruct
      defstruct unquote(struct_fields)

      # Schema introspection
      def __schema__, do: unquote(Macro.escape(schema))
      def __template_id__, do: unquote(template_id)
      def __schema_id__, do: unquote(schema_id)
      def __version__, do: unquote(version)
      def __fields__, do: unquote(field_names)
      def block_length, do: unquote(block_length)

      # Mark this as a struct codec for registry discovery
      def __gridcodec_struct__?, do: true

      # Encode struct to binary (payload only)
      @doc """
      Encodes a struct to binary (payload only, no header).

      ## Example

          binary = #{inspect(unquote(module))}.encode(struct)
      """
      unquote(struct_encoder_body)

      # Internal encoder that works with maps (for compatibility)
      unquote(encoder_clauses)

      # Encode with header
      @doc """
      Encodes a struct to binary WITH message header (for dispatch).

      ## Example

          binary = #{inspect(unquote(module))}.encode!(struct)
      """
      def encode!(%unquote(module){} = struct) do
        header = GridCodec.Header.encode(unquote(header_opts))
        payload = encode(struct)
        <<header::binary, payload::binary>>
      end

      # Decode binary to struct (payload only)
      @doc """
      Decodes binary payload to a #{inspect(unquote(module))} struct.

      ## Example

          {:ok, %#{inspect(unquote(module))}{}} = #{inspect(unquote(module))}.decode(binary)
      """
      def decode(binary) when is_binary(binary) do
        # Direct struct decoder - avoids map->struct conversion overhead
        unquote(struct_decoder_body)
      end

      # Internal decoder that returns map (used for tests/introspection)
      @doc false
      def decode_map(binary) when is_binary(binary) do
        unquote(decoder_body)
      end

      # Decode framed binary with header validation
      @doc """
      Decodes framed binary (with header) to a #{inspect(unquote(module))} struct.

      ## Example

          {:ok, %#{inspect(unquote(module))}{}} = #{inspect(unquote(module))}.decode!(binary)
      """
      def decode!(binary) when is_binary(binary) do
        case GridCodec.Header.decode(binary) do
          {:ok, header, payload} ->
            with :ok <- validate_header(header) do
              decode(payload)
            end

          {:error, _} = error ->
            error
        end
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

      # Zero-copy wrap
      @doc """
      Wraps a binary payload for zero-copy field access.

      ## Example

          env = #{inspect(unquote(module))}.wrap(binary)
          value = #{inspect(unquote(module))}.get(env, :field_name)
      """
      def wrap(binary) when is_binary(binary) do
        GridCodec.Envelope.wrap(binary, unquote(module))
      end

      # Zero-copy getters
      unquote(getter_clauses)

      # Inline get macro (fastest - expands at compile time)
      unquote(getter_macro)

      # Pattern matching macro
      unquote(match_macro)

      # Field spec macro for GridCodec.get/2
      unquote(field_macro)
    end
  end

  # ============================================================================
  # Struct Field Generation
  # ============================================================================

  defp build_struct_fields(fields) do
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

    enforce_keys =
      fields
      |> Enum.filter(fn {_name, _type, opts} ->
        Keyword.get(opts, :presence) == :required
      end)
      |> Enum.map(fn {name, _, _} -> name end)

    {struct_fields, enforce_keys}
  end

  # ============================================================================
  # Type Resolution (from GridCodec.Compiler)
  # ============================================================================

  defp resolve_types(fields, custom_types) do
    Enum.map(fields, fn {name, type_atom, opts} ->
      case GridCodec.Type.lookup(type_atom, custom_types) do
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
    # Check if we have required field validation
    has_required =
      Enum.any?(fixed_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :required
      end)

    # We can use fast path for:
    # - No required fields (no validation needed)
    # - No groups (groups need special handling)
    # - With or without var_fields (we now handle those!)
    can_use_fast_path = not has_required and groups == []

    non_constant_fixed_fields =
      Enum.reject(fixed_fields, fn {_, _, _, opts} ->
        Keyword.get(opts, :presence) == :constant
      end)

    if can_use_fast_path and
         (not Enum.empty?(non_constant_fixed_fields) or not Enum.empty?(var_fields)) do
      # Generate struct pattern with ALL field variables (fixed + var)
      all_fields = non_constant_fixed_fields ++ var_fields

      pattern_pairs =
        for {name, _, _, _} <- all_fields do
          var = Macro.var(name, __MODULE__)
          {name, var}
        end

      struct_pattern = quote do: %unquote(struct_module){unquote_splicing(pattern_pairs)}

      # Build map with preprocessed values (nil -> default where applicable)
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

      # Generate binary parts for fixed fields
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

      # Generate var field encoding (if any)
      if var_fields == [] do
        quote do
          def encode(unquote(struct_pattern)) do
            unquote(fixed_binary_ast)
          end
        end
      else
        var_encoding_ast = generate_inline_var_encoder(var_fields)

        quote do
          def encode(unquote(struct_pattern)) do
            fixed_block = unquote(fixed_binary_ast)
            var_data = unquote(var_encoding_ast)
            <<fixed_block::binary, var_data::binary>>
          end
        end
      end
    else
      # Fall back to map-based encoding for complex codecs with groups or required fields
      quote do
        def encode(%unquote(struct_module){} = struct) do
          data = Map.from_struct(struct)
          encode_map(data)
        end
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

    required_validations = generate_required_validations(fixed_fields, data_var)

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
        entry_encoder = Keyword.get(opts, :entry_encoder)

        if entry_encoder do
          quote do
            entries = :maps.get(unquote(name), unquote(data_var), [])
            GridCodec.Group.encode(entries, unquote(entry_encoder))
          end
        else
          quote do
            :maps.get(unquote(name), unquote(data_var), <<0::little-16, 0::little-16>>)
          end
        end
      end)

    quote do
      IO.iodata_to_binary([unquote_splicing(encodings)])
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

    group_decoding = generate_group_decoder(groups)
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
            quote do
              fixed_map = %{unquote_splicing(fixed_result_pairs)}
              {groups_map, _groups_rest} = unquote(group_decoding)
              Map.merge(fixed_map, groups_map)
            end

          true ->
            quote do
              fixed_map = %{unquote_splicing(fixed_result_pairs)}
              {groups_map, var_rest} = unquote(group_decoding)
              {var_map, _final_rest} = unquote(var_decoding)

              fixed_map
              |> Map.merge(groups_map)
              |> Map.merge(var_map)
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

    group_decoding = generate_group_decoder(groups)
    var_decoding = generate_var_decoder(var_fields)

    if fixed_patterns == [] and groups == [] and var_fields == [] do
      quote do
        if binary == <<>> do
          {:ok, %unquote(struct_module){}}
        else
          {:error, :expected_empty}
        end
      end
    else
      # Generate result based on field types
      result_ast =
        cond do
          groups == [] and var_fields == [] ->
            # Most common case - build struct directly (no intermediate map!)
            quote do: %unquote(struct_module){unquote_splicing(fixed_result_pairs)}

          groups == [] ->
            # Fixed + var fields: decode var fields inline, build struct directly
            generate_inline_var_struct_decoder(fixed_result_pairs, var_fields, struct_module)

          var_fields == [] ->
            # Fixed + groups: use Enum.reduce for groups (they're complex)
            quote do
              fixed_map = %{unquote_splicing(fixed_result_pairs)}
              {groups_map, _groups_rest} = unquote(group_decoding)
              struct!(unquote(struct_module), Map.merge(fixed_map, groups_map))
            end

          true ->
            # All three: groups need Enum.reduce, but we can still optimize var fields
            quote do
              fixed_map = %{unquote_splicing(fixed_result_pairs)}
              {groups_map, var_rest} = unquote(group_decoding)
              {var_map, _final_rest} = unquote(var_decoding)

              struct!(
                unquote(struct_module),
                fixed_map |> Map.merge(groups_map) |> Map.merge(var_map)
              )
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

  defp generate_group_decoder([]) do
    quote do
      {%{}, rest}
    end
  end

  defp generate_group_decoder(groups) do
    decode_steps =
      Enum.map(groups, fn {name, _block, opts} ->
        entry_decoder = Keyword.get(opts, :entry_decoder)

        quote do
          {unquote(name),
           fn entry_binary ->
             case unquote(entry_decoder) do
               nil -> {:ok, entry_binary}
               decoder -> decoder.(entry_binary)
             end
           end}
        end
      end)

    quote do
      Enum.reduce(
        unquote(decode_steps),
        {%{}, rest},
        fn {name, decoder}, {acc, binary} ->
          case GridCodec.Group.parse(binary, decoder) do
            {:ok, group} ->
              group_rest = GridCodec.Group.rest(group)
              {Map.put(acc, name, group), group_rest}

            {:error, reason} ->
              raise "Failed to decode group #{inspect(name)}: #{inspect(reason)}"
          end
        end
      )
    end
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
  # Getter Generation
  # ============================================================================

  defp generate_getters(fixed_fields, var_fields, groups, offsets, endian) do
    fixed_clauses =
      Enum.map(fixed_fields, fn {name, _type, module, _opts} ->
        offset = Map.get(offsets, name)
        generate_fixed_getter(name, module, offset, endian)
      end)

    var_clauses =
      Enum.map(var_fields, fn {name, _type, _module, _opts} ->
        generate_var_getter(name)
      end)

    group_clauses =
      Enum.map(groups, fn {name, _block, _opts} ->
        generate_group_getter(name)
      end)

    all_clauses = fixed_clauses ++ var_clauses ++ group_clauses

    quote do
      (unquote_splicing(all_clauses))

      # Fallback for unknown fields
      def get(_binary_or_env, field) do
        raise ArgumentError, "unknown field: #{inspect(field)}"
      end
    end
  end

  defp generate_fixed_getter(name, module, offset, endian) when is_integer(offset) do
    payload_var = quote do: var!(payload)
    getter_body = module.getter_ast(offset, endian, payload_var)

    quote do
      # Direct binary getter - fastest path (no envelope overhead)
      def get(var!(payload), unquote(name)) when is_binary(var!(payload)) do
        unquote(getter_body)
      end

      # Envelope getter - for API compatibility
      def get(%GridCodec.Envelope{binary: var!(payload)}, unquote(name)) do
        unquote(getter_body)
      end
    end
  end

  defp generate_var_getter(name) do
    quote do
      def get(payload, unquote(name)) when is_binary(payload) do
        raise ArgumentError,
              "variable-length field #{inspect(unquote(name))} requires full decode"
      end

      def get(%GridCodec.Envelope{binary: _payload}, unquote(name)) do
        raise ArgumentError,
              "variable-length field #{inspect(unquote(name))} requires full decode"
      end
    end
  end

  defp generate_group_getter(name) do
    quote do
      def get(payload, unquote(name)) when is_binary(payload) do
        raise ArgumentError,
              "group field #{inspect(unquote(name))} requires full decode"
      end

      def get(%GridCodec.Envelope{binary: _payload}, unquote(name)) do
        raise ArgumentError,
              "group field #{inspect(unquote(name))} requires full decode"
      end
    end
  end

  # ============================================================================
  # Inline Getter Macro Generation
  # ============================================================================

  defp generate_getter_macro(fixed_fields, var_fields, groups, field_offsets, endian) do
    # Build a map of field_name => {module, offset} for fixed fields
    fixed_field_specs =
      Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
        offset = Map.get(field_offsets, name)
        {name, {module, offset}}
      end)
      |> Map.new()

    var_field_names = Enum.map(var_fields, fn {name, _, _, _} -> name end)
    group_names = Enum.map(groups, fn {name, _, _} -> name end)

    quote do
      @doc """
      Inline field access macro.

      When called with a literal atom field name, expands at compile time
      to direct binary pattern matching - as fast as the `match` macro.

          require #{inspect(__MODULE__)}
          value = #{inspect(__MODULE__)}.get!(binary, :price)

      If the field name is a variable, falls back to function dispatch.
      """
      defmacro get!(binary_expr, field_name) do
        fixed_specs = unquote(Macro.escape(fixed_field_specs))
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

  # ============================================================================
  # Pattern Matching Macro Generation
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

      Use this macro to pattern match on GridCodec binaries.

      ## Example

          require #{inspect(__MODULE__)}

          case binary do
            #{inspect(__MODULE__)}.match(id: id) when id > 100 ->
              {:high, id}
            _ ->
              :other
          end
      """
      defmacro match(field_bindings \\ []) do
        field_info = unquote(Macro.escape(field_info))
        block_length = unquote(block_length)
        endian = unquote(endian)

        GridCodec.Struct.Compiler.__build_match_pattern__(
          field_bindings,
          field_info,
          block_length,
          endian
        )
      end
    end
  end

  @doc false
  def __build_match_pattern__(field_bindings, field_info, _block_length, endian) do
    requested_fields = Keyword.keys(field_bindings)
    available_fields = Enum.map(field_info, fn {name, _, _, _, _} -> name end)

    unknown = requested_fields -- available_fields

    if unknown != [] do
      raise ArgumentError,
            "unknown or non-matchable fields: #{inspect(unknown)}. " <>
              "Available fixed fields: #{inspect(available_fields)}"
    end

    sorted_fields = Enum.sort_by(field_info, fn {_, _, _, offset, _} -> offset end)

    {segments, _} =
      Enum.reduce(sorted_fields, {[], 0}, fn {name, _type_atom, _module, offset, size},
                                             {segs, current_pos} ->
        segs =
          if offset > current_pos do
            skip_size = offset - current_pos
            skip_seg = quote do: _ :: binary - size(unquote(skip_size))
            segs ++ [skip_seg]
          else
            segs
          end

        var = Keyword.get(field_bindings, name)

        seg =
          if var do
            build_typed_pattern(var, size, endian)
          else
            quote do: _ :: binary - size(unquote(size))
          end

        {segs ++ [seg], offset + size}
      end)

    final_segments = segments ++ [quote(do: _ :: binary)]

    quote do
      <<unquote_splicing(final_segments)>>
    end
  end

  defp build_typed_pattern(var, size, endian) do
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
    # Build field specs map: %{field_name => {type_module, offset, endian} | {:variable, name}}
    fixed_specs =
      Enum.map(fixed_fields, fn {name, _type_atom, module, _opts} ->
        offset = Map.get(field_offsets, name)
        {name, {module, offset, endian}}
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
end
