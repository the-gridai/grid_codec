defmodule GridCodec.Types.U64 do
  @moduledoc """
  Unsigned 64-bit integer type.

  Encodes values from 0 to 18,446,744,073,709,551,615 in eight bytes.
  Ideal for timestamps, large IDs, and monetary values in minor units.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :timestamp, :u64
          field :price_cents, :u64, default: 0
        end
      end

      # Encode a timestamp and price
      now = System.system_time(:microsecond)
      MyCodec.encode(%{timestamp: now, price_cents: 1_500_000})

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       8     Unsigned 64-bit value

  ## Common Use Cases

  - **Timestamps**: Microseconds since epoch fit comfortably
  - **Monetary values**: Store cents/minor units to avoid float precision issues
  - **Snowflake IDs**: Twitter-style distributed IDs
  - **Hash prefixes**: First 8 bytes of a hash for quick comparison

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
  def null_value, do: 18_446_744_073_709_551_615

  @null_val 18_446_744_073_709_551_615

  @impl true
  def encode_ast(field_name, default, endian, data_var) do
    # Use :maps.get/3 BIF directly (faster than Map.get/3)
    # If key is missing, default is returned; if present with nil, use null_val
    null_val = @null_val

    case endian do
      :little ->
        quote do
          case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
            nil ->
              unquote(null_val)

            v ->
              unquote(GridCodec.Types.Integer.validate_unsigned_ast(quote(do: v), 64, field_name))
          end :: unsigned - little - 64
        end

      :big ->
        quote do
          case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
            nil ->
              unquote(null_val)

            v ->
              unquote(GridCodec.Types.Integer.validate_unsigned_ast(quote(do: v), 64, field_name))
          end :: unsigned - big - 64
        end
    end
  end

  @impl true
  def decode_pattern_ast(var, endian) do
    case endian do
      :little -> quote do: unquote(var) :: unsigned - little - 64
      :big -> quote do: unquote(var) :: unsigned - big - 64
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
          <<_::binary-size(unquote(offset)), value::unsigned-little-64, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end

      :big ->
        quote do
          <<_::binary-size(unquote(offset)), value::unsigned-big-64, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end
    end
  end

  @doc """
  Extracts a u64 value from a binary at the given offset.

  Used by `GridCodec.get/2` with field specs.
  """
  def get_value(binary, offset, endian) when is_binary(binary) do
    case endian do
      :little ->
        <<_::binary-size(offset), value::unsigned-little-64, _::binary>> = binary

        case value do
          @null_val -> nil
          v -> v
        end

      :big ->
        <<_::binary-size(offset), value::unsigned-big-64, _::binary>> = binary

        case value do
          @null_val -> nil
          v -> v
        end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator, do: GridCodec.Generators.u64()
  end
end
