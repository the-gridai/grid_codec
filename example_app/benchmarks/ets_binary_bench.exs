# ETS Binary-First Benchmark
#
# Demonstrates and measures GridCodec's advantages when using ETS as a
# binary-native message store (like OTel's batch span processor pattern).
#
# Run from example_app/:
#   MIX_ENV=prod mix run benchmarks/ets_binary_bench.exs

alias ExampleApp.Bench.BinaryTraceContext

IO.puts("""
ETS Binary-First Benchmark
==================================================
Comparing struct-based vs binary-based ETS patterns.

The OTel batch span processor stores spans as Erlang records in ETS.
Reading them back copies the full record into the reader's heap.
GridCodec binaries stored in ETS are shared via refc pointers.
""")

# =============================================================================
# Setup: generate test data
# =============================================================================

n_spans = 10_000

struct_spans =
  for i <- 1..n_spans do
    now = System.system_time(:nanosecond)

    struct!(BinaryTraceContext,
      trace_id: :crypto.strong_rand_bytes(16),
      span_id: i,
      parent_span_id: max(i - 1, 0),
      flags: rem(i, 4),
      kind: rem(i, 5),
      start_time_ns: now,
      end_time_ns: now + :rand.uniform(10_000_000),
      name: "span.operation.#{rem(i, 20)}"
    )
  end

binary_spans =
  Enum.map(struct_spans, fn s ->
    {:ok, bin} = BinaryTraceContext.encode(s)
    bin
  end)

sample_struct = hd(struct_spans)
sample_binary = hd(binary_spans)

require BinaryTraceContext

IO.puts("Data: #{n_spans} spans")
IO.puts("Struct size (ETF): #{byte_size(:erlang.term_to_binary(sample_struct))} bytes")
IO.puts("Binary size: #{byte_size(sample_binary)} bytes\n")

# =============================================================================
# Benchmark 1: ETS Insert
# =============================================================================

IO.puts("=== 1: ETS Insert (#{n_spans} spans) ===\n")

