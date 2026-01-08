defmodule Bench.Parameterized do
  @moduledoc """
  Parameterized benchmark suite that runs benchmarks across different
  configurations to observe performance trends.

  Updated for GridCodec v0.5.0+ API:
  - encode/1 includes header by default
  - decode/1 expects header by default
  - get/2 macro works directly on binary (no wrap needed)
  """

  alias Bench.DataStructures
  alias Bench.Config

  def run(config \\ Config.default()) do
    IO.puts("""
    ════════════════════════════════════════════════════════════════════════════
    GridCodec Parameterized Benchmarks
    ════════════════════════════════════════════════════════════════════════════

    Configuration:
      Iterations: #{config.iterations}
      Time: #{config.time}s
      Data sizes: #{inspect(config.data_sizes)}
    """)

    results = %{}

    # Run benchmarks for each data size
    results =
      Enum.reduce(config.data_sizes, results, fn size, acc ->
        IO.puts("\n" <> String.duplicate("═", 80))
        IO.puts("DATA SIZE: #{String.upcase(to_string(size))}")
        IO.puts(String.duplicate("═", 80))

        {data, module} = DataStructures.get_for_size(size)
        binary_size = DataStructures.binary_size(size)

        IO.puts("Binary size: #{binary_size} bytes")
        IO.puts("Fields: #{inspect(module.__fields__())}\n")

        size_results = run_size_benchmarks(data, module, size, config)
        Map.put(acc, size, size_results)
      end)

    # Print summary
    print_summary(results)
    results
  end

  defp run_size_benchmarks(data, module, _size, config) do
    # encode/1 now includes header by default
    # For payload-only, use encode(struct, header: false)
    binary = module.encode(data)
    binary_no_header = module.encode(data, header: false)

    results = %{}

    # Encode benchmark
    if config.benchmarks.encode do
      IO.puts("── Encode Performance ────────────────────────────────────────────────")

      require module

      encode_results = Benchee.run(
        %{
          "Direct.encode (with header)" => fn -> module.encode(data) end,
          "Direct.encode (no header)" => fn -> module.encode(data, header: false) end,
          "GridCodec.encode (dispatch)" => fn -> GridCodec.encode(data) end
        },
        time: config.time,
        warmup: config.warmup_time,
        memory_time: config.memory_time,
        print: [configuration: config.print_config]
      )
      results = Map.put(results, :encode, encode_results)
    end

    # Decode benchmark
    if config.benchmarks.decode do
      IO.puts("\n── Decode Performance ────────────────────────────────────────────────")

      require module

      decode_results = Benchee.run(
        %{
          "Direct.decode (with header)" => fn -> module.decode(binary) end,
          "Direct.decode (no header)" => fn -> module.decode(binary_no_header, header: false) end,
          "GridCodec.decode (dispatch)" => fn -> GridCodec.decode(binary) end
        },
        time: config.time,
        warmup: config.warmup_time,
        memory_time: config.memory_time,
        print: [configuration: config.print_config]
      )
      results = Map.put(results, :decode, decode_results)
    end

    # Zero-copy get benchmark (uses get/2 macro directly on binary)
    if config.benchmarks.zero_copy do
      IO.puts("\n── Zero-Copy Get Performance ──────────────────────────────────────────")

      require module

      first_field = List.first(module.__fields__())

      if first_field do
        get_results = Benchee.run(
          %{
            # get/2 macro works directly on binary (with header by default)
            "get(#{first_field}) [with header]" => fn -> module.get(binary, first_field) end,
            # For payload-only binary, use header: false
            "get(#{first_field}) [no header]" => fn -> module.get(binary_no_header, first_field, header: false) end
          },
          time: config.time,
          warmup: config.warmup_time,
          memory_time: config.memory_time,
          print: [configuration: config.print_config]
        )
        results = Map.put(results, :zero_copy, get_results)
      end
    end

    results
  end

  defp print_summary(results) do
    IO.puts("\n" <> String.duplicate("═", 80))
    IO.puts("PERFORMANCE SUMMARY BY DATA SIZE")
    IO.puts(String.duplicate("═", 80))

    for {size, size_results} <- results do
      IO.puts("\n#{String.upcase(to_string(size))}:")

      if encode = size_results[:encode] do
        stats = Benchee.Statistics.statistics(encode.scenarios)
        best = List.first(stats)
        IO.puts("  Encode: #{format_ips(best.ips)} (#{format_ns(best.average)} ns/op)")
      end

      if decode = size_results[:decode] do
        stats = Benchee.Statistics.statistics(decode.scenarios)
        best = List.first(stats)
        IO.puts("  Decode: #{format_ips(best.ips)} (#{format_ns(best.average)} ns/op)")
      end

      if zero_copy = size_results[:zero_copy] do
        stats = Benchee.Statistics.statistics(zero_copy.scenarios)
        best = List.first(stats)
        IO.puts("  Get:    #{format_ips(best.ips)} (#{format_ns(best.average)} ns/op)")
      end
    end
  end

  defp format_ips(ips) when ips >= 1_000_000, do: "#{Float.round(ips / 1_000_000, 2)}M ips"
  defp format_ips(ips) when ips >= 1_000, do: "#{Float.round(ips / 1_000, 2)}K ips"
  defp format_ips(ips), do: "#{Float.round(ips, 2)} ips"

  defp format_ns(ns), do: "#{Float.round(ns, 1)}"
end

# Run if executed directly
if System.argv() != [] or true do
  # Load dependencies first
  Code.require_file("config.exs", __DIR__)
  Code.require_file("data_structures.exs", __DIR__)

  config = Bench.Config.default()
  Bench.Parameterized.run(config)
end
