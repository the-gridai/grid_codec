# IOList vs Binary Concatenation Benchmark
#
# Tests whether :erlang.iolist_to_binary([fixed | groups]) is faster than
# <<fixed::binary, groups::binary>> for combining fixed fields with group data.
#
# Run with: mix run benchmarks/iolist_vs_concat_bench.exs

alias ExampleApp.Events.OrderCreated

IO.puts("IOList vs Binary Concatenation — Encode Strategy Comparison")
IO.puts("=" |> String.duplicate(60))

order = %OrderCreated{
  order_id: :crypto.strong_rand_bytes(16),
  user_id: 12345,
  symbol: "BTC/USD",
  side: :buy,
  price: 1_234_567,
  quantity: 100,
  timestamp: System.system_time(:microsecond),
  flags: 1
}

{:ok, encoded} = OrderCreated.encode(order)
IO.puts("Encoded size: #{byte_size(encoded)} bytes\n")

# Simulate the two strategies at the BEAM level with realistic binary sizes.
# We split the encoded binary into fixed + groups portions to test the
# final assembly step in isolation.

{:ok, payload} = OrderCreated.encode(order, header: false)
fixed_size = OrderCreated.block_length()

fixed_block = binary_part(payload, 0, fixed_size)
groups_bin = binary_part(payload, fixed_size, byte_size(payload) - fixed_size)

IO.puts("Fixed block: #{byte_size(fixed_block)} bytes")
IO.puts("Groups data: #{byte_size(groups_bin)} bytes")
IO.puts("")

# Also test with larger group data (simulating many group entries)
large_groups = :crypto.strong_rand_bytes(4096)
huge_groups = :crypto.strong_rand_bytes(65_536)

Benchee.run(
  %{
    "<<fixed, groups>> (binary concat)" =>
      fn -> <<fixed_block::binary, groups_bin::binary>> end,
    "iolist_to_binary([fixed, groups])" =>
      fn -> :erlang.iolist_to_binary([fixed_block, groups_bin]) end,
    "iolist_to_binary([fixed | [groups]])" =>
      fn -> :erlang.iolist_to_binary([fixed_block | [groups_bin]]) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  title: "Small groups (#{byte_size(groups_bin)} bytes)"
)

Benchee.run(
  %{
    "<<fixed, large_groups>> (binary concat)" =>
      fn -> <<fixed_block::binary, large_groups::binary>> end,
    "iolist_to_binary([fixed, large_groups])" =>
      fn -> :erlang.iolist_to_binary([fixed_block, large_groups]) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  title: "4KB groups"
)

Benchee.run(
  %{
    "<<fixed, huge_groups>> (binary concat)" =>
      fn -> <<fixed_block::binary, huge_groups::binary>> end,
    "iolist_to_binary([fixed, huge_groups])" =>
      fn -> :erlang.iolist_to_binary([fixed_block, huge_groups]) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  title: "64KB groups"
)

# Also test the 3-part case (fixed + groups + var_data)
var_data = :crypto.strong_rand_bytes(128)

Benchee.run(
  %{
    "<<fixed, groups, var>> (binary concat)" =>
      fn -> <<fixed_block::binary, groups_bin::binary, var_data::binary>> end,
    "iolist_to_binary([fixed, groups, var])" =>
      fn -> :erlang.iolist_to_binary([fixed_block, groups_bin, var_data]) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  title: "3-part: fixed + groups + var_data"
)

IO.puts("\nDone!")
