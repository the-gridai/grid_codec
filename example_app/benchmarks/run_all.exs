defmodule Bench.RunAll do
  @moduledoc """
  Run all benchmarks in sequence.

  Updated for GridCodec v0.5.0+ API.
  """

  def run do
    IO.puts("""
    ════════════════════════════════════════════════════════════════════════════
    GridCodec Benchmark Suite
    ════════════════════════════════════════════════════════════════════════════

    API Notes (v0.5.0+):
    - encode/1 includes 8-byte header by default
    - decode/1 expects header by default
    - get/2 macro works directly on binary (no wrap needed)
    - Use header: false option for payload-only operations
    """)

    IO.puts("\n── Checking consolidated registry ────────────────────────────────────")
    is_consolidated = GridCodec.Registry.consolidated?()
    IO.puts("Registry consolidated: #{is_consolidated}")

    if not is_consolidated do
      IO.puts("⚠ Warning: Registry not consolidated. Run 'mix compile' first.")
    end

    # Core benchmarks with parameterized data sizes
    IO.puts("\n" <> String.duplicate("═", 80))
    IO.puts("BENCHMARK 1: Parameterized Benchmarks (Small/Medium/Large)")
    IO.puts(String.duplicate("═", 80))
    Code.require_file("config.exs", __DIR__)
    Code.require_file("data_structures.exs", __DIR__)
    Code.require_file("parameterized_bench.exs", __DIR__)

    # Encode/Decode benchmark for example app codecs
    IO.puts("\n" <> String.duplicate("═", 80))
    IO.puts("BENCHMARK 2: Example App Codecs (OrderCreated, TradeExecuted)")
    IO.puts(String.duplicate("═", 80))
    Code.require_file("encode_decode.exs", __DIR__)

    IO.puts("\n" <> String.duplicate("═", 80))
    IO.puts("ALL BENCHMARKS COMPLETE")
    IO.puts(String.duplicate("═", 80))
  end
end

Bench.RunAll.run()
