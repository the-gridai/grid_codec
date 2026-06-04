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
    null_m = @null_mantissa
    dec_mod = Decimal

    quote do
      case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
        nil ->
          <<unquote(null_m)::little-signed-64, 0::signed-8>>

        %unquote(dec_mod){coef: :NaN} ->
          <<unquote(null_m)::little-signed-64, 0::signed-8>>

        %unquote(dec_mod){coef: :inf} ->
          <<unquote(null_m)::little-signed-64, 0::signed-8>>

        %unquote(dec_mod){sign: 1, coef: coef, exp: exp} ->
          <<coef::little-signed-64, exp::signed-8>>

        %unquote(dec_mod){coef: coef, exp: exp} ->
          <<-coef::little-signed-64, exp::signed-8>>

        {m, e} when is_integer(m) and is_integer(e) ->
          <<m::little-signed-64, e::signed-8>>

        n when is_integer(n) ->
          <<n::little-signed-64, 0::signed-8>>
      end :: binary - size(9)
    end
  end

  @doc false
  def encode_value(nil), do: <<@null_mantissa::little-signed-64, 0::signed-8>>

  def encode_value(%Decimal{coef: :NaN}), do: <<@null_mantissa::little-signed-64, 0::signed-8>>
  def encode_value(%Decimal{coef: :inf}), do: <<@null_mantissa::little-signed-64, 0::signed-8>>

  def encode_value(%Decimal{sign: 1, coef: coef, exp: exp}) when is_integer(coef) do
    <<coef::little-signed-64, exp::signed-8>>
  end

  def encode_value(%Decimal{coef: coef, exp: exp}) when is_integer(coef) do
    <<-coef::little-signed-64, exp::signed-8>>
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

  @impl true
  def compare_values(left, right) do
    case Decimal.compare(coerce_compare_value(left), coerce_compare_value(right)) do
      :lt -> :lt
      :eq -> :eq
      :gt -> :gt
    end
  end

  @doc """
  Extracts a decimal from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(^offset), mantissa::little-signed-64, exponent::signed-8, _::binary>> =
      binary

    if mantissa == @null_mantissa do
      nil
    else
      {sign, coef} = if mantissa < 0, do: {-1, -mantissa}, else: {1, mantissa}
      %Decimal{sign: sign, coef: coef, exp: exponent}
    end
  end

  @impl true
  def decode_as_ast(var, opts) do
    scale = Keyword.get(opts, :scale)
    integer_source? = integer_source?(Keyword.get(opts, :source_module))

    cond do
      scale && integer_source? ->
        quote do
          case unquote(var) do
            nil -> nil
            0 -> Decimal.new(0)
            v when v > 0 -> Decimal.new(1, v, -unquote(scale))
            v -> Decimal.new(-1, -v, -unquote(scale))
          end
        end

      scale ->
        quote do
          case unquote(var) do
            nil -> nil
            %Decimal{} = d -> d
            0 -> Decimal.new(0)
            v when is_integer(v) and v > 0 -> Decimal.new(1, v, -unquote(scale))
            v when is_integer(v) -> Decimal.new(-1, -v, -unquote(scale))
            v -> v
          end
        end

      integer_source? ->
        quote do
          case unquote(var) do
            nil -> nil
            v -> Decimal.new(v)
          end
        end

      true ->
        quote do
          case unquote(var) do
            nil -> nil
            v when is_integer(v) -> Decimal.new(v)
            %Decimal{} = d -> d
            v -> v
          end
        end
    end
  end

  @impl true
  def encode_to_wire_ast(var, opts) do
    scale = Keyword.get(opts, :scale, 0)

    quote do
      case unquote(var) do
        %Decimal{sign: sign, coef: coef, exp: exp} ->
          diff = unquote(scale) + exp

          adjusted =
            if diff >= 0 do
              coef * GridCodec.Types.Decimal.int_pow10(diff)
            else
              div(coef, GridCodec.Types.Decimal.int_pow10(-diff))
            end

          if sign == 1, do: adjusted, else: -adjusted

        {m, e} when is_integer(m) and is_integer(e) ->
          diff = unquote(scale) + e

          if diff >= 0 do
            m * GridCodec.Types.Decimal.int_pow10(diff)
          else
            div(m, GridCodec.Types.Decimal.int_pow10(-diff))
          end

        n when is_integer(n) ->
          n
      end
    end
  end

  @doc false
  def int_pow10(0), do: 1
  def int_pow10(1), do: 10
  def int_pow10(2), do: 100
  def int_pow10(3), do: 1_000
  def int_pow10(4), do: 10_000
  def int_pow10(5), do: 100_000
  def int_pow10(6), do: 1_000_000
  def int_pow10(7), do: 10_000_000
  def int_pow10(8), do: 100_000_000
  def int_pow10(n) when n > 0, do: 10 * int_pow10(n - 1)

  @integer_types [
    GridCodec.Types.I8,
    GridCodec.Types.I16,
    GridCodec.Types.I32,
    GridCodec.Types.I64,
    GridCodec.Types.U8,
    GridCodec.Types.U16,
    GridCodec.Types.U32,
    GridCodec.Types.U64
  ]

  defp integer_source?(nil), do: false
  defp integer_source?(module), do: module in @integer_types

  @impl true
  def coerce_ast(var) do
    dec_mod = Decimal

    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        %unquote(dec_mod){} = v ->
          {:ok, v}

        {m, e} when is_integer(m) and is_integer(e) ->
          {sign, coef} = if m < 0, do: {-1, -m}, else: {1, m}
          {:ok, %unquote(dec_mod){sign: sign, coef: coef, exp: e}}

        v when is_integer(v) ->
          {:ok, unquote(dec_mod).new(v)}

        v when is_float(v) ->
          {:ok, unquote(dec_mod).from_float(v)}

        v when is_binary(v) ->
          try do
            {:ok, unquote(dec_mod).new(v)}
          rescue
            Decimal.Error -> {:error, "cannot parse decimal from #{inspect(v)}"}
          end

        v ->
          {:error, "expected Decimal, number, or string, got #{inspect(v)}"}
      end
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    dec_mod = Decimal

    quote do
      case unquote(var) do
        nil ->
          :ok

        %unquote(dec_mod){} ->
          :ok

        {m, e} when is_integer(m) and is_integer(e) ->
          :ok

        v when is_integer(v) ->
          :ok

        v when is_float(v) ->
          :ok

        v ->
          raise GridCodec.ValidationError.type_mismatch(
                  unquote(mod),
                  unquote(field),
                  :decimal,
                  v,
                  "Decimal, {mantissa, exponent} tuple, integer, float, or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(StreamData) do
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

  defp coerce_compare_value(%Decimal{} = d), do: d
  defp coerce_compare_value({m, e}) when is_integer(m) and is_integer(e), do: to_decimal(m, e)
  defp coerce_compare_value(n) when is_integer(n), do: Decimal.new(n)
  defp coerce_compare_value(n) when is_float(n), do: Decimal.from_float(n)

  defp coerce_compare_value(other) do
    raise ArgumentError,
          "unsupported decimal compare value: #{inspect(other)}. " <>
            "Expected Decimal.t, {mantissa, exponent}, integer, or float"
  end
end
