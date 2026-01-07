# Maps vs GridCodec Binary Access Benchmark Results

**Date**: January 7, 2026  
**System**: Darwin (macOS)  
**Elixir/OTP**: As configured in project

Based on the classic [Elixir Forum discussion](https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909/6) and [akoutmos's benchmark gist](https://gist.github.com/akoutmos/6e965558fa8bb5771e90b1961762a7d0).

---

## Key Finding: Use the `match` Macro for Best Performance!

The `match` macro provides **direct binary pattern matching** at compile-time offsets, avoiding the envelope dispatch overhead.

```elixir
# Direct binary match - FAST!
case binary do
  MyCodec.match(field_1: value, field_4: other) -> {value, other}
end

# Envelope get/2 - 2.5x slower due to struct dispatch
env = MyCodec.wrap(binary)
MyCodec.get(env, :field_1)
```

---

## Part 1: Direct Binary Match vs Map.get

### Small (8 fields)

| Benchmark | ips | avg (ns) | vs fastest |
|-----------|-----|----------|------------|
| Map.get field_8 | 102.03 M | 9.80 | baseline |
| **match field_4** | **60.43 M** | **16.55** | 1.69x slower |
| **match field_1** | **59.50 M** | **16.81** | 1.71x slower |
| **match field_8** | **41.49 M** | **24.10** | 2.46x slower |
| Map.get field_4 | 32.51 M | 30.76 | 3.14x slower |
| Map.get field_1 | 31.35 M | 31.90 | 3.25x slower |

**Finding**: Direct `match` is **faster than Map.get** for mid/early fields (field_1, field_4)!

### Medium (32 fields - flat map limit)

| Benchmark | ips | avg (ns) | vs fastest |
|-----------|-----|----------|------------|
| Map.get field_16 | 70.77 M | 14.13 | baseline |
| **match field_32** | **66.08 M** | **15.13** | **1.07x slower** |
| **match field_1** | **63.52 M** | **15.74** | **1.11x slower** |
| Map.get field_1 | 59.37 M | 16.84 | 1.19x slower |
| Map.get field_32 | 45.39 M | 22.03 | 1.56x slower |

**Finding**: `match` is **nearly as fast as Map.get** and shows consistent O(1) performance!

### Large (33 fields - HAMT)

| Benchmark | ips | avg (ns) | vs fastest |
|-----------|-----|----------|------------|
| Map.get field_33 | 97.22 M | 10.29 | baseline |
| Map.get field_16 | 96.65 M | 10.35 | 1.01x slower |
| **match field_1** | **79.51 M** | **12.58** | **1.22x slower** |
| **match field_33** | **77.90 M** | **12.84** | **1.25x slower** |
| Map.get field_1 | 27.13 M | 36.86 | 3.58x slower |

**Finding**: `match` is **2.9x faster than Map.get** for first field access in HAMT!

---

## Part 2: Match vs Envelope (Measuring Overhead)

| Method | ips | avg (ns) | Overhead |
|--------|-----|----------|----------|
| **match (direct binary)** | **68.34 M** | **14.63** | baseline |
| Envelope.get (struct dispatch) | 27.19 M | 36.77 | **2.51x slower** |

**The envelope adds 22ns overhead per access!**

---

## Part 3: Batch Access - Multiple Fields

### Reading 3 fields

| Method | ips | avg (ns) | vs fastest |
|--------|-----|----------|------------|
| Map.get 3 fields | 29.03 M | 34.44 | baseline |
| **match 3 fields** | **20.48 M** | **48.82** | 1.42x slower |
| full decode | 17.25 M | 57.96 | 1.68x slower |
| Envelope get 3 fields | 15.07 M | 66.34 | 1.93x slower |

### Reading ALL 8 fields

| Method | ips | avg (ns) | vs fastest |
|--------|-----|----------|------------|
| **full decode** | **16.68 M** | **59.96** | baseline |
| **match all 8 fields** | **15.59 M** | **64.13** | 1.07x slower |
| Map.get all 8 fields | 13.90 M | 71.95 | **1.20x slower** |

**Key Finding**: When extracting ALL fields, `match` is **1.12x faster than Map.get**!

---

## Part 4: Serialization

### Binary Sizes

| Size | GridCodec | ETF | Savings |
|------|-----------|-----|---------|
| Small (8 fields) | 64 B | 94 B | **31% smaller** |
| Medium (32 fields) | 256 B | 381 B | **32% smaller** |
| Large (33 fields) | 264 B | 393 B | **32% smaller** |

### Encode Performance

| Benchmark | ips | Speedup |
|-----------|-----|---------|
| Codec Small (8) | 41.92 M | **12.7x faster** vs ETF |
| Codec Medium (32) | 3.95 M | **3.2x faster** vs ETF |
| Codec Large (33) | 3.96 M | **4.3x faster** vs ETF |

### Decode Performance

| Benchmark | ips | Speedup |
|-----------|-----|---------|
| Codec Small (8) | 15.91 M | **4.4x faster** vs ETF |
| Codec Medium/Large | ~1 M | ~1x vs ETF (struct creation overhead) |

---

## Summary: Performance Hierarchy

| Operation | Speed | Use When |
|-----------|-------|----------|
| **match macro** | ~60-80M ips | Need 1-3 fields from binary |
| Map.get (atom keys) | ~30-100M ips | In-memory data access |
| full decode | ~15M ips | Need most/all fields |
| Envelope.get | ~27M ips | Runtime field selection (avoid if possible) |

## Recommendations

### Use `match` macro when:
- ✅ Field name is known at compile time
- ✅ Extracting 1-8 fields from binary
- ✅ Performance is critical
- ✅ Routing/filtering on specific fields

```elixir
require MyCodec

case binary do
  MyCodec.match(user_id: uid, timestamp: ts) when uid == target_uid ->
    handle_match(ts)
  _ ->
    :skip
end
```

### Use Envelope.get when:
- Field name is determined at runtime
- Building generic utilities
- Performance is not critical

### Use full decode when:
- Need most/all fields
- Will iterate over the data multiple times
- Need struct pattern matching downstream
