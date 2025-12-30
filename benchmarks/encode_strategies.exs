# Compare different encoding strategies
#
# This script compares various approaches to encoding to identify
# the most efficient code generation strategy.

data = %{id: 12345, count: 100, flag: true}
iterations = 500_000

# Strategy 1: Current GridCodec approach (case per field inside binary)
IO.puts("=== Encoding Strategy Comparison (#{iterations} iterations) ===\n")

{t1, _} = :timer.tc(fn ->
  for _ <- 1..iterations do
    <<
      case Map.get(data, :id, 18446744073709551615) do nil -> 18446744073709551615; v -> v end :: little-64,
      case Map.get(data, :count, 4294967295) do nil -> 4294967295; v -> v end :: little-32,
      case Map.get(data, :flag, 255) do true -> 1; false -> 0; _ -> 255 end :: 8
    >>
  end
end)
IO.puts("1. Current GridCodec (case inside binary): #{t1/1000}ms")

# Strategy 2: Extract values first, then binary (like manual code)
{t2, _} = :timer.tc(fn ->
  for _ <- 1..iterations do
    id = Map.get(data, :id, 18446744073709551615)
    id = if id == nil, do: 18446744073709551615, else: id
    count = Map.get(data, :count, 4294967295)
    count = if count == nil, do: 4294967295, else: count
    flag = Map.get(data, :flag, 255)
    flag_byte = case flag do true -> 1; false -> 0; _ -> 255 end
    <<id::little-64, count::little-32, flag_byte::8>>
  end
end)
IO.puts("2. Extract then binary: #{t2/1000}ms")

# Strategy 3: Direct pattern match on map (only works if all keys present)
{t3, _} = :timer.tc(fn ->
  for _ <- 1..iterations do
    %{id: id, count: count, flag: flag} = data
    flag_byte = case flag do true -> 1; false -> 0; nil -> 255; _ -> 255 end
    <<id::little-64, count::little-32, flag_byte::8>>
  end
end)
IO.puts("3. Pattern match on map: #{t3/1000}ms")

# Strategy 4: Using Map.fetch with default handling
{t4, _} = :timer.tc(fn ->
  for _ <- 1..iterations do
    id = case Map.fetch(data, :id) do {:ok, v} when v != nil -> v; _ -> 18446744073709551615 end
    count = case Map.fetch(data, :count) do {:ok, v} when v != nil -> v; _ -> 4294967295 end
    flag = case Map.fetch(data, :flag) do
      {:ok, true} -> 1
      {:ok, false} -> 0
      _ -> 255
    end
    <<id::little-64, count::little-32, flag::8>>
  end
end)
IO.puts("4. Map.fetch with guards: #{t4/1000}ms")

# Strategy 5: No nil handling (assume all values present and valid)
{t5, _} = :timer.tc(fn ->
  for _ <- 1..iterations do
    id = Map.get(data, :id)
    count = Map.get(data, :count)
    flag = if Map.get(data, :flag), do: 1, else: 0
    <<id::little-64, count::little-32, flag::8>>
  end
end)
IO.puts("5. Simple Map.get (no nil): #{t5/1000}ms")

# Strategy 6: Absolute minimum - pre-extracted values
id = 12345
count = 100
flag_byte = 1
{t6, _} = :timer.tc(fn ->
  for _ <- 1..iterations do
    <<id::little-64, count::little-32, flag_byte::8>>
  end
end)
IO.puts("6. Pre-extracted (baseline): #{t6/1000}ms")

# Strategy 7: Map.get with || for nil substitution (integers only)
{t7, _} = :timer.tc(fn ->
  for _ <- 1..iterations do
    id = Map.get(data, :id) || 18446744073709551615
    count = Map.get(data, :count) || 4294967295
    flag = Map.get(data, :flag)
    flag_byte = case flag do true -> 1; false -> 0; _ -> 255 end
    <<id::little-64, count::little-32, flag_byte::8>>
  end
end)
IO.puts("7. Map.get with ||: #{t7/1000}ms")

IO.puts("\n=== Summary ===")
baseline = t6
IO.puts("Baseline (pre-extracted): #{baseline/1000}ms")
IO.puts("Overhead of each strategy vs baseline:")
IO.puts("  1. Current GridCodec: +#{Float.round((t1-baseline)/baseline*100, 1)}%")
IO.puts("  2. Extract then binary: +#{Float.round((t2-baseline)/baseline*100, 1)}%")
IO.puts("  3. Pattern match: +#{Float.round((t3-baseline)/baseline*100, 1)}%")
IO.puts("  4. Map.fetch: +#{Float.round((t4-baseline)/baseline*100, 1)}%")
IO.puts("  5. Simple Map.get: +#{Float.round((t5-baseline)/baseline*100, 1)}%")
IO.puts("  7. Map.get with ||: +#{Float.round((t7-baseline)/baseline*100, 1)}%")
