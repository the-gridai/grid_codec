# Benchmark: Single binary construction vs IOData
#
# Run: cd example_app && mix run benchmarks/iodata_vs_binary.exs

# Sample data (simulating OrderCreated fields)
order_id = :crypto.strong_rand_bytes(16)
user_id = 12_345_678_901_234_567
side = 1
price = 15_000_000_000
quantity = 100_000
timestamp = System.system_time(:microsecond)
flags = 7

# String field (variable length)
symbol = "BTCUSD"
symbol_len = byte_size(symbol)

IO.puts("\n=== Binary Construction Methods ===\n")

Benchee.run(
  %{
    # How GridCodec does it: single binary construction
    "single_binary" => fn ->
      <<
        order_id::binary-16,
        user_id::little-64,
        side::8,
        price::little-64,
        quantity::little-32,
        timestamp::little-signed-64,
        flags::8,
        symbol_len::little-16,
        symbol::binary
      >>
    end,

    # Alternative: build as iodata, convert to binary
    "iodata_to_binary" => fn ->
      IO.iodata_to_binary([
        order_id,
        <<user_id::little-64>>,
        <<side::8>>,
        <<price::little-64>>,
        <<quantity::little-32>>,
        <<timestamp::little-signed-64>>,
        <<flags::8>>,
        <<symbol_len::little-16>>,
        symbol
      ])
    end,

    # IOData left as-is (for socket send)
    "iodata_only" => fn ->
      [
        order_id,
        <<user_id::little-64>>,
        <<side::8>>,
        <<price::little-64>>,
        <<quantity::little-32>>,
        <<timestamp::little-signed-64>>,
        <<flags::8>>,
        <<symbol_len::little-16>>,
        symbol
      ]
    end,

    # What if we pre-build the fixed block?
    "fixed_block_plus_var" => fn ->
      fixed = <<
        order_id::binary-16,
        user_id::little-64,
        side::8,
        price::little-64,
        quantity::little-32,
        timestamp::little-signed-64,
        flags::8
      >>

      var_data = <<symbol_len::little-16, symbol::binary>>
      <<fixed::binary, var_data::binary>>
    end,

    # IOData with pre-built fixed block
    "fixed_block_iodata" => fn ->
      fixed = <<
        order_id::binary-16,
        user_id::little-64,
        side::8,
        price::little-64,
        quantity::little-32,
        timestamp::little-signed-64,
        flags::8
      >>

      [fixed, <<symbol_len::little-16>>, symbol]
    end
  },
  warmup: 1,
  time: 3,
  memory_time: 1
)

IO.puts("\n=== With Multiple Variable Fields ===\n")

# More realistic: multiple variable-length fields
symbol2 = "ETHUSD"
description = "Limit order for BTC/USD pair"

Benchee.run(
  %{
    "single_binary_multivar" => fn ->
      <<
        order_id::binary-16,
        user_id::little-64,
        side::8,
        price::little-64,
        quantity::little-32,
        timestamp::little-signed-64,
        flags::8,
        byte_size(symbol)::little-16,
        symbol::binary,
        byte_size(symbol2)::little-16,
        symbol2::binary,
        byte_size(description)::little-16,
        description::binary
      >>
    end,
    "iodata_to_binary_multivar" => fn ->
      fixed = <<
        order_id::binary-16,
        user_id::little-64,
        side::8,
        price::little-64,
        quantity::little-32,
        timestamp::little-signed-64,
        flags::8
      >>

      IO.iodata_to_binary([
        fixed,
        <<byte_size(symbol)::little-16>>,
        symbol,
        <<byte_size(symbol2)::little-16>>,
        symbol2,
        <<byte_size(description)::little-16>>,
        description
      ])
    end,
    "iodata_only_multivar" => fn ->
      fixed = <<
        order_id::binary-16,
        user_id::little-64,
        side::8,
        price::little-64,
        quantity::little-32,
        timestamp::little-signed-64,
        flags::8
      >>

      [
        fixed,
        <<byte_size(symbol)::little-16>>,
        symbol,
        <<byte_size(symbol2)::little-16>>,
        symbol2,
        <<byte_size(description)::little-16>>,
        description
      ]
    end
  },
  warmup: 1,
  time: 3,
  memory_time: 1
)
