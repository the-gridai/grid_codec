# Stable benchmark comparison
# Run multiple times to ensure stable results

defmodule Manual.SimpleCodec do
  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  def encode(%{id: id, count: count, flag: flag}) do
    id_val = id || @u64_null
    count_val = count || @u32_null
    flag_byte = case flag do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<id_val::little-64, count_val::little-32, flag_byte::8>>
  end
end

defmodule Manual.MapsGetCodec do
  @u64_null 18_446_744_073_709_551_615
  @u32_null 4_294_967_295
  @bool_null 255

  def encode(data) do
    id_val = case :maps.get(:id, data, @u64_null) do
      nil -> @u64_null
      v -> v
    end
    count_val = case :maps.get(:count, data, @u32_null) do
      nil -> @u32_null
      v -> v
    end
    flag_byte = case :maps.get(:flag, data, @bool_null) do
      true -> 1
      false -> 0
      _ -> @bool_null
    end
    <<id_val::little-64, count_val::little-32, flag_byte::8>>
  end
end

defmodule Generated.SimpleCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

test_data = %{id: 12345, count: 100, flag: true}
iterations = 1_000_000

# Warmup
IO.puts("Warming up...")
for _ <- 1..100_000 do
  Manual.SimpleCodec.encode(test_data)
  Manual.MapsGetCodec.encode(test_data)
  Generated.SimpleCodec.encode(test_data)
end

IO.puts("\nRunning #{iterations} iterations (5 runs each)...\n")

results = for run <- 1..5 do
  {t1, _} = :timer.tc(fn -> for _ <- 1..iterations, do: Manual.SimpleCodec.encode(test_data) end)
  {t2, _} = :timer.tc(fn -> for _ <- 1..iterations, do: Manual.MapsGetCodec.encode(test_data) end)
  {t3, _} = :timer.tc(fn -> for _ <- 1..iterations, do: Generated.SimpleCodec.encode(test_data) end)

  IO.puts("Run #{run}: Pattern=#{Float.round(t1/1000,1)}ms, MapsGet=#{Float.round(t2/1000,1)}ms, GridCodec=#{Float.round(t3/1000,1)}ms")
  {t1, t2, t3}
end

# Calculate averages (exclude first run for warmup effects)
{sum1, sum2, sum3} = results
  |> Enum.drop(1)
  |> Enum.reduce({0, 0, 0}, fn {t1, t2, t3}, {a1, a2, a3} -> {a1+t1, a2+t2, a3+t3} end)

avg1 = sum1 / 4 / 1000
avg2 = sum2 / 4 / 1000
avg3 = sum3 / 4 / 1000

IO.puts("\nAverages (runs 2-5):")
IO.puts("  Pattern match:  #{Float.round(avg1, 1)} ms")
IO.puts("  :maps.get:      #{Float.round(avg2, 1)} ms")
IO.puts("  GridCodec:      #{Float.round(avg3, 1)} ms")
IO.puts("")
IO.puts("Ratios:")
IO.puts("  GridCodec / Pattern: #{Float.round(avg3/avg1, 2)}x")
IO.puts("  GridCodec / MapsGet: #{Float.round(avg3/avg2, 2)}x")
IO.puts("  MapsGet / Pattern:   #{Float.round(avg2/avg1, 2)}x")
