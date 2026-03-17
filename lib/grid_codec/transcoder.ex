defmodule GridCodec.Transcoder do
  @moduledoc """
  Compile-time codec-to-codec transcoding without intermediate struct.

  Generates efficient functions that read fields from a source GridCodec binary
  at compile-time known offsets and pass them directly to a target encoder,
  skipping the full decode -> struct -> re-encode cycle.

  ## Usage

      defmodule SpanTranscoder do
        use GridCodec.Transcoder,
          source: MyApp.BinaryTraceContext,
          target: MyApp.ProtoTarget,
          validate: :target

        # 1:1 mapping (same field name, pass-through value)
        field :trace_id
        field :flags

        # Rename field
        field :start_time_ns, to: :start_time_unix_nano

        # Transform value during transcoding
        field :span_id, transform: &<<&1::64>>
      end

      SpanTranscoder.transcode(gc_binary)
      #=> {:ok, target_binary} | {:error, reason}

      SpanTranscoder.transcode(gc_binary, validate: :both)
      #=> {:ok, target_binary} | {:error, reason}

  ## Options

  Options passed to `use GridCodec.Transcoder`:

  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `source:` | `module()` | required | Source GridCodec codec used for field extraction |
  | `target:` | `module()` | required | Target module that receives the transcoded field map |
  | `validate:` | `false | true | :source | :target | :both` | `false` | Default validation mode for generated `transcode/1` calls |

  ## Target module

  The target module must implement `encode/1` accepting a map of field values:

      defmodule MyApp.ProtoTarget do
        def encode(fields) when is_map(fields) do
          # Convert field map to the target wire format
          {:ok, proto_binary}
        end
      end

  When transcoder validation is enabled with `validate: :target` or
  `validate: :both`, GridCodec prefers `target.new_binary/1` when available.
  This gives generated `GridCodec.Struct` targets a validated, no-target-struct
  fast path. Custom targets can opt into the same behavior by implementing
  `new_binary/1`.

  ## Validation modes

  Transcoders default to the raw fast path (`validate: false`). You can enable
  validation at compile time and override it per call:

      defmodule SafeSpanTranscoder do
        use GridCodec.Transcoder,
          source: MyApp.SourceSpan,
          target: MyApp.TargetSpan,
          validate: :both
      end

      SafeSpanTranscoder.transcode(binary)
      SafeSpanTranscoder.transcode(binary, validate: false)

  Supported validation modes:

  - `false` - raw fast path, no transcoder-side validation
  - `:source` - run `source.validate_binary/1` before extracting fields
  - `:target` - prefer `target.new_binary/1` for validated target encoding
  - `:both` / `true` - run source binary validation and validated target encoding

  Source validation uses the source codec's binary-capable validator subset.
  Decoded-only validators (for example callback validators and expression
  invariants over variable-width fields) are not run on the source side.

  ## How it works

  At compile time, `use GridCodec.Transcoder` resolves field offsets from the
  source codec and generates a `transcode/1` function that:

  1. Extracts each mapped field from the binary at its known offset (O(1) each)
  2. Applies any field-level transforms
  3. Builds the output field map
  4. Passes it to the target module's `encode/1` or `new_binary/1`

  No intermediate struct is created. The source binary is never fully decoded.
  """

  @type validate_mode :: false | :source | :target | :both

  defmacro __using__(opts) do
    source = Keyword.fetch!(opts, :source)
    target = Keyword.fetch!(opts, :target)
    validate = normalize_validate_mode!(Keyword.get(opts, :validate, false))

    quote do
      import GridCodec.Transcoder, only: [field: 1, field: 2]

      Module.register_attribute(__MODULE__, :__tc_mappings__, accumulate: true)

      @__tc_source__ unquote(source)
      @__tc_target__ unquote(target)
      @__tc_validate__ unquote(validate)

      @before_compile GridCodec.Transcoder
    end
  end

  @doc false
  @spec normalize_validate_mode!(boolean() | validate_mode() | nil) :: validate_mode()
  def normalize_validate_mode!(mode)

  def normalize_validate_mode!(mode) when mode in [false, :source, :target, :both], do: mode
  def normalize_validate_mode!(true), do: :both
  def normalize_validate_mode!(nil), do: false

  def normalize_validate_mode!(mode) do
    raise ArgumentError,
          "expected transcoder validate mode to be false, true, :source, :target, or :both, got: #{inspect(mode)}"
  end

  @doc """
  Maps a source field to the target output.

  ## Options

  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `to:` | `atom()` | same as source | Rename the field key in the output map |
  | `transform:` | `(term() -> term())` | identity | Apply a function to the extracted value |

  ## Examples

      field :trace_id                         # pass-through
      field :start_time_ns, to: :start_ns     # rename
      field :span_id, transform: &<<&1::64>>  # u64 -> bytes
  """
  defmacro field(name, opts \\ []) do
    transform_ast = Keyword.get(opts, :transform)
    other_opts = Keyword.delete(opts, :transform)

    quote do
      @__tc_mappings__ {unquote(name), unquote(other_opts), unquote(Macro.escape(transform_ast))}
    end
  end

  defmacro __before_compile__(env) do
    source = Module.get_attribute(env.module, :__tc_source__)
    target = Module.get_attribute(env.module, :__tc_target__)
    default_validate = Module.get_attribute(env.module, :__tc_validate__)
    mappings = Module.get_attribute(env.module, :__tc_mappings__) |> Enum.reverse()

    source_mod = Macro.expand(source, env)

    unless function_exported?(source_mod, :__match_meta__, 0) do
      raise CompileError,
        description:
          "Source #{inspect(source_mod)} does not export __match_meta__/0. " <>
            "Ensure it uses GridCodec.Struct and is compiled first."
    end

    meta = source_mod.__match_meta__()
    binary_var = Macro.var(:__tc_bin__, __MODULE__)

    extractions_and_pairs =
      for {src_name, opts, transform_ast} <- mappings do
        dst_name = Keyword.get(opts, :to, src_name)

        unless Map.has_key?(meta, src_name) do
          raise CompileError,
            description:
              "Source field #{inspect(src_name)} not found in #{inspect(source_mod)}. " <>
                "Available: #{inspect(Map.keys(meta))}"
        end

        field_meta = Map.fetch!(meta, src_name)
        wire_mod = field_meta.wire_module
        offset = field_meta.offset
        endian = field_meta.endian

        val_var = Macro.var(:"__val_#{src_name}__", __MODULE__)
        getter = wire_mod.getter_ast(offset, endian, binary_var)

        extraction =
          if transform_ast do
            quote do
              unquote(val_var) = unquote(transform_ast).(unquote(getter))
            end
          else
            quote do
              unquote(val_var) = unquote(getter)
            end
          end

        {extraction, {dst_name, val_var}}
      end

    {extractions, pairs} = Enum.unzip(extractions_and_pairs)

    field_map =
      {:%{}, [],
       Enum.map(pairs, fn {dst_name, var} ->
         {dst_name, var}
       end)}

    target_mod = Macro.expand(target, env)
    target_has_new_binary? = function_exported?(target_mod, :new_binary, 1)

    source_validation =
      quote do
        if function_exported?(unquote(source_mod), :validate_binary, 1) do
          unquote(source_mod).validate_binary(unquote(binary_var))
        else
          :ok
        end
      end

    raw_target_call =
      quote do
        unquote(target_mod).encode(unquote(field_map))
      end

    validated_target_call =
      if target_has_new_binary? do
        quote do
          unquote(target_mod).new_binary(unquote(field_map))
        end
      else
        raw_target_call
      end

    quote do
      @doc """
      Transcodes a source binary to the target format
      without intermediate struct creation.

      ## Options

      - `:validate` - override the default validation mode for this call
      """
      def transcode(unquote(binary_var)) when is_binary(unquote(binary_var)) do
        __transcode__(unquote(binary_var), unquote(default_validate))
      end

      def transcode(unquote(binary_var), opts)
          when is_binary(unquote(binary_var)) and is_list(opts) do
        validate_mode =
          GridCodec.Transcoder.normalize_validate_mode!(
            Keyword.get(opts, :validate, unquote(default_validate))
          )

        __transcode__(unquote(binary_var), validate_mode)
      end

      defp __transcode__(unquote(binary_var), false) do
        unquote_splicing(extractions)
        unquote(raw_target_call)
      end

      defp __transcode__(unquote(binary_var), :source) do
        with :ok <- unquote(source_validation) do
          unquote_splicing(extractions)
          unquote(raw_target_call)
        end
      end

      defp __transcode__(unquote(binary_var), :target) do
        unquote_splicing(extractions)
        unquote(validated_target_call)
      end

      defp __transcode__(unquote(binary_var), :both) do
        with :ok <- unquote(source_validation) do
          unquote_splicing(extractions)
          unquote(validated_target_call)
        end
      end
    end
  end
end
