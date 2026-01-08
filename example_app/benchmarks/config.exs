defmodule Bench.Config do
  @moduledoc """
  Parameterized benchmark configuration.

  Allows running benchmarks with different configurations to observe
  performance trends as parameters change.

  Updated for GridCodec v0.5.0+ API:
  - encode/1 includes header by default
  - decode/1 expects header by default
  - get/2 macro works directly on binary (no wrap needed)
  """

  @doc """
  Default benchmark configuration.
  """
  def default do
    %{
      # Iteration counts
      iterations: 1_000_000,
      warmup_iterations: 10_000,

      # Benchmark time (seconds)
      time: 3,
      warmup_time: 1,
      memory_time: 1,

      # Data size presets
      data_sizes: [:small, :medium, :large],

      # Enable/disable specific benchmarks
      benchmarks: %{
        encode: true,
        decode: true,
        dispatch: true,
        zero_copy: true,  # Uses get/2 macro directly on binary
        comparison: true,
        comprehensive: true
      },

      # Output options
      print_config: false,
      save_results: false,
      results_dir: "bench_results"
    }
  end

  @doc """
  Get configuration for a specific data size.
  """
  def for_size(size) when size in [:small, :medium, :large] do
    base = default()

    case size do
      :small ->
        Map.put(base, :data_size, %{
          fixed_fields: 3,
          var_fields: 0,
          string_length: 10,
          description: "Small: 3 fixed fields, no variable fields"
        })

      :medium ->
        Map.put(base, :data_size, %{
          fixed_fields: 7,
          var_fields: 1,
          string_length: 50,
          description: "Medium: 7 fixed fields, 1 variable field"
        })

      :large ->
        Map.put(base, :data_size, %{
          fixed_fields: 15,
          var_fields: 3,
          string_length: 200,
          description: "Large: 15 fixed fields, 3 variable fields"
        })
    end
  end

  @doc """
  Run benchmarks with custom configuration.
  """
  def run_with_config(config \\ default()) do
    config = Map.merge(default(), config)

    IO.puts("""
    ════════════════════════════════════════════════════════════════════════════
    GridCodec Benchmarks - Parameterized Run
    ════════════════════════════════════════════════════════════════════════════

    Configuration:
      Iterations: #{config.iterations}
      Time: #{config.time}s
      Data sizes: #{inspect(config.data_sizes)}

    API Notes (v0.5.0+):
      - encode/1 includes 8-byte header by default
      - decode/1 expects header by default
      - get/2 macro works directly on binary
    """)

    # Run benchmarks for each data size
    for size <- config.data_sizes do
      size_config = for_size(size)
      IO.puts("\n" <> String.duplicate("═", 80))
      IO.puts("Running benchmarks for: #{size_config.data_size.description}")
      IO.puts(String.duplicate("═", 80))

      # Run benchmarks with this size
      run_benchmarks_for_size(size_config)
    end
  end

  defp run_benchmarks_for_size(config) do
    # This will be called by the actual benchmark modules
    config
  end
end
