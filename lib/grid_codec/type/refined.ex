defmodule GridCodec.Type.Refined do
  @moduledoc """
  Helper for defining refinement-style custom types on top of an existing GridCodec type.

  A refined type delegates binary layout, encode, decode, and access behavior to
  a base type, then layers an additional field-local rule on top via `refine/1`.

  This keeps field-local invariants in the type system, so whole-struct
  validation pipelines can focus on cross-field/state rules.

  ## Example

      defmodule MyApp.Types.NonNegativeI64 do
        use GridCodec.Type.Refined, base: :i64

        @impl true
        def refine(nil), do: :ok
        def refine(value) when value >= 0, do: :ok
        def refine(_), do: {:error, "must be >= 0"}
      end

  The refinement is enforced by `new/1`/`update/2` coercion and by encode-time
  validation when `validate: true` is enabled.
  """

  @callback refine(term()) :: :ok | {:error, String.t()}

  defmacro __using__(opts) do
    base = Keyword.fetch!(opts, :base)

    base_module =
      case GridCodec.Type.lookup(base, %{}) do
        {:ok, module} ->
          module

        {:error, :unknown_type} ->
          raise ArgumentError, "unknown refined base type: #{inspect(base)}"
      end

    quote bind_quoted: [base_module: base_module] do
      @behaviour GridCodec.Type
      @behaviour GridCodec.Type.Refined

      @base_type base_module

      @doc false
      def __base_type__, do: @base_type

      @impl GridCodec.Type
      def size, do: @base_type.size()

      @impl GridCodec.Type
      def alignment, do: @base_type.alignment()

      @impl GridCodec.Type
      def null_value, do: @base_type.null_value()

      @impl GridCodec.Type
      def encode_ast(field_name, default, endian, data_var),
        do: @base_type.encode_ast(field_name, default, endian, data_var)

      @impl GridCodec.Type
      def decode_pattern_ast(var, endian), do: @base_type.decode_pattern_ast(var, endian)

      @impl GridCodec.Type
      def getter_ast(offset, endian, payload_var),
        do: @base_type.getter_ast(offset, endian, payload_var)

      @doc false
      def get_value(binary, offset, endian), do: @base_type.get_value(binary, offset, endian)

      if function_exported?(@base_type, :decode_value_ast, 1) do
        @impl GridCodec.Type
        def decode_value_ast(var), do: @base_type.decode_value_ast(var)
      end

      if function_exported?(@base_type, :compare_values, 2) do
        @impl GridCodec.Type
        def compare_values(left, right), do: @base_type.compare_values(left, right)
      end

      if function_exported?(@base_type, :generator, 0) do
        @impl GridCodec.Type
        def generator, do: @base_type.generator()
      end

      if function_exported?(@base_type, :decode_as_ast, 2) do
        @impl GridCodec.Type
        def decode_as_ast(value_var, opts), do: @base_type.decode_as_ast(value_var, opts)
      end

      if function_exported?(@base_type, :encode_to_wire_ast, 2) do
        @impl GridCodec.Type
        def encode_to_wire_ast(value_var, opts),
          do: @base_type.encode_to_wire_ast(value_var, opts)
      end

      @impl GridCodec.Type
      def coerce_ast(value_var) do
        base_ast =
          if function_exported?(@base_type, :coerce_ast, 1) do
            @base_type.coerce_ast(value_var)
          else
            quote(do: {:ok, unquote(value_var)})
          end

        mod = __MODULE__

        quote do
          case unquote(base_ast) do
            {:ok, nil} ->
              {:ok, nil}

            {:ok, value} ->
              case unquote(mod).refine(value) do
                :ok -> {:ok, value}
                {:error, reason} -> {:error, reason}
              end

            {:error, _} = error ->
              error
          end
        end
      end

      @impl GridCodec.Type
      def validate_ast(value_var, field_name, codec_module) do
        base_ast =
          if function_exported?(@base_type, :validate_ast, 3) do
            @base_type.validate_ast(value_var, field_name, codec_module)
          end

        mod = __MODULE__

        quote do
          unquote(base_ast || quote(do: :ok))

          case unquote(value_var) do
            nil ->
              :ok

            value ->
              case unquote(mod).refine(value) do
                :ok ->
                  :ok

                {:error, reason} ->
                  raise GridCodec.ValidationError.invariant_failed(
                          unquote(codec_module),
                          unquote(field_name),
                          reason,
                          %{type: unquote(mod), validation: :type_refinement}
                        )
              end
          end
        end
      end
    end
  end
end
