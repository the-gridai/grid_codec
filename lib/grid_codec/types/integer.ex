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
  def gen_unsigned_coerce_ast(var, bits, type_atom) do
    max = (1 <<< bits) - 1
    type_name = Atom.to_string(type_atom)

    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        v when is_integer(v) and v >= 0 and v <= unquote(max) ->
          {:ok, v}

        v when is_integer(v) ->
          {:error, "#{unquote(type_name)} value #{v} out of range 0..#{unquote(max)}"}

        v when is_binary(v) ->
          case Integer.parse(v) do
            {int, ""} when int >= 0 and int <= unquote(max) ->
              {:ok, int}

            {int, ""} ->
              {:error, "#{unquote(type_name)} value #{int} out of range 0..#{unquote(max)}"}

            _ ->
              {:error, "cannot parse integer from #{inspect(v)}"}
          end

        v ->
          {:error, "expected integer or string, got #{inspect(v)}"}
      end
    end
  end

  @doc false
  def gen_signed_coerce_ast(var, bits, type_atom) do
    min = -(1 <<< (bits - 1))
    max = (1 <<< (bits - 1)) - 1
    type_name = Atom.to_string(type_atom)

    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        v when is_integer(v) and v >= unquote(min) and v <= unquote(max) ->
          {:ok, v}

        v when is_integer(v) ->
          {:error,
           "#{unquote(type_name)} value #{v} out of range #{unquote(min)}..#{unquote(max)}"}

        v when is_binary(v) ->
          case Integer.parse(v) do
            {int, ""} when int >= unquote(min) and int <= unquote(max) ->
              {:ok, int}

            {int, ""} ->
              {:error,
               "#{unquote(type_name)} value #{int} out of range #{unquote(min)}..#{unquote(max)}"}

            _ ->
              {:error, "cannot parse integer from #{inspect(v)}"}
          end

        v ->
          {:error, "expected integer or string, got #{inspect(v)}"}
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
