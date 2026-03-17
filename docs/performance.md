# Performance Guide

GridCodec is optimized for high-throughput BEAM workloads. All encode/decode
code is generated at compile time with inline AST — no runtime function calls
in the hot path.

## Baseline Numbers (Apple M3 Max, OTP 28, JIT enabled)

Quick verification: `cd example_app && mix run benchmarks/quick_bench.exs`. Full comparison vs Ecto/JSON: `mix run benchmarks/ecto_comparison.exs`.

| Operation | Latency | Throughput |
|-----------|---------|------------|
| Simple encode (6 fields) | 265 ns | 3.8M ops/sec |
| Simple decode | 344 ns | 2.9M ops/sec |
| `get/2` (zero-copy field access) | 38 ns | 26.7M ops/sec |
| `new/1` (coerce + validate) | 375 ns | 2.7M ops/sec |
| `new_binary/1` (coerce + validate + encode) | 376 ns | 2.7M ops/sec |
| `content_hash/1` | 350 ns | 2.9M ops/sec |
| `decode_only/2` (1 field) | 85 ns | 11.8M ops/sec |

## Group Performance (TradingPeriodSettled shape, positive_decimal + enums)

| Scenario | Encode | Decode+list | Roundtrip |
|----------|--------|-------------|-----------|
| Small (250 entries) | 34 µs | 19 µs | 55 µs |
| Medium (2,500 entries) | 0.94 ms | 0.27 ms | 1.1 ms |
| Large (12,000 entries) | 4.7 ms | 3.9 ms | 9.5 ms |
| Huge (55,000 entries) | 34 ms | 25 ms | 69 ms |

## vs Alternatives

GridCodec is compared against common serialization approaches on the same
8-field struct (order event with UUID, integers, string, enum, timestamp):

### Construction: `new/1` vs Ecto Changeset

| Operation | Latency | Memory |
|-----------|---------|--------|
| `MyCodec.new/1` (typed) | 0.55 us | 1.5 KB |
| Ecto changeset + apply_action | 2.1 us | 5.0 KB |
| **Speedup** | **3.8x** | **3.4x less** |

### Full Pipeline: attrs -> wire format

| Operation | Latency | Memory | Wire size |
|-----------|---------|--------|-----------|
| `MyCodec.new_binary/1` | 345 ns | 0.8 KB | 63 B |
| Ecto changeset + Jason.encode | 4,142 ns | 7.1 KB | 170 B |
| **Speedup** | **12x** | **9.2x less** | **2.7x smaller** |

### Encode (struct already constructed)

| Operation | Latency | Memory |
|-----------|---------|--------|
| `GridCodec.encode/1` | 0.40 us | 0.4 KB |
| Jason.encode! | 1.17 us | 1.8 KB |
| **Speedup** | **3x** | **4x less** |

### Decode

| Operation | Latency | Memory |
|-----------|---------|--------|
| `GridCodec.decode/1` | 0.16 us | 0.5 KB |
| Jason.decode! | 1.13 us | 1.1 KB |
| **Speedup** | **7.2x** | **2.1x less** |

### Single Field Access

| Method | Latency |
|--------|---------|
| `GridCodec.get/2` (zero-copy) | 31 ns |
| JSON decode + map access | 1,239 ns |
| **Speedup** | **40x** |

Run comparisons yourself: `cd example_app && mix run benchmarks/ecto_comparison.exs`

For format comparison (vs Protobuf, ETF, MessagePack): `mix run benchmarks/format_comparison.exs`

## Validation Pipeline Baseline

Validation pipelines now have a dedicated benchmark:

```bash
cd example_app
MIX_ENV=prod mix run benchmarks/validation_bench.exs
```

Reference run on Apple M3 Max, OTP 28.3, Elixir 1.19.4:

### Struct validation, happy path

| Method | Throughput | Average |
|--------|------------|---------|
| Hand-rolled struct validation | 24.56 M ips | 40.72 ns |
| Generated `validate_struct/1` | 14.08 M ips | 71.02 ns |
| Map validators (anonymous fns) | 13.04 M ips | 76.69 ns |

