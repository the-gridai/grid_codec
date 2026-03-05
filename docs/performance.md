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
