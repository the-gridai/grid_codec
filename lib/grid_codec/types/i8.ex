defmodule GridCodec.Types.I8 do
  @moduledoc """
  Signed 8-bit integer type.

  Encodes values from -128 to 127 in a single byte using two's complement.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :temperature, :i8
          field :offset, :i8, default: 0
        end
      end

      MyCodec.encode(%{temperature: -40, offset: 10})
      # => <<216, 10>>

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       1     Signed 8-bit value (-128 to 127)

  ## Two's Complement

  Negative values use two's complement representation:
  - -1 is encoded as 0xFF (255 unsigned)
  - -128 is encoded as 0x80 (128 unsigned)
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 1

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: -128

  @null_val -128

  @impl true
  def encode_ast(field_name, default, _endian, data_var) do
    null_val = @null_val

    quote do
      case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
        nil -> unquote(null_val)
        v -> unquote(GridCodec.Types.Integer.validate_signed_ast(quote(do: v), 8, field_name))
      end :: signed - 8
    end
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: signed - 8
  end

  @impl true
  def decode_value_ast(var) do
    null_val = @null_val

    quote do
      case unquote(var) do
        unquote(null_val) -> nil
        v -> v
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    null_val = @null_val

    quote do
      <<_::binary-size(unquote(offset)), value::signed-8, _::binary>> = unquote(payload_var)

      case value do
        unquote(null_val) -> nil
        v -> v
      end
    end
  end

  @doc """
  Extracts an i8 value from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(offset), value::signed-8, _::binary>> = binary
    if value == @null_val, do: nil, else: value
  end

  @impl true
  def coerce_ast(var) do
    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        v when is_integer(v) ->
          {:ok, v}

        v when is_binary(v) ->
          case Integer.parse(v) do
            {int, ""} -> {:ok, int}
            _ -> {:error, "cannot parse integer from #{inspect(v)}"}
          end

        v ->
          {:error, "expected integer or string, got #{inspect(v)}"}
      end
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    GridCodec.Types.Integer.gen_signed_validate_ast(var, field, mod, 8, :i8)
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.i8()
  end
end