### Binary validation, happy path

| Method | Throughput | Average |
|--------|------------|---------|
| Hand-rolled binary pattern | 23.11 M ips | 43.27 ns |
| `validate_struct/1` on decoded struct | 14.35 M ips | 69.71 ns |
| Decode + hand-rolled struct validation | 9.58 M ips | 104.37 ns |
| Generated `validate_binary/1` | 8.97 M ips | 111.44 ns |

### Why this benchmark exists

This benchmark is a correctness and optimization guardrail, not just a vanity
number. Generated validation should stay competitive with hand-rolled code and
should beat generic map validation pipelines built from anonymous functions
where the compiler has enough static information to specialize the checks.

Current takeaways:

- `validate_struct/1` now beats the generic map-validator pipeline on the happy
  path while using less memory, but still trails fully hand-rolled struct
  checks.
- `validate_binary/1` is now close to the `decode + hand-rolled struct
  validation` path, but still behind a fully specialized hand-written binary
  pattern match.
- Failure-path allocation is still higher than the hand-rolled baseline, so
  there is remaining headroom in accumulated-error construction.

## Choosing the Right Constructor

| Function | When to use | Latency | Memory |
|----------|-------------|---------|--------|
| `new_binary/1` | Write path — need binary, not struct | 376 ns | 512 B |
| `new/1` | Need the struct for further processing | 375 ns | 1.2 KB |
| `encode/1` | Already have a struct | 265 ns | 104 B |
| `%Module{}` + `encode/1` | Trusted internal code | 265 ns | 104 B |

`new_binary/1` produces the binary directly with **2.7x less memory** than
`new/1` + `encode/1` because there's no intermediate struct allocation.

## Use `decode_only/2` for Partial Reads

When you only need 1-3 fields from a binary, `decode_only` is faster than
full decode because it skips all other fields:

```elixir
{:ok, %{price: price, side: side}} = MyCodec.decode_only(binary, [:price, :side])
```

Use lookups when you need a reusable alternate access path over a decoded group or batch:

```elixir
{:ok, account} = AccountCodec.decode(binary)
{:ok, reservations_by_id} = AccountCodec.reservations_by_id(account)
```

Lookups are not a replacement for `decode_only/2`. They operate on decoded
collection fields and are best when the same projection logic would otherwise be
rewritten as `GridCodec.Group.to_list(...) |> Map.new(...)` in multiple places.

For keyed group projections, generated lookups use last-write-wins semantics. In
the reference `example_app` benchmark on an Apple M3 Max, a generated
typed-group map lookup beat the equivalent manual
`GridCodec.Group.to_list(...) |> Map.new(...)` pipeline (`5.69 ms`, `6.94 MB`
versus `6.21 ms`, `8.49 MB`). The generated filtered list lookup also beat the
manual `to_list |> Enum.filter` path (`3.47 ms`, `6.19 MB` versus
`4.67 ms`, `7.81 MB`).

Run the comparison yourself with:

```bash
cd example_app
MIX_ENV=prod mix run benchmarks/lookup_bench.exs
```

## Use `get/2` for Single Field Hot Reads

For fixed-size fields, zero-copy access is the fastest option:

```elixir
require MyCodec
price = MyCodec.get(binary, :price)  # 38 ns, zero allocation
```

## Parallel Group Decode

For large groups (>256KB total data), decode multiple groups in parallel:

```elixir
[balances, orders] = GridCodec.Group.to_lists_parallel([data.balances, data.orders])
```

This spawns one process per group with pre-sized heaps. Benchmarked 1.73x
faster for 55k entries. Falls back to sequential for small groups.

## Type Selection for Performance

