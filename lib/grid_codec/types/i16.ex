defmodule GridCodec.Types.I16 do
  @moduledoc """
  Signed 16-bit integer type.

  Encodes values from -32,768 to 32,767 in two bytes using two's complement.

  ## Examples

      defmodule MyCodec do
        use GridCodec

        defcodec do
          field :altitude, :i16
          field :delta, :i16, default: 0
        end
      end

      MyCodec.encode(%{altitude: -1000, delta: 500})

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       2     Signed 16-bit value (-32,768 to 32,767)

  ## Byte Order

  With `:little` endian (default): least significant byte first.
  With `:big` endian: most significant byte first.
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 2

  @impl true
  def alignment, do: 2

  @impl true
  def null_value, do: -32768

  @null_val -32_768

  @impl true
  def encode_ast(field_name, default, endian, data_var) do
    null_val = @null_val

    case endian do
      :little ->
        quote do
          (case Map.get(unquote(data_var), unquote(field_name), unquote(default)) do
             nil -> unquote(null_val)
             v -> v
           end) :: signed - little - 16
        end

      :big ->
        quote do
          (case Map.get(unquote(data_var), unquote(field_name), unquote(default)) do
             nil -> unquote(null_val)
             v -> v
           end) :: signed - big - 16
        end
    end
  end

  @impl true
  def decode_pattern_ast(var, endian) do
    case endian do
      :little -> quote do: unquote(var) :: signed - little - 16
      :big -> quote do: unquote(var) :: signed - big - 16
    end
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
  def getter_ast(offset, endian, payload_var) do
    null_val = @null_val

    case endian do
      :little ->
        quote do
          <<_::binary-size(unquote(offset)), value::signed-little-16, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end

      :big ->
        quote do
          <<_::binary-size(unquote(offset)), value::signed-big-16, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator, do: GridCodec.Generators.i16()
  end
end
