defmodule GridCodec.Types.PositiveDecimal do
  @moduledoc """
  Decimal type optimized for values that are always non-negative.

  Same 9-byte wire format as `:decimal`, but skips sign handling on both
  encode and decode. Use for prices, quantities, balances, fees — any
  field that is never negative.

  ## Wire Format

      ┌─────────────────────────────────────────┐
      │  mantissa (i64 LE)  │  exponent (i8)    │
      └─────────────────────────────────────────┘
      Total: 9 bytes

  Wire-compatible with `:decimal` for non-negative values.

  ## Performance

  Encoding: skips `%Decimal{}` sign check — direct `coef` write.
  Decoding: skips sign computation — always `%Decimal{sign: 1, ...}`.

  ## Usage

      defcodec do
        field :price, GridCodec.Types.PositiveDecimal
        field :quantity, GridCodec.Types.PositiveDecimal
      end
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

        %unquote(dec_mod){coef: coef, exp: exp} ->
          <<coef::little-signed-64, exp::signed-8>>

        {m, e} when is_integer(m) and is_integer(e) ->
          <<m::little-signed-64, e::signed-8>>

        n when is_integer(n) ->
          <<n::little-signed-64, 0::signed-8>>
      end :: binary - size(9)
    end
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: binary - size(9)
  end

  @impl true
  def decode_value_ast(var) do
    null_mantissa = @null_mantissa

    quote do
      <<mantissa::little-signed-64, exponent::signed-8>> = unquote(var)

      if mantissa == unquote(null_mantissa) do
        nil
      else
        %Decimal{sign: 1, coef: mantissa, exp: exponent}
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    null_mantissa = @null_mantissa

    quote do
      <<_::binary-size(unquote(offset)), mantissa::little-signed-64, exponent::signed-8,
        _::binary>> = unquote(payload_var)

      if mantissa == unquote(null_mantissa) do
        nil
      else
        %Decimal{sign: 1, coef: mantissa, exp: exponent}
      end
    end
  end

  @impl true
  def compare_values(left, right) do
    case Decimal.compare(coerce(left), coerce(right)) do
      :lt -> :lt
      :eq -> :eq
      :gt -> :gt
    end
  end

  defp coerce(%Decimal{} = d), do: d
  defp coerce({m, e}) when is_integer(m), do: %Decimal{sign: 1, coef: m, exp: e}
  defp coerce(n) when is_integer(n), do: Decimal.new(n)

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
                  :positive_decimal,
                  v,
                  "Decimal, {mantissa, exponent} tuple, integer, float, or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator do
      import StreamData

      one_of([
        bind(integer(0..1_000_000_000), fn mantissa ->
          bind(integer(-8..8), fn exp ->
            constant({mantissa, exp})
          end)
        end),
        constant(nil)
      ])
    end
  end
end