| Type | Encode cost | Decode cost | Use when |
|------|-------------|-------------|----------|
| `:i64` / `:u64` | ~2 ns | ~2 ns | Fixed-point integers, timestamps |
| `:positive_decimal` | ~50 ns | ~100 ns | Financial values (positive only) |
| `:decimal` | ~60 ns | ~120 ns | Financial values (signed) |
| `:uuid` | ~5 ns | ~5 ns | Internal binary IDs |
| `:uuid_string` | ~5 ns | ~80 ns | Human-readable UUID output |
| Custom enum | ~5 ns | ~5 ns | Small value sets (:buy/:sell) |

For maximum throughput, use `:i64` for monetary values (fixed-point integers)
and `:uuid` for IDs. The `%Decimal{}` struct allocation dominates decode cost.

## Memory & Binary Lifecycle

Understanding how the BEAM manages binary memory is critical for getting the
most out of GridCodec in production.

### Refc Binaries and Zero-Copy Sends

Binaries > 64 bytes are **reference-counted** (refc binaries). The payload lives
in a shared binary allocator; each process holds only a small `ProcBin`
reference (~5 words) on its heap.

GridCodec encoded structs are almost always > 64 bytes, which means:

- **Sending is O(1)**: `send(pid, encoded_binary)` copies only the ProcBin
  pointer, not the payload. This is why "encode once, fan out to N processes"
  is so effective.
- **ETS insertion is O(1)**: `ets:insert` also creates a ProcBin reference,
  not a full copy of the binary data.
- **GC doesn't touch the payload**: Only the ProcBin linked list is scanned
  during garbage collection. The binary payload is freed when the last
  ProcBin reference is collected.

### Sub-Binary Retention (The "Chapter from a Book" Problem)

When `get/2` extracts a binary-typed field (`:uuid`, `char_array`), the result
is a **sub-binary** — a lightweight pointer into the original encoded binary.
This sub-binary keeps the *entire* original alive:

```elixir
# This 16-byte sub-binary pins the full ~200 byte encoded binary in memory
uuid = MyCodec.get(large_binary, :trace_id)
large_binary = nil  # Doesn't help — uuid still references it!
```

This matters most when:

1. **Scanning groups**: Iterating over a 100KB group, extracting one UUID per
   entry — every group binary stays pinned
2. **ETS lookup + extract**: Fetching a binary from ETS, extracting one field,
   discarding the binary — the sub-binary pins it
3. **Long-lived references**: Storing extracted UUIDs in a GenServer state while
   the source binaries are no longer needed

**Fix with `copy: true`:**

```elixir
require MyCodec
uuid = MyCodec.get(binary, :trace_id, copy: true)
```

Or use `GridCodec.Binary.detach/1` after full decode:

```elixir
{:ok, struct} = MyCodec.decode(large_binary)
struct = GridCodec.Binary.detach(struct)
```

**Types affected**: `:uuid` and `char_array(N)` return sub-binaries.
**Types NOT affected**: All integer types, `:bool`, `:decimal`, floats,
`:uuid_string` (creates a new formatted string), timestamps.

### Message Queue Strategy

For high-throughput GridCodec consumers, consider the `message_queue_data`
process flag:

```elixir
spawn_opt(fn -> consumer_loop() end, [message_queue_data: :off_heap])
```

- **`:on_heap`** (default): sender tries to write directly to receiver's heap.
  Lower latency when the lock is available.
- **`:off_heap`**: sender allocates a heap fragment without locking. Reduces
  contention when the receiver is processing heavily.

Since GridCodec binaries are refc, the "message" being copied is just the
ProcBin pointer either way — the main benefit of `:off_heap` is avoiding
the main lock on the receiver.

### Binary Virtual Heap and GC Tuning

Each process tracks refc binary references in a **binary virtual heap**
(`bin_vheap_sz`). When accumulated binary references exceed this threshold,
GC is triggered to sweep dead ProcBin references and decrement refcounts.

For processes that create and discard many GridCodec binaries:

```elixir
spawn_opt(fn -> encoder_loop() end, [min_bin_vheap_size: 100_000])
```

