# Lazy/Binary Decode Exploration
#
# Can we filter/scan group entries without fully decoding them?
# Can we extract single fields (columnar) faster than full decode?
#
# Run with: mix run benchmarks/lazy_decode_bench.exs

defmodule LazyDecodeBench do
  defmodule OrderSide do
    use GridCodec.Types.Enum, encoding: :u8
    defenum do
      value(:buy)
      value(:sell)
    end
  end

  defmodule OrderBook do
    use GridCodec.Struct, template_id: 990, schema_id: 99, version: 1
    alias LazyDecodeBench.OrderSide

    defcodec do
      field :id, :uuid

      group :orders do
        field :order_id, :uuid          # offset 0, 16 bytes
        field :trader_id, :uuid         # offset 16, 16 bytes
        field :side, OrderSide          # offset 32, 1 byte
        field :price, :i64              # offset 33, 8 bytes (fixed-point integer)
        field :quantity, :i64           # offset 41, 8 bytes
        field :submitted_at, :timestamp_us  # offset 49, 8 bytes
      end
      # block_length = 16+16+1+8+8+8 = 57 bytes per entry
    end
  end

  @block_length 57
  @price_offset 33
  @qty_offset 41
  @side_offset 32

  defp make_orders(n) do
    for i <- 1..n do
      %{
        order_id: <<i::128>>,
        trader_id: <<rem(i, 500)::128>>,
        side: if(rem(i, 2) == 0, do: :buy, else: :sell),
        price: 50_000_00 + rem(i, 2000) * 100,
        quantity: 1_00 + rem(i, 100) * 10,
        submitted_at: 1_700_000_000_000_000 + i
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Binary scan helpers — extract fields at known offsets, no full decode
  # ---------------------------------------------------------------------------

  def binary_scan_prices(data, block_length) do
    do_scan_prices(data, block_length, [])
  end

  defp do_scan_prices(<<>>, _bl, acc), do: :lists.reverse(acc)

  defp do_scan_prices(data, bl, acc) do
    <<_::binary-size(@price_offset), price::little-signed-64, _::binary-size(bl - @price_offset - 8),
      rest::binary>> = data

    do_scan_prices(rest, bl, [price | acc])
  end

  def binary_filter_by_price(data, block_length, threshold) do
    do_filter_price(data, block_length, threshold, 0, [])
  end

  defp do_filter_price(<<>>, _bl, _threshold, _idx, acc), do: :lists.reverse(acc)

  defp do_filter_price(data, bl, threshold, idx, acc) do
    <<entry::binary-size(bl), rest::binary>> = data
    <<_::binary-size(@price_offset), price::little-signed-64, _::binary>> = entry

    acc = if price >= threshold, do: [{idx, price} | acc], else: acc
    do_filter_price(rest, bl, threshold, idx + 1, acc)
  end

  def binary_scan_side_and_price(data, block_length, target_side_int) do
    do_scan_side_price(data, block_length, target_side_int, 0, [])
  end

  defp do_scan_side_price(<<>>, _bl, _side, _idx, acc), do: :lists.reverse(acc)

  defp do_scan_side_price(data, bl, target_side, idx, acc) do
    <<_::binary-size(@side_offset), side::unsigned-8,
      price::little-signed-64, quantity::little-signed-64,
      _::binary-size(bl - @side_offset - 1 - 8 - 8), rest::binary>> = data

    acc =
      if side == target_side,
        do: [{idx, price, quantity} | acc],
        else: acc

    do_scan_side_price(rest, bl, target_side, idx + 1, acc)
  end

  def run do
    IO.puts("Lazy/Binary Decode Exploration")
    IO.puts("Schedulers: #{System.schedulers_online()}\n")

    n = 10_000
    orders = make_orders(n)
    event = %OrderBook{id: <<1::128>>, orders: orders}
    binary = OrderBook.encode(event)
    {:ok, decoded} = OrderBook.decode(binary)

    group = decoded.orders
    %{binary: group_bin, entries_offset: offset, num_in_group: count, block_length: bl} = group
    entries_data = binary_part(group_bin, offset, count * bl)

    decoded_list = GridCodec.Group.to_list(group)
    price_threshold = 50_500_00

    IO.puts("#{n} orders, #{bl} bytes/entry, #{div(byte_size(binary), 1024)} KB wire\n")

    # -----------------------------------------------------------------------
    # 1. Extract ALL prices: to_list + Enum.map vs binary column scan
    # -----------------------------------------------------------------------
    IO.puts("--- Extract all prices ---")

    Benchee.run(
      %{
        "to_list + Enum.map(:price)" => fn ->
          decoded_list |> Enum.map(& &1.price)
        end,
        "to_list (decode) + Enum.map" => fn ->
          GridCodec.Group.to_list(group) |> Enum.map(& &1.price)
        end,
        "binary column scan (no decode)" => fn ->
          binary_scan_prices(entries_data, bl)
        end
      },
      warmup: 2, time: 5, memory_time: 1
    )

    # -----------------------------------------------------------------------
    # 2. Filter: find orders with price >= threshold
    # -----------------------------------------------------------------------
    IO.puts("\n--- Filter: price >= #{price_threshold} ---")

    matching_full = Enum.count(decoded_list, &(&1.price >= price_threshold))
    matching_binary = length(binary_filter_by_price(entries_data, bl, price_threshold))
    IO.puts("Matching entries: #{matching_full} (full), #{matching_binary} (binary)\n")

    Benchee.run(
      %{
        "to_list + Enum.filter" => fn ->
          GridCodec.Group.to_list(group) |> Enum.filter(&(&1.price >= price_threshold))
        end,
        "pre-decoded list + Enum.filter" => fn ->
          Enum.filter(decoded_list, &(&1.price >= price_threshold))
        end,
        "binary scan + filter (no decode)" => fn ->
          binary_filter_by_price(entries_data, bl, price_threshold)
        end,
        "binary scan + selective full decode" => fn ->
          matches = binary_filter_by_price(entries_data, bl, price_threshold)

          Enum.map(matches, fn {idx, _price} ->
            {:ok, entry} = GridCodec.Group.get_entry(group, idx)
            entry
          end)
        end
      },
      warmup: 2, time: 5, memory_time: 1
    )

    # -----------------------------------------------------------------------
    # 3. Matching scenario: find all sell orders (side scan + price/qty extract)
    # -----------------------------------------------------------------------
    IO.puts("\n--- Find all sell orders with price + quantity ---")

    sell_int = 1

    Benchee.run(
      %{
        "to_list + filter side" => fn ->
          GridCodec.Group.to_list(group)
          |> Enum.filter(&(&1.side == :sell))
          |> Enum.map(&{&1.price, &1.quantity})
        end,
        "binary scan side+price+qty (no decode)" => fn ->
          binary_scan_side_and_price(entries_data, bl, sell_int)
        end
      },
      warmup: 2, time: 5, memory_time: 1
    )

    # -----------------------------------------------------------------------
    # 4. Single entry lookup by index
    # -----------------------------------------------------------------------
    IO.puts("\n--- Single entry: random access ---")

    Benchee.run(
      %{
        "Group.get_entry (full decode)" => fn ->
          GridCodec.Group.get_entry(group, 5000)
        end,
        "binary_part price only" => fn ->
          entry_start = 5000 * bl
          <<_::binary-size(@price_offset), price::little-signed-64, _::binary>> =
            binary_part(entries_data, entry_start, bl)
          price
        end,
        "pre-decoded list access" => fn ->
          Enum.at(decoded_list, 5000)
        end
      },
      warmup: 2, time: 5, memory_time: 1
    )
  end
end

LazyDecodeBench.run()
