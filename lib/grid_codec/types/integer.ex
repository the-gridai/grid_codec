defmodule GridCodec.Types.Integer do
  @moduledoc false

  import Bitwise

  @doc false
  def validate_unsigned_ast(value_ast, bits, field_name) do
    max = (1 <<< bits) - 1

    quote do
      case unquote(value_ast) do
        v when is_integer(v) and v >= 0 and v <= unquote(max) ->
          v

        _ ->
          raise ArgumentError,
                "field #{inspect(unquote(field_name))} expects u#{unquote(bits)} integer in 0..#{unquote(max)}, got: #{inspect(unquote(value_ast))}"
      end
    end
  end

  @doc false
  def validate_signed_ast(value_ast, bits, field_name) do
    min = -(1 <<< (bits - 1))
    max = (1 <<< (bits - 1)) - 1

    quote do
      case unquote(value_ast) do
        v when is_integer(v) and v >= unquote(min) and v <= unquote(max) ->
          v

        _ ->
          raise ArgumentError,
                "field #{inspect(unquote(field_name))} expects i#{unquote(bits)} integer in #{unquote(min)}..#{unquote(max)}, got: #{inspect(unquote(value_ast))}"
      end
    end
  end

  @doc false
  def gen_unsigned_validate_ast(value_var, field_name, codec_module, bits, type_atom) do
    max = (1 <<< bits) - 1

    quote do
      case unquote(value_var) do
        nil ->
          :ok

        v when is_integer(v) and v >= 0 and v <= unquote(max) ->
          :ok

        v ->
          raise GridCodec.ValidationError.out_of_range(
                  unquote(codec_module),
                  unquote(field_name),
                  unquote(type_atom),
                  v,
                  "0..#{unquote(max)} or nil"
                )
      end
    end
  end

  @doc false
  def gen_signed_validate_ast(value_var, field_name, codec_module, bits, type_atom) do
    min = -(1 <<< (bits - 1))
    max = (1 <<< (bits - 1)) - 1

    quote do
      case unquote(value_var) do
        nil ->
          :ok

        v when is_integer(v) and v >= unquote(min) and v <= unquote(max) ->
          :ok

        v ->
          raise GridCodec.ValidationError.out_of_range(
                  unquote(codec_module),
                  unquote(field_name),
                  unquote(type_atom),
                  v,
                  "#{unquote(min)}..#{unquote(max)} or nil"
                )
      end
    end
  end
end
