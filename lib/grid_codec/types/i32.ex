defmodule GridCodec.Types.I32 do
  @moduledoc """
  Signed 32-bit integer type.

  Encodes values from -2,147,483,648 to 2,147,483,647 in four bytes
  using two's complement.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :balance, :i32
          field :change, :i32, default: 0
        end
      end

      MyCodec.encode(%{balance: -50000, change: 1000})

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       4     Signed 32-bit value

  ## Common Use Cases

  - **Balances**: Account balances that can go negative
  - **Coordinates**: X/Y positions in games or maps
  - **Deltas**: Changes that can be positive or negative
  - **Temperatures**: Scientific measurements

  ## Byte Order

  With `:little` endian (default): least significant byte first.
  With `:big` endian: most significant byte first.
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 4

  @impl true
  def alignment, do: 4

  @impl true
  def null_value, do: -2_147_483_648

  @null_val -2_147_483_648

  @impl true
  def encode_ast(field_name, default, endian, data_var) do
    null_val = @null_val

    case endian do
      :little ->
        quote do
          case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
            nil ->
              unquote(null_val)

            v ->
              unquote(GridCodec.Types.Integer.validate_signed_ast(quote(do: v), 32, field_name))
          end :: signed - little - 32
        end

      :big ->
        quote do
          case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
            nil ->
              unquote(null_val)

            v ->
              unquote(GridCodec.Types.Integer.validate_signed_ast(quote(do: v), 32, field_name))
          end :: signed - big - 32
        end
    end
  end

  @impl true
  def decode_pattern_ast(var, endian) do
    case endian do
      :little -> quote do: unquote(var) :: signed - little - 32
      :big -> quote do: unquote(var) :: signed - big - 32
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
          <<_::binary-size(unquote(offset)), value::signed-little-32, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end

      :big ->
        quote do
          <<_::binary-size(unquote(offset)), value::signed-big-32, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end
    end
  end

  @doc """
  Extracts an i32 value from a binary at the given offset.
  """
  def get_value(binary, offset, endian) when is_binary(binary) do
    value =
      case endian do
        :little ->
          <<_::binary-size(offset), v::signed-little-32, _::binary>> = binary
          v

        :big ->
          <<_::binary-size(offset), v::signed-big-32, _::binary>> = binary
          v
      end

    if value == @null_val, do: nil, else: value
  end

  @impl true
  def coerce_ast(var) do
    GridCodec.Types.Integer.gen_signed_coerce_ast(var, 32, :i32)
  end

  @impl true
  def validate_ast(var, field, mod) do
    GridCodec.Types.Integer.gen_signed_validate_ast(var, field, mod, 32, :i32)
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.i32()
  end
end