The default `min_bin_vheap_size` (46422 words) works for most workloads. Only
tune this if profiling shows excessive minor GCs in binary-heavy processes.

### The Load Balancer Anti-Pattern

A process that receives GridCodec binaries and forwards them (router, load
balancer) accumulates ProcBin references without GC pressure:

```elixir
# This process never allocates — GC may not run for a long time
def loop(workers, n) do
  receive do
    binary ->
      Enum.at(workers, n) |> send(binary)
      loop(workers, rem(n + 1, length(workers)))
  end
end
```

Fix: trigger GC periodically or use `hibernate` in the receive timeout:

```elixir
receive do
  binary -> forward(binary)
after
  5_000 -> :erlang.garbage_collect(); loop(workers, n)
end
```

### Distribution: GridCodec is Wire-Efficient

When sending between Erlang nodes, terms go through `term_to_binary` for the
wire. A raw binary has minimal ETF overhead (tag + length prefix), while
maps/structs have per-field overhead. Sending a GridCodec binary between nodes
is more efficient than sending the equivalent Elixir struct.

The inter-node buffer is 128MB by default. Tune with `+zdbbl` if sending
large batches of GridCodec binaries between nodes:

```
erl +zdbbl 256000   # 256MB buffer
```

## Telemetry

Enable per-module for production latency tracking:

```elixir
use GridCodec.Struct, telemetry: true, telemetry_min_duration: 10_000
```

`telemetry_min_duration` filters out cheap operations so histograms focus
on the latency you care about. Zero overhead when disabled.

## Profiling

Use tprof for identifying bottlenecks:

```elixir
Mix.Tasks.Profile.Tprof.profile(fn -> work end,
  type: :time, sort: :time, report: :total, set_on_spawn: false)
```

Use Benchee for measuring improvements:

```elixir
Benchee.run(%{"name" => fn -> work end}, warmup: 2, time: 5, memory_time: 1)
```

Benchmark scripts in `example_app/benchmarks/`:
- `quick_bench.exs` — simple codec baseline
- `group_bench.exs` — realistic exchange shapes
- `group_profile.exs` — tprof time + memory analysis
- `constructor_bench.exs` — new/1, new_binary, validation, content_hash
- `lazy_decode_bench.exs` — binary scan vs decoded map access
- `parallel_decode_bench.exs` — parallel vs sequential group decode
- `ecto_comparison.exs` — GridCodec vs Ecto changeset + JSON
- `format_comparison.exs` — GridCodec vs Protobuf, ETF, MessagePack, JSON

## Production Monitoring

### Binary Memory

Monitor total binary allocator usage:

```elixir
:erlang.memory(:binary)
```

Track per-process binary references to find processes retaining large binaries:

```elixir
Process.info(pid, :binary)
# Returns list of {binary_id, size, refcount} tuples
```

### Detecting Binary Leaks

Use `recon` to find processes whose binary memory grows between GC cycles:

```elixir
:recon.bin_leak(10)  # Top 10 processes by binary growth
```

Common causes of binary leaks with GridCodec:

1. **Router processes** that forward binaries without GC (see load balancer
   anti-pattern above)
2. **GenServer state** accumulating sub-binary references from `get/2` calls
3. **ETS tables** growing without cleanup — each entry's binary stays in
   `binary_alloc`

### BEAM Allocator Flags

For systems with heavy GridCodec binary workloads, these VM flags may help:

| Flag | Default | Description |
|------|---------|-------------|
| `+MBas bf` | best fit | Binary allocator strategy |
| `+MBsbct 512` | varies | Singleblock carrier threshold (KB) |
| `+MBlmbcs 8192` | varies | Max multiblock carrier size (KB) |
| `+zdbbl 128000` | 128MB | Distribution buffer size (KB) |
| `+hmqd off_heap` | on_heap | Default message queue strategy |

Only tune these after profiling with `recon_alloc:memory/1` and
`recon_alloc:fragmentation/1`. The defaults work well for most workloads.
