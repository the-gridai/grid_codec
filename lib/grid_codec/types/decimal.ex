defmodule GridCodec.Types.Decimal do
  @moduledoc """
  Composite decimal type for precise financial values.

  Encodes numbers as mantissa + exponent, avoiding floating-point precision loss.
  This is critical for financial applications where `0.1 + 0.2 != 0.3` in floats.

  ## Wire Format

      ┌─────────────────────────────────────────┐
      │  mantissa (i64 LE)  │  exponent (i8)    │
      └─────────────────────────────────────────┘
      Total: 9 bytes

  ## Value Interpretation

      value = mantissa × 10^exponent

  ## Examples

      # Price: $123.45
      mantissa = 12345, exponent = -2
      value = 12345 × 10^(-2) = 123.45

  ## Null Representation

  Uses `mantissa = -2^63` (i64 min) as the null sentinel.

  ## Usage

      defcodec do
        field :price, :decimal
        field :quantity, :decimal
      end

      # Encode with Decimal library
      data = %{price: Decimal.new("123.45"), quantity: Decimal.new("100")}

      # Or encode with {mantissa, exponent} tuple
      data = %{price: {12345, -2}, quantity: {100, 0}}
  """

  @behaviour GridCodec.Type

  @size 9
  @alignment 8
  @null_mantissa -9_223_372_036_854_775_808

  @impl true
  def size, do: @size

  @impl true
  def alignment, do: @alignment

  @impl true
  def null_value, do: nil

  @impl true
  def encode_ast(field_name, default, _endian, data_var) do
    # Return a binary value that will be concatenated
    quote do
      GridCodec.Types.Decimal.encode_value(
        :maps.get(unquote(field_name), unquote(data_var), unquote(default))
      ) :: binary
    end
  end

  @doc false
  def encode_value(nil), do: <<@null_mantissa::little-signed-64, 0::signed-8>>

  def encode_value(%Decimal{} = d) do
    {mantissa, exponent} = from_decimal(d)
    <<mantissa::little-signed-64, exponent::signed-8>>
  end

  def encode_value({m, e}) when is_integer(m) and is_integer(e) do
    <<m::little-signed-64, e::signed-8>>
  end

  def encode_value(n) when is_integer(n) do
    <<n::little-signed-64, 0::signed-8>>
  end

  def encode_value(n) when is_float(n) do
    {mantissa, exponent} = from_float(n)
    <<mantissa::little-signed-64, exponent::signed-8>>
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    # Decode as raw 9-byte binary, post-process in decode_value_ast
    quote do
      unquote(var) :: binary - size(9)
    end
  end

  @impl true
  def decode_value_ast(var) do
    null_mantissa = @null_mantissa

    # Inline decode for performance - avoids function call overhead
    # Direct struct creation is 1.6x faster than Decimal.new/3
    quote do
      <<mantissa::little-signed-64, exponent::signed-8>> = unquote(var)

      if mantissa == unquote(null_mantissa) do
        nil
      else
        {sign, coef} = if mantissa < 0, do: {-1, -mantissa}, else: {1, mantissa}
        %Decimal{sign: sign, coef: coef, exp: exponent}
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    null_mantissa = @null_mantissa

    # Inline for performance - direct struct creation
    quote do
      <<_::binary-size(unquote(offset)), mantissa::little-signed-64, exponent::signed-8,
        _::binary>> = unquote(payload_var)

      if mantissa == unquote(null_mantissa) do
        nil
      else
        {sign, coef} = if mantissa < 0, do: {-1, -mantissa}, else: {1, mantissa}
        %Decimal{sign: sign, coef: coef, exp: exponent}
      end
    end
  end

  @doc """
  Extracts a decimal from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(offset), mantissa::little-signed-64, exponent::signed-8, _::binary>> = binary

    if mantissa == @null_mantissa do
      nil
    else
      {sign, coef} = if mantissa < 0, do: {-1, -mantissa}, else: {1, mantissa}
      %Decimal{sign: sign, coef: coef, exp: exponent}
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator do
      import StreamData

      one_of([
        # Regular decimals
        bind(integer(-1_000_000_000..1_000_000_000), fn mantissa ->
          bind(integer(-8..8), fn exp ->
            constant({mantissa, exp})
          end)
        end),
        # Nil
        constant(nil)
      ])
    end
  end

  # ============================================================================
  # Binary Helpers
  # ============================================================================

  @doc false
  def decode_binary(<<@null_mantissa::little-signed-64, _exp::signed-8>>), do: nil

  def decode_binary(<<mantissa::little-signed-64, exponent::signed-8>>) do
    to_decimal(mantissa, exponent)
  end

  # ============================================================================
  # Conversion Helpers
  # ============================================================================

  @doc """
  Converts a Decimal struct to {mantissa, exponent} tuple.
  """
  @spec from_decimal(Decimal.t()) :: {integer(), integer()}
  def from_decimal(%Decimal{sign: sign, coef: coef, exp: exp}) when is_integer(coef) do
    mantissa = if sign == 1, do: coef, else: -coef
    {mantissa, exp}
  end

  def from_decimal(%Decimal{coef: :NaN}), do: {@null_mantissa, 0}
  def from_decimal(%Decimal{coef: :inf}), do: {@null_mantissa, 0}

  @doc """
  Converts a float to {mantissa, exponent} tuple.

  Uses 8 decimal places by default to avoid precision issues.
  """
  @spec from_float(float(), integer()) :: {integer(), integer()}
  def from_float(f, precision \\ -8) do
    scale = round(:math.pow(10, -precision))
    mantissa = round(f * scale)
    {mantissa, precision}
  end

  @doc """
  Converts mantissa and exponent to a Decimal struct.
  """
  @spec to_decimal(integer(), integer()) :: Decimal.t()
  def to_decimal(mantissa, exponent) do
    {sign, coef} =
      if mantissa < 0 do
        {-1, -mantissa}
      else
        {1, mantissa}
      end

    %Decimal{sign: sign, coef: coef, exp: exponent}
  end

  @doc """
  Converts to a float (may lose precision).
  """
  @spec to_float(integer(), integer()) :: float()
  def to_float(mantissa, exponent) do
    mantissa * :math.pow(10, exponent)
  end
end
