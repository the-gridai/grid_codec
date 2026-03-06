defmodule GridCodec.Types.F64 do
  @moduledoc """
  IEEE 754 double-precision floating-point type.

  Encodes floating-point values in eight bytes with approximately
  15-16 decimal digits of precision.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

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
  def decode_value_ast(var) do
    quote do
      unquote(__MODULE__).maybe_nil(unquote(var))
    end
  end

  @doc false
  # IEEE 754: NaN != NaN is the canonical NaN check
  # credo:disable-for-next-line Credo.Check.Warning.OperationOnSameValues
  def maybe_nil(v) when is_float(v) and v != v, do: nil
  def maybe_nil(v), do: v

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

  @doc """
  Extracts an f64 value from a binary at the given offset.
  """
  def get_value(binary, offset, endian) when is_binary(binary) do
    case endian do
      :little ->
        <<_::binary-size(offset), value::float-little-64, _::binary>> = binary
        value

      :big ->
        <<_::binary-size(offset), value::float-big-64, _::binary>> = binary
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
  def coerce_ast(var) do
    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        v when is_float(v) ->
          {:ok, v}

        v when is_integer(v) ->
          {:ok, v * 1.0}

        v when is_binary(v) ->
          case Float.parse(v) do
            {f, ""} -> {:ok, f}
            _ -> {:error, "cannot parse float from #{inspect(v)}"}
          end

        v ->
          {:error, "expected number or string, got #{inspect(v)}"}
      end
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
                  :f64,
                  v,
                  "number or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.f64()
  end
end
