defmodule GridCodec.Types.F32 do
  @moduledoc """
  IEEE 754 single-precision floating-point type.

  Encodes floating-point values in four bytes with approximately
  7 decimal digits of precision.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :temperature, :f32
          field :humidity, :f32, default: 0.0
        end
      end

      MyCodec.encode(%{temperature: 23.5, humidity: 65.2})

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       4     IEEE 754 single-precision float

  ## Precision

  Single-precision floats have:
  - 1 sign bit
  - 8 exponent bits
  - 23 mantissa bits

  This provides approximately 7 significant decimal digits.
  For higher precision, use `:f64`.

  ## Special Values

  IEEE 754 defines special values that are preserved:
  - Positive/negative infinity
  - NaN (Not a Number)
  - Positive/negative zero

  ## When to Use

  - Sensor data where 7 digits is sufficient
  - Graphics coordinates
  - When bandwidth is constrained
  - Legacy system compatibility

  For financial or scientific data requiring precision, prefer
  integer types with fixed-point arithmetic.
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 4

  @impl true
  def alignment, do: 4

  @impl true
  def null_value, do: :nan

  @impl true
  def encode_ast(field_name, default, endian, data_var) do
    # Floats are not nullable - nil will cause a runtime error
    # To support nullable floats, use a wrapper type or treat NaN as null
    case endian do
      :little ->
        quote do
          :maps.get(unquote(field_name), unquote(data_var), unquote(default)) ::
            float - little - 32
        end

      :big ->
        quote do
          :maps.get(unquote(field_name), unquote(data_var), unquote(default)) :: float - big - 32
        end
    end
  end

  @impl true
  def decode_pattern_ast(var, endian) do
    case endian do
      :little -> quote do: unquote(var) :: float - little - 32
      :big -> quote do: unquote(var) :: float - big - 32
    end
  end

  @impl true
  def getter_ast(offset, endian, payload_var) do
    case endian do
      :little ->
        quote do
          <<_::binary-size(unquote(offset)), value::float-little-32, _::binary>> =
            unquote(payload_var)

          value
        end

      :big ->
        quote do
          <<_::binary-size(unquote(offset)), value::float-big-32, _::binary>> =
            unquote(payload_var)

          value
        end
    end
  end

  @doc """
  Extracts an f32 value from a binary at the given offset.
  """
  def get_value(binary, offset, endian) when is_binary(binary) do
    case endian do
      :little ->
        <<_::binary-size(offset), value::float-little-32, _::binary>> = binary
        value

      :big ->
        <<_::binary-size(offset), value::float-big-32, _::binary>> = binary
        value
    end
  end

  @impl true
  def compare_values(left, right) do
    cond do
      left == right -> :eq
      left < right -> :lt
      true -> :gt
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    quote do
      case unquote(var) do
        nil ->
          :ok

        v when is_number(v) ->
          :ok

        v ->
          raise GridCodec.ValidationError.type_mismatch(
                  unquote(mod),
                  unquote(field),
                  :f32,
                  v,
                  "number or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator, do: GridCodec.Generators.f32()
  end
end
