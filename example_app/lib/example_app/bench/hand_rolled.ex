defmodule ExampleApp.Bench.HandRolled do
  @moduledoc false

  @null_u64 18_446_744_073_709_551_615
  @null_u32 4_294_967_295
  @null_u8 255
  @max_u64 18_446_744_073_709_551_615
  @max_u32 4_294_967_295
  @max_u8 255
  @min_i64 -9_223_372_036_854_775_808
  @max_i64 9_223_372_036_854_775_807

  def encode(%{
        order_id: order_id,
        user_id: user_id,
        symbol: symbol,
        side: side,
        price: price,
        quantity: quantity,
        timestamp: timestamp,
        flags: flags
      }) do
    encoded_symbol = encode_string16(symbol)

    <<
      validate_binary16(order_id, :order_id)::binary-size(16),
      validate_u64(user_id, :user_id)::unsigned-little-64,
      validate_u8(side, :side)::unsigned-8,
      validate_u64(price, :price)::unsigned-little-64,
      validate_u32(quantity, :quantity)::unsigned-little-32,
      validate_i64(timestamp, :timestamp)::signed-little-64,
      validate_u8(flags, :flags)::unsigned-8,
      encoded_symbol::binary
    >>
  end

  def decode(
        <<order_id::binary-size(16), user_id::unsigned-little-64, side::unsigned-8,
          price::unsigned-little-64, quantity::unsigned-little-32, timestamp::signed-little-64,
          flags::unsigned-8, rest::binary>>
      ) do
    {symbol, _rest} = decode_string16(rest)

    {:ok,
     %{
       order_id: if(order_id == <<0::128>>, do: nil, else: order_id),
       user_id: if(user_id == @null_u64, do: nil, else: user_id),
       side: if(side == @null_u8, do: nil, else: side),
       price: if(price == @null_u64, do: nil, else: price),
       quantity: if(quantity == @null_u32, do: nil, else: quantity),
       timestamp: if(timestamp == 0, do: nil, else: timestamp),
       flags: if(flags == @null_u8, do: nil, else: flags),
       symbol: symbol
     }}
  end

  def get_price(
        <<_::binary-size(16), _::64, _::8, price::unsigned-little-64, _::binary>>
      ) do
    if price == @null_u64, do: nil, else: price
  end

  defp validate_binary16(nil, _), do: <<0::128>>
  defp validate_binary16(v, _) when is_binary(v) and byte_size(v) == 16, do: v

  defp validate_binary16(v, name),
    do: raise(ArgumentError, "field #{inspect(name)} expects 16-byte binary, got: #{inspect(v)}")

  defp validate_u64(nil, _), do: @null_u64
  defp validate_u64(v, _) when is_integer(v) and v >= 0 and v <= @max_u64, do: v

  defp validate_u64(v, name),
    do: raise(ArgumentError, "field #{inspect(name)} expects u64, got: #{inspect(v)}")

  defp validate_u32(nil, _), do: @null_u32
  defp validate_u32(v, _) when is_integer(v) and v >= 0 and v <= @max_u32, do: v

  defp validate_u32(v, name),
    do: raise(ArgumentError, "field #{inspect(name)} expects u32, got: #{inspect(v)}")

  defp validate_u8(nil, _), do: @null_u8
  defp validate_u8(v, _) when is_integer(v) and v >= 0 and v <= @max_u8, do: v

  defp validate_u8(v, name),
    do: raise(ArgumentError, "field #{inspect(name)} expects u8, got: #{inspect(v)}")

  defp validate_i64(nil, _), do: 0
  defp validate_i64(v, _) when is_integer(v) and v >= @min_i64 and v <= @max_i64, do: v

  defp validate_i64(v, name),
    do: raise(ArgumentError, "field #{inspect(name)} expects i64, got: #{inspect(v)}")

  defp encode_string16(nil), do: <<0::little-16>>

  defp encode_string16(str) when is_binary(str) do
    <<byte_size(str)::little-16, str::binary>>
  end

  defp decode_string16(<<0::little-16, rest::binary>>), do: {nil, rest}

  defp decode_string16(<<len::little-16, str::binary-size(len), rest::binary>>),
    do: {str, rest}
end
