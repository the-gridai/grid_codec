defmodule GridCodec.Transcoder do
  @moduledoc """
  Compile-time codec-to-codec transcoding without intermediate struct.

  Generates efficient functions that read fields from a source GridCodec binary
  at compile-time known offsets and pass them directly to a target encoder,
  skipping the full decode → struct → re-encode cycle.

  ## Usage

      defmodule SpanTranscoder do
        use GridCodec.Transcoder,
          source: MyApp.BinaryTraceContext,
          target: MyApp.ProtoTarget

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

  ## Target module

  The target module must implement `encode/1` accepting a map of field values:

      defmodule MyApp.ProtoTarget do
        def encode(fields) when is_map(fields) do
          # Convert field map to the target wire format
          {:ok, proto_binary}
        end
      end

  ## How it works

  At compile time, `use GridCodec.Transcoder` resolves field offsets from the
  source codec and generates a `transcode/1` function that:

  1. Extracts each mapped field from the binary at its known offset (O(1) each)
  2. Applies any field-level transforms
  3. Builds the output field map
  4. Passes it to the target module's `encode/1`

  No intermediate struct is created. The source binary is never fully decoded.
  """

  defmacro __using__(opts) do
    source = Keyword.fetch!(opts, :source)
    target = Keyword.fetch!(opts, :target)

    quote do
      import GridCodec.Transcoder, only: [field: 1, field: 2]

      Module.register_attribute(__MODULE__, :__tc_mappings__, accumulate: true)

      @__tc_source__ unquote(source)
      @__tc_target__ unquote(target)

      @before_compile GridCodec.Transcoder
    end
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
      field :span_id, transform: &<<&1::64>>  # u64 → bytes
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

    quote do
      @doc """
      Transcodes a source binary to the target format
      without intermediate struct creation.
      """
      def transcode(unquote(binary_var)) when is_binary(unquote(binary_var)) do
        unquote_splicing(extractions)
        unquote(target_mod).encode(unquote(field_map))
      end
    end
  end
end