Benchee.run(
  %{
    "Struct → ETS (term copy)" => fn ->
      tab = :ets.new(:bench_s, [:set, :public])
      Enum.each(struct_spans, fn s -> :ets.insert(tab, {s.span_id, s}) end)
      :ets.delete(tab)
    end,
    "Binary → ETS (refc pointer)" => fn ->
      tab = :ets.new(:bench_b, [:set, :public])

      binary_spans
      |> Enum.with_index(1)
      |> Enum.each(fn {bin, i} -> :ets.insert(tab, {i, bin}) end)

      :ets.delete(tab)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2
)

# =============================================================================
# Benchmark 2: ETS Read (single lookup)
# =============================================================================

IO.puts("\n=== 2: ETS Single Lookup + Field Access ===\n")

struct_tab = :ets.new(:struct_tab, [:set, :public])
Enum.each(struct_spans, fn s -> :ets.insert(struct_tab, {s.span_id, s}) end)

binary_tab = :ets.new(:binary_tab, [:set, :public])

binary_spans
|> Enum.with_index(1)
|> Enum.each(fn {bin, i} -> :ets.insert(binary_tab, {i, bin}) end)

Benchee.run(
  %{
    "Struct: ets.lookup + .flags" => fn ->
      [{_, s}] = :ets.lookup(struct_tab, 42)
      s.flags
    end,
    "Binary: ets.lookup + get(:flags)" => fn ->
      [{_, bin}] = :ets.lookup(binary_tab, 42)
      BinaryTraceContext.get(bin, :flags)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 1
)

# =============================================================================
# Benchmark 3: ETS Scan + Filter (the big win)
# =============================================================================

IO.puts("\n=== 3: Full Table Scan + Filter (find sampled spans) ===\n")

IO.puts("Filtering #{n_spans} spans for flags == 1 (approx 25% match)\n")

Benchee.run(
  %{
    "Struct: ets.foldl + .flags" => fn ->
      :ets.foldl(
        fn {_k, s}, acc -> if s.flags == 1, do: [s | acc], else: acc end,
        [],
        struct_tab
      )
    end,
    "Binary: ets.foldl + get(:flags)" => fn ->
      :ets.foldl(
        fn {_k, bin}, acc ->
          if BinaryTraceContext.get(bin, :flags) == 1, do: [bin | acc], else: acc
        end,
        [],
        binary_tab
      )
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2
)

# =============================================================================
# Benchmark 4: Double-buffer export (OTel batch processor pattern)
# =============================================================================

IO.puts("\n=== 4: Double-Buffer Export (OTel batch processor pattern) ===\n")

IO.puts("""
Simulates the OTel batch processor: fill a table, swap to new table,
read all entries from the old table for export. Measures the read cost.
""")

struct_export_tab = :ets.new(:struct_export, [:set, :public])
Enum.each(struct_spans, fn s -> :ets.insert(struct_export_tab, {s.span_id, s}) end)

binary_export_tab = :ets.new(:binary_export, [:set, :public])

binary_spans
|> Enum.with_index(1)
|> Enum.each(fn {bin, i} -> :ets.insert(binary_export_tab, {i, bin}) end)

Benchee.run(
  %{
    "Struct: tab2list (deep copy all)" => fn ->
      :ets.tab2list(struct_export_tab)
    end,
    "Binary: tab2list (refc shared)" => fn ->
      :ets.tab2list(binary_export_tab)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2
)

# =============================================================================
# Benchmark 5: Cross-field filter (where GridCodec.Match shines)
# =============================================================================

IO.puts("\n=== 5: Cross-Field Filter (slow spans: end - start > 5ms) ===\n")

# Define a match filter inline
defmodule BenchFilters do
  use GridCodec.Match

  defmatch :slow?, BinaryTraceContext do
    where end_time_ns - start_time_ns > 5_000_000
  end
end

Benchee.run(
  %{
    "Struct: full field access + comparison" => fn ->
      :ets.foldl(
        fn {_k, s}, acc ->
          if s.end_time_ns - s.start_time_ns > 5_000_000, do: [s | acc], else: acc
        end,
        [],
        struct_tab
      )
    end,
    "Binary: GridCodec.Match defmatch" => fn ->
      :ets.foldl(
        fn {_k, bin}, acc ->
          if BenchFilters.slow?(bin), do: [bin | acc], else: acc
        end,
        [],
        binary_tab
      )
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2
)

# Cleanup
:ets.delete(struct_tab)
:ets.delete(binary_tab)
:ets.delete(struct_export_tab)
:ets.delete(binary_export_tab)

IO.puts("""

==================================================
Key Takeaways
==================================================

1. ETS INSERT: Binary insert is faster because ETS stores a reference to the
   refc binary, not a deep copy. Struct insert copies the entire term.

2. SINGLE LOOKUP: Binary + get(:flags) avoids copying the full struct into
   the reader's heap. Only the field bytes are read.

3. FULL SCAN + FILTER: The binary path wins because each ets.foldl iteration
   only needs to share a refc pointer + read 4 bytes (flags offset).
   The struct path copies each struct into the fold process's heap.

4. BATCH EXPORT: tab2list on binaries returns refc-shared references.
   tab2list on structs deep-copies every term. At 10K spans, this matters.

5. CROSS-FIELD FILTER: GridCodec.Match generates efficient binary extraction
   at compile-time offsets. No full decode needed for the comparison.

Pattern for OTel-style batch processing:
  1. Encode spans to GridCodec binary on creation
  2. Store binaries in ETS (insert is a pointer store)
  3. On export timer: swap tables, tab2list old table (refc shared)
  4. Filter with GridCodec.Match predicates (no decode)
  5. Transcode matched spans to protobuf via GridCodec.Transcoder
""")
