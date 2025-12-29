defmodule GridCodec.Types.I64 do
  @moduledoc """
  Signed 64-bit integer type.

  Encodes values from -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807
  in eight bytes using two's complement.

  ## Examples

      defmodule MyCodec do
        use GridCodec

        defcodec do
          field :timestamp, :i64
          field :offset_ns, :i64, default: 0
        end
      end

      # Encode a signed timestamp (can represent dates before Unix epoch)
      MyCodec.encode(%{timestamp: -1_000_000, offset_ns: 0})

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       8     Signed 64-bit value

  ## Common Use Cases

  - **Timestamps**: When you need to represent dates before 1970
  - **Nanosecond offsets**: High-precision time adjustments
  - **Large signed values**: Financial calculations requiring sign

  ## Byte Order

  With `:little` endian (default): least significant byte first.
  With `:big` endian: most significant byte first.
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 8

  @impl true
  def alignment, do: 8

  @impl true
  def null_value, do: -9_223_372_036_854_775_808

  @null_val -9_223_372_036_854_775_808

  @impl true
  def encode_ast(field_name, default, endian, data_var) do
    null_val = @null_val

    case endian do
      :little ->
        quote do
          case Map.get(unquote(data_var), unquote(field_name), unquote(default)) do
            nil -> unquote(null_val)
            v -> v
          end :: signed - little - 64
        end

      :big ->
        quote do
          case Map.get(unquote(data_var), unquote(field_name), unquote(default)) do
            nil -> unquote(null_val)
            v -> v
          end :: signed - big - 64
        end
    end
  end

  @impl true
  def decode_pattern_ast(var, endian) do
    case endian do
      :little -> quote do: unquote(var) :: signed - little - 64
      :big -> quote do: unquote(var) :: signed - big - 64
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
          <<_::binary-size(unquote(offset)), value::signed-little-64, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end

      :big ->
        quote do
          <<_::binary-size(unquote(offset)), value::signed-big-64, _::binary>> =
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
    def generator, do: GridCodec.Generators.i64()
  end
end
