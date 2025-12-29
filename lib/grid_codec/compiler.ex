defmodule GridCodec.Compiler do
  @moduledoc false

  @doc """
  Generates the codec implementation at compile time.

  This module is invoked via `@before_compile` and generates:

  - `encode/1` - Encode a map to binary (payload only)
  - `encode!/1` - Encode with message header for dispatch/routing
  - `decode/1` - Decode binary to map (payload only)
  - `decode!/1` - Decode with message header validation
  - `wrap/1` - Wrap binary for zero-copy access
  - `get/2` - Get a field from wrapped binary
  - `__schema__/0` - Return schema metadata
  - `__template_id__/0` - Return the template ID for dispatch

  ## Wire Format (with header)

      ┌─────────────────────────────────────────────────────────┐
      │ Header (8 bytes)                                        │
      │   block_length (u16) | template_id (u16)               │
      │   schema_id (u16)    | version (u16)                   │
      ├─────────────────────────────────────────────────────────┤
      │ Fixed Block (compile-time calculated size)             │
      │   Field 1, Field 2, ... (with alignment padding)       │
      ├─────────────────────────────────────────────────────────┤
      │ Groups Section                                          │
      │   Group Header + Entries ...                           │
      ├─────────────────────────────────────────────────────────┤
      │ Var-Data Section                                        │
      │   String 1, String 2, ... (length-prefixed)            │
      └─────────────────────────────────────────────────────────┘

  ## Offset Calculation

  Field offsets are calculated at compile time with proper alignment.
  This enables O(1) field access for fixed-size types.
  """

  defmacro __before_compile__(env) do
    fields = Module.get_attribute(env.module, :gridcodec_fields) |> Enum.reverse()
    groups = Module.get_attribute(env.module, :gridcodec_groups) |> Enum.reverse()
    opts = Module.get_attribute(env.module, :gridcodec_opts) || []

    version = Keyword.get(opts, :version, 1)
    template_id = Keyword.get(opts, :template_id, 0)
    schema_id = Keyword.get(opts, :schema_id, 0)
    endian = Keyword.get(opts, :endian, :little)
    custom_types = Keyword.get(opts, :types, []) |> Enum.into(%{})
    align_fields = Keyword.get(opts, :align, false)

    # Validate since: versions at compile time
    Enum.each(fields, fn {name, _type, field_opts} ->
      since = Keyword.get(field_opts, :since, 1)

      if since > version do
        raise CompileError,
          description:
            "Field #{inspect(name)} has since: #{since} but codec version is #{version}. " <>
              "The :since version must be <= codec version."
      end
    end)

    # Separate fixed and variable-length fields
    resolved_fields = resolve_types(fields, custom_types)
    {fixed_fields, var_fields} = partition_fields(resolved_fields)

    # Calculate offsets with alignment (if enabled)
    {field_offsets, block_length} = calculate_offsets(fixed_fields, align_fields)

    # Build field version map for introspection
    field_versions =
      Enum.map(fields, fn {name, _type, field_opts} ->
        {name, Keyword.get(field_opts, :since, 1)}
      end)
      |> Map.new()

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
      field_versions: field_versions
    }

    encoder_body = generate_encoder(fixed_fields, var_fields, groups, endian)
    decoder_body = generate_decoder(fixed_fields, var_fields, groups, endian)

    # Header encoding for framed messages
    header_opts = [
      block_length: block_length,
      template_id: template_id,
      schema_id: schema_id,
      version: version
    ]

    # Generate typespec for the decoded data
    typespec = generate_typespec(fixed_fields, var_fields, groups)
    field_names = Enum.map(fields, fn {name, _, _} -> name end)

    quote do
      @typedoc """
      The decoded data type for this codec.

      Generated from the schema definition.
      """
      @type t :: unquote(typespec)

      @doc """
      Returns the codec schema metadata.
      """
      def __schema__ do
        unquote(Macro.escape(schema))
      end

      @doc """
      Returns the template ID for this codec.

      Template IDs identify message types for dispatch routing.
      """
      @spec __template_id__() :: non_neg_integer()
      def __template_id__, do: unquote(template_id)

      @doc """
      Returns the schema ID for this codec.

      Schema IDs identify the schema/application namespace.
      """
      @spec __schema_id__() :: non_neg_integer()
      def __schema_id__, do: unquote(schema_id)

      @doc """
      Returns the schema version for this codec.
      """
      @spec __version__() :: non_neg_integer()
      def __version__, do: unquote(version)

      @doc """
      Returns the fixed block length in bytes.
      """
      def block_length, do: unquote(block_length)

      @doc """
      Returns the list of field names defined in this codec.
      """
      @spec __fields__() :: [atom()]
      def __fields__, do: unquote(field_names)

      @doc """
      Returns a map of field names to the version they were added.

      Useful for schema evolution and compatibility checks.

      ## Example

          MyCodec.__field_versions__()
          #=> %{id: 1, count: 1, status: 2}
      """
      @spec __field_versions__() :: %{atom() => pos_integer()}
      def __field_versions__, do: unquote(Macro.escape(field_versions))

      @doc """
      Encodes a map into the binary format (payload only, no header).

      Use `encode!/1` to include the message header for framed messages.

      ## Example

          binary = MyCodec.encode(%{id: 123, name: "test"})
      """
      @spec encode(t()) :: binary()
      def encode(var!(data)) when is_map(var!(data)) do
        unquote(encoder_body)
      end

      @doc """
      Encodes a map into the binary format WITH message header.

      The header includes block_length, template_id, schema_id, and version.
      Use this for framed messages that need routing/dispatch.

      ## Wire Format

          ┌─────────────────────────────────────────────────┐
          │ Header (8 bytes)                                │
          │   block_length(u16) | template_id(u16)         │
          │   schema_id(u16)    | version(u16)             │
          ├─────────────────────────────────────────────────┤
          │ Payload (variable)                              │
          └─────────────────────────────────────────────────┘

      ## Example

          framed = MyCodec.encode!(%{id: 123, name: "test"})
          # Can now be dispatched via GridCodec.Dispatch.decode/2
      """
      @spec encode!(t()) :: binary()
      def encode!(data) when is_map(data) do
        header = GridCodec.Header.encode(unquote(header_opts))
        payload = encode(data)
        <<header::binary, payload::binary>>
      end

      @doc """
      Decodes a binary payload into a map (no header expected).

      Use `decode!/1` to decode framed messages with headers.

      ## Example

          {:ok, map} = MyCodec.decode(binary)
      """
      @spec decode(binary()) :: {:ok, t()} | {:error, term()}
      def decode(binary) when is_binary(binary) do
        unquote(decoder_body)
      end

      @doc """
      Decodes a framed binary WITH header validation.

      Validates that the header's template_id, schema_id match this codec,
      and that the version is compatible.

      ## Example

          {:ok, map} = MyCodec.decode!(framed_binary)
          {:error, {:version_mismatch, got, expected}} = MyCodec.decode!(old_binary)
      """
      @spec decode!(binary()) :: {:ok, t()} | {:error, term()}
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

      @doc """
      Wraps a binary for zero-copy field access.

      Returns an opaque envelope that can be passed to `get/2`.

      ## Example

          env = MyCodec.wrap(binary)
          value = MyCodec.get(env, :field_name)
      """
      @spec wrap(binary()) :: GridCodec.Envelope.t()
      def wrap(binary) when is_binary(binary) do
        GridCodec.Envelope.wrap(binary, __MODULE__)
      end

      @doc """
      Wraps a framed binary (strips header) for zero-copy field access.

      ## Example

          env = MyCodec.wrap!(framed_binary)
          value = MyCodec.get(env, :field_name)
      """
      @spec wrap!(binary()) :: GridCodec.Envelope.t() | {:error, term()}
      def wrap!(binary) when is_binary(binary) do
        case GridCodec.Header.decode(binary) do
          {:ok, _header, payload} -> wrap(payload)
          {:error, _} = error -> error
        end
      end

      @doc """
      Gets a field value from a wrapped binary without full decode.

      This uses sub-binary references for zero-copy access to fixed-size fields.

      ## Example

          env = MyCodec.wrap(binary)
          id = MyCodec.get(env, :id)
      """
      unquote(generate_getters(fixed_fields, var_fields, groups, field_offsets, endian))

      # Pattern matching macro
      unquote(generate_match_macro(fixed_fields, field_offsets, block_length, endian))
    end
  end

  # ============================================================================
  # Typespec Generation
  # ============================================================================

  defp generate_typespec(fixed_fields, var_fields, groups) do
    all_fields = fixed_fields ++ var_fields

    field_types =
      Enum.map(all_fields, fn {name, type_atom, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        elixir_type = type_to_typespec(type_atom, module, presence)
        {name, elixir_type}
      end)

    # Groups are decoded as GridCodec.Group structs
    group_types =
      Enum.map(groups, fn {name, _block, _opts} ->
        {name, quote(do: GridCodec.Group.t())}
      end)

    all_types = field_types ++ group_types

    # Build the map type: %{field1: type1, field2: type2, ...}
    quote do
      %{unquote_splicing(all_types)}
    end
  end

  # Map codec types to Elixir typespecs
  defp type_to_typespec(type_atom, module, presence) do
    base_type =
      case type_atom do
        :u8 ->
          quote(do: non_neg_integer())

        :u16 ->
          quote(do: non_neg_integer())

        :u32 ->
          quote(do: non_neg_integer())

        :u64 ->
          quote(do: non_neg_integer())

        :i8 ->
          quote(do: integer())

        :i16 ->
          quote(do: integer())

        :i32 ->
          quote(do: integer())

        :i64 ->
          quote(do: integer())

        :f32 ->
          quote(do: float())

        :f64 ->
          quote(do: float())

        :bool ->
          quote(do: boolean())

        :uuid ->
          quote(do: binary())

        :string ->
          quote(do: String.t())

        :string8 ->
          quote(do: String.t())

        :string16 ->
          quote(do: String.t())

        :string32 ->
          quote(do: String.t())

        :decimal ->
          quote(do: Decimal.t())

        :timestamp_us ->
          quote(do: DateTime.t())

        :timestamp_ns ->
          quote(do: DateTime.t())

        :enum ->
          # Check if the module has a typespec defined
          if function_exported?(module, :typespec, 0) do
            module.typespec()
          else
            quote(do: atom())
          end

        _ ->
          # For custom types, use term()
          quote(do: term())
      end

    # If presence is optional, add nil as a possible value
    case presence do
      :required -> base_type
      :constant -> base_type
      _ -> quote(do: unquote(base_type) | nil)
    end
  end

  # ============================================================================
  # Type Resolution
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
        # Apply alignment if enabled
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

  defp generate_encoder(fixed_fields, var_fields, groups, endian) do
    data_var = quote do: var!(data)

    # Generate validation for required fields
    required_validations = generate_required_validations(fixed_fields, data_var)

    # Encode fixed fields
    fixed_encoding =
      Enum.map(fixed_fields, fn {name, _type, module, opts} ->
        presence = Keyword.get(opts, :presence, :optional)
        default = Keyword.get(opts, :default)
        const_value = Keyword.get(opts, :value)
        null_value = module.null_value()

        case presence do
          :constant ->
            # Always use the constant value
            module.encode_ast(
              name,
              const_value,
              endian,
              quote(do: %{unquote(name) => unquote(const_value)})
            )

          _ ->
            # For optional fields, use null_value when nil
            # Create a data map with nil replaced by null_value
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

    # Encode groups
    group_encoding = generate_group_encoder(groups, data_var)

    # Encode variable-length fields
    var_encoding = generate_var_encoder(var_fields, data_var)

    quote do
      # Validate required fields
      unquote_splicing(required_validations)

      fixed_block = unquote(fixed_binary)
      groups_binary = unquote(group_encoding)
      var_data = unquote(var_encoding)
      <<fixed_block::binary, groups_binary::binary, var_data::binary>>
    end
  end

  defp generate_required_validations(fixed_fields, data_var) do
    fixed_fields
    |> Enum.filter(fn {_name, _type, _module, opts} ->
      Keyword.get(opts, :presence) == :required
    end)
    |> Enum.map(fn {name, _type, _module, _opts} ->
      quote do
        if Map.get(unquote(data_var), unquote(name)) == nil do
          raise ArgumentError, "required field #{unquote(inspect(name))} cannot be nil"
        end
      end
    end)
  end

  defp generate_group_encoder([], _data_var) do
    quote do: <<>>
  end

  defp generate_group_encoder(groups, data_var) do
    encodings =
      Enum.map(groups, fn {name, _block, opts} ->
        entry_encoder = Keyword.get(opts, :entry_encoder)

        if entry_encoder do
          quote do
            entries = Map.get(unquote(data_var), unquote(name), [])
            GridCodec.Group.encode(entries, unquote(entry_encoder))
          end
        else
          quote do
            # Default: expect pre-encoded binary or empty group header (4 bytes)
            Map.get(unquote(data_var), unquote(name), <<0::little-16, 0::little-16>>)
          end
        end
      end)

    quote do
      IO.iodata_to_binary([unquote_splicing(encodings)])
    end
  end

  defp generate_var_encoder([], _data_var) do
    quote do: <<>>
  end

  defp generate_var_encoder(var_fields, data_var) do
    encodings =
      Enum.map(var_fields, fn {name, _type, _module, _opts} ->
        quote do
          value = Map.get(unquote(data_var), unquote(name))
          GridCodec.Types.String.encode(value)
        end
      end)

    quote do
      IO.iodata_to_binary([unquote_splicing(encodings)])
    end
  end

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

        # For constant fields, return the constant value
        value_ast =
          case presence do
            :constant ->
              Macro.escape(const_value)

            _ ->
              # Apply value transformation if the type defines it
              if function_exported?(module, :decode_value_ast, 1) do
                module.decode_value_ast(var)
              else
                var
              end
          end

        {name, value_ast}
      end)

    # Generate group decoding
    group_decoding = generate_group_decoder(groups)

    # Generate var-data decoding
    var_decoding = generate_var_decoder(var_fields)

    if fixed_patterns == [] and groups == [] and var_fields == [] do
      # Empty codec - special case
      quote do
        if binary == <<>> do
          {:ok, %{}}
        else
          {:error, :expected_empty}
        end
      end
    else
      quote do
        case binary do
          <<unquote_splicing(fixed_patterns), rest::binary>> ->
            fixed_map = %{unquote_splicing(fixed_result_pairs)}

            # Decode groups and var-data from rest
            {groups_map, var_rest} = unquote(group_decoding)
            {var_map, _final_rest} = unquote(var_decoding)

            result =
              fixed_map
              |> Map.merge(groups_map)
              |> Map.merge(var_map)

            {:ok, result}

          _ ->
            {:error, :invalid_binary}
        end
      end
    end
  end

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
    decode_steps =
      Enum.map(var_fields, fn {name, _type, _module, _opts} ->
        name
      end)

    quote do
      Enum.reduce(
        unquote(decode_steps),
        {%{}, var_rest},
        fn name, {acc, binary} ->
          {value, rest} = GridCodec.Types.String.decode(binary)
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

      def get(_env, field) do
        raise ArgumentError, "unknown field: #{inspect(field)}"
      end
    end
  end

  defp generate_fixed_getter(name, module, offset, endian) when is_integer(offset) do
    payload_var = quote do: var!(payload)
    getter_body = module.getter_ast(offset, endian, payload_var)

    quote do
      def get(%GridCodec.Envelope{binary: var!(payload)}, unquote(name)) do
        unquote(getter_body)
      end
    end
  end

  defp generate_var_getter(name) do
    quote do
      def get(%GridCodec.Envelope{binary: _payload}, unquote(name)) do
        raise ArgumentError,
              "variable-length field #{inspect(unquote(name))} requires full decode"
      end
    end
  end

  defp generate_group_getter(name) do
    quote do
      def get(%GridCodec.Envelope{binary: _payload}, unquote(name)) do
        raise ArgumentError,
              "group field #{inspect(unquote(name))} requires full decode"
      end
    end
  end

  # ============================================================================
  # Pattern Matching Macro Generation
  # ============================================================================

  defp generate_match_macro(fixed_fields, field_offsets, block_length, endian) do
    # Build info about each fixed field for the macro
    field_info =
      Enum.map(fixed_fields, fn {name, type_atom, module, _opts} ->
        offset = Map.get(field_offsets, name)
        size = module.size()
        {name, type_atom, module, offset, size}
      end)

    quote do
      @doc """
      Pattern matching macro for binary data.

      Use this macro to pattern match on GridCodec binaries in case/cond/function heads.
      Only fixed-size fields can be matched. Variable-length fields and groups require
      full decode.

      ## Usage

      First, require the module:

          require MyCodec

      Then use in pattern matching:

          case binary do
            MyCodec.match(type: 1, id: id) when id > 100 ->
              {:high_priority, id}

            MyCodec.match(type: 2) ->
              :status_update

            _ ->
              :unknown
          end

      Or in function heads:

          def handle(MyCodec.match(type: 1, id: id)), do: {:command, id}
          def handle(MyCodec.match(type: 2, id: id)), do: {:query, id}

      ## Limitations

      - Only fixed-size fields can be matched (not strings, groups)
      - The binary must be at least `block_length()` bytes
      - Guards can reference bound variables

      ## Example with Guards

          case binary do
            MyCodec.match(score: s, level: l) when s > 1000 and l > 10 ->
              :expert

            MyCodec.match(score: s) when s > 500 ->
              :intermediate

            MyCodec.match() ->
              :beginner
          end
      """
      defmacro match(field_bindings \\ []) do
        field_info = unquote(Macro.escape(field_info))
        block_length = unquote(block_length)
        endian = unquote(endian)

        GridCodec.Compiler.__build_match_pattern__(
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
    # Validate all requested fields exist and are fixed-size
    requested_fields = Keyword.keys(field_bindings)
    available_fields = Enum.map(field_info, fn {name, _, _, _, _} -> name end)

    unknown = requested_fields -- available_fields

    if unknown != [] do
      raise ArgumentError,
            "unknown or non-matchable fields: #{inspect(unknown)}. " <>
              "Available fixed fields: #{inspect(available_fields)}"
    end

    # Sort field_info by offset
    sorted_fields = Enum.sort_by(field_info, fn {_, _, _, offset, _} -> offset end)

    # Build binary pattern segments
    {segments, _} =
      Enum.reduce(sorted_fields, {[], 0}, fn {name, _type_atom, _module, offset, size},
                                             {segs, current_pos} ->
        # Add skip segment if there's a gap
        segs =
          if offset > current_pos do
            skip_size = offset - current_pos
            skip_seg = quote do: _ :: binary - size(unquote(skip_size))
            segs ++ [skip_seg]
          else
            segs
          end

        # Check if this field is requested
        var = Keyword.get(field_bindings, name)

        seg =
          if var do
            # User wants to bind this field
            build_typed_pattern(var, size, endian)
          else
            # Skip this field
            quote do: _ :: binary - size(unquote(size))
          end

        {segs ++ [seg], offset + size}
      end)

    # Add trailing binary match for rest of message
    final_segments = segments ++ [quote(do: _ :: binary)]

    # Build the binary pattern
    quote do
      <<unquote_splicing(final_segments)>>
    end
  end

  defp build_typed_pattern(var, size, endian) do
    case {size, endian} do
      {1, _} ->
        quote do: unquote(var) :: 8

      {2, :little} ->
        quote do: unquote(var) :: little - 16

      {2, :big} ->
        quote do: unquote(var) :: big - 16

      {4, :little} ->
        quote do: unquote(var) :: little - 32

      {4, :big} ->
        quote do: unquote(var) :: big - 32

      {8, :little} ->
        quote do: unquote(var) :: little - 64

      {8, :big} ->
        quote do: unquote(var) :: big - 64

      {16, _} ->
        # UUID - match as binary
        quote do: unquote(var) :: binary - size(16)

      {_, _} ->
        # General case - match as binary
        quote do: unquote(var) :: binary - size(unquote(size))
    end
  end
end
