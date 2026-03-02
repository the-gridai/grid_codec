defmodule ExampleApp.Bench.HandRolled do
  @moduledoc false

  @null_u64 18_446_744_073_709_551_615
  @null_u32 4_294_967_295
  @null_u8 255

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
      (order_id || <<0::128>>)::binary-size(16),
      (user_id || @null_u64)::unsigned-little-64,
      (side || @null_u8)::unsigned-8,
      (price || @null_u64)::unsigned-little-64,
      (quantity || @null_u32)::unsigned-little-32,
      (timestamp || 0)::signed-little-64,
      (flags || @null_u8)::unsigned-8,
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

  defp encode_string16(nil), do: <<0::little-16>>

  defp encode_string16(str) when is_binary(str) do
    <<byte_size(str)::little-16, str::binary>>
  end

  defp decode_string16(<<0::little-16, rest::binary>>), do: {nil, rest}

  defp decode_string16(<<len::little-16, str::binary-size(len), rest::binary>>),
    do: {str, rest}
end
