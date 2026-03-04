defmodule GridCodec.Types.U8 do
  @moduledoc """
  Unsigned 8-bit integer type.

  Encodes values from 0 to 255 in a single byte.
  Endianness has no effect on single-byte values.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :status, :u8
          field :flags, :u8, default: 0
        end
      end

      MyCodec.encode(%{status: 1, flags: 255})
      # => <<1, 255>>

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       1     Unsigned 8-bit value (0-255)
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 1

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: 255

  @null_val 255

  @impl true
  def encode_ast(field_name, default, _endian, data_var) do
    null_val = @null_val

    quote do
      case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
        nil -> unquote(null_val)
        v -> unquote(GridCodec.Types.Integer.validate_unsigned_ast(quote(do: v), 8, field_name))
      end :: unsigned - 8
    end
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: unsigned - 8
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
      <<_::binary-size(unquote(offset)), value::unsigned-8, _::binary>> = unquote(payload_var)

      case value do
        unquote(null_val) -> nil
        v -> v
      end
    end
  end

  @doc """
  Extracts a u8 value from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(offset), value::unsigned-8, _::binary>> = binary
    if value == @null_val, do: nil, else: value
  end

  @impl true
  def validate_ast(var, field, mod) do
    GridCodec.Types.Integer.gen_unsigned_validate_ast(var, field, mod, 8, :u8)
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator, do: GridCodec.Generators.u8()
  end
end
