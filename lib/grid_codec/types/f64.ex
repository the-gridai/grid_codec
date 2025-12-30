defmodule GridCodec.Types.F64 do
  @moduledoc """
  IEEE 754 double-precision floating-point type.

  Encodes floating-point values in eight bytes with approximately
  15-16 decimal digits of precision.

  ## Examples

      defmodule MyCodec do
        use GridCodec

        defcodec do
          field :latitude, :f64
          field :longitude, :f64
        end
      end

      MyCodec.encode(%{latitude: 37.7749295, longitude: -122.4194155})

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       8     IEEE 754 double-precision float

  ## Precision

  Double-precision floats have:
  - 1 sign bit
  - 11 exponent bits
  - 52 mantissa bits

  This provides approximately 15-16 significant decimal digits.

  ## Special Values

  IEEE 754 defines special values that are preserved:
  - Positive/negative infinity
  - NaN (Not a Number)
  - Positive/negative zero

  ## Common Use Cases

  - **GPS coordinates**: Latitude/longitude requiring high precision
  - **Scientific measurements**: Physics, chemistry calculations
  - **Statistical data**: When intermediate precision matters

  ## Note on Financial Data

  For monetary values, prefer integer types (`:u64`, `:i64`) storing
  the smallest unit (cents, satoshis, etc.) to avoid floating-point
  precision issues.
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 8

  @impl true
  def alignment, do: 8

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
            float - little - 64
        end

      :big ->
        quote do
          :maps.get(unquote(field_name), unquote(data_var), unquote(default)) :: float - big - 64
        end
    end
  end

  @impl true
  def decode_pattern_ast(var, endian) do
    case endian do
      :little -> quote do: unquote(var) :: float - little - 64
      :big -> quote do: unquote(var) :: float - big - 64
    end
  end

  @impl true
  def getter_ast(offset, endian, payload_var) do
    case endian do
      :little ->
        quote do
          <<_::binary-size(unquote(offset)), value::float-little-64, _::binary>> =
            unquote(payload_var)

          value
        end

      :big ->
        quote do
          <<_::binary-size(unquote(offset)), value::float-big-64, _::binary>> =
            unquote(payload_var)

          value
        end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator, do: GridCodec.Generators.f64()
  end
end
