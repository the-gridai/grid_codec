# Maps vs GridCodec Binary Access Benchmark Results

**Date**: January 7, 2026  
**System**: Darwin (macOS)

Based on the classic [Elixir Forum discussion](https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909/6).

---

## Key Finding: GridCodec is Competitive with Maps!

GridCodec now supports direct binary access via `get(binary, field)`:

```elixir
# Direct binary field access - no envelope needed!
value = MyCodec.get(binary, :field_name)

# Or use match macro for multiple fields (single pattern match)
case binary do
  MyCodec.match(field_1: v1, field_4: v4) -> {v1, v4}
end
```

---

## Part 1: Single Field Access - get(binary, field) vs Map.get

### Small (8 fields)

| Benchmark | ips | avg (ns) | vs fastest |
|-----------|-----|----------|------------|
| Map.get field_8 | 101.34 M | 9.87 | baseline |
| Map.get field_1 | 31.28 M | 31.97 | 3.24x slower |
| **get(bin, :field_8)** | **29.03 M** | **34.45** | 3.49x slower |
| **get(bin, :field_1)** | **29.02 M** | **34.46** | 3.49x slower |

GridCodec shows **consistent O(1) performance** (~29M ips) regardless of field position!

### Medium (32 fields - flat map limit) ⭐

| Benchmark | ips | avg (ns) | vs fastest |
|-----------|-----|----------|------------|
| **get(bin, :field_1)** | **57.78 M** | **17.31** | **baseline** |
| **get(bin, :field_16)** | **46.19 M** | **21.65** | 1.25x slower |
| Map.get field_32 | 29.39 M | 34.03 | **1.97x slower** |
| Map.get field_16 | 28.54 M | 35.04 | **2.02x slower** |
| Map.get field_1 | 27.58 M | 36.26 | **2.10x slower** |

**GridCodec is 2x FASTER than Map.get for 32-field structs!**

### Large (33 fields - HAMT)

| Benchmark | ips | avg (ns) | vs fastest |
|-----------|-----|----------|------------|
| Map.get field_16 | 99.01 M | 10.10 | baseline (HAMT optimized) |
| Map.get field_1 | 27.57 M | 36.28 | 3.59x slower |
| Map.get field_33 | 27.40 M | 36.50 | 3.61x slower |
| get(bin, :field_1) | 26.41 M | 37.86 | 3.75x slower |
| get(bin, :field_16) | 26.09 M | 38.33 | 3.79x slower |

GridCodec is competitive with Map.get for HAMT maps.

---

## Part 2: Comparing All Access Methods

| Method | ips | avg (ns) | Notes |
|--------|-----|----------|-------|
| Map.get | 93.09 M | 10.74 | Best for in-memory with atom keys |
| **get(binary, field)** | **30.17 M** | **33.14** | **Direct binary access** |
| get(envelope, field) | 26.67 M | 37.50 | Envelope overhead |
| match macro | 16.41 M | 60.93 | Case statement overhead for single field |

**New `get(binary, field)` is 1.13x faster than envelope-based access!**

---

## Part 3: Batch Access - Multiple Fields

### Reading 3 fields

| Method | ips | avg (ns) | vs fastest |
|--------|-----|----------|------------|
| Map.get x3 | 27.62 M | 36.21 | baseline |
| **match 3 fields** | **20.57 M** | **48.61** | 1.34x slower |
| full decode | 15.84 M | 63.15 | 1.74x slower |
| get(bin, field) x3 | 14.38 M | 69.55 | 1.92x slower |

### Reading ALL 8 fields ⭐

| Method | ips | avg (ns) | vs fastest |
|--------|-----|----------|------------|
| **match all 8 fields** | **14.38 M** | **69.54** | **baseline** |
| **full decode** | **14.32 M** | **69.86** | 1.00x (same) |
| Map.get x8 | 12.49 M | 80.04 | **1.15x slower** |
| get(bin, field) x8 | 7.79 M | 128.36 | 1.85x slower |

**Key Finding**: For extracting all fields:
- **`match` is 1.15x faster than Map.get!**
- `full decode` equals `match` performance
- Multiple `get()` calls add function call overhead

---

## Part 4: Serialization

### Binary Sizes

| Size | GridCodec | ETF | Savings |
|------|-----------|-----|---------|
| Small (8 fields) | 64 B | 94 B | **31% smaller** |
| Medium (32 fields) | 256 B | 381 B | **32% smaller** |
| Large (33 fields) | 264 B | 393 B | **32% smaller** |

### Encode Performance

| Benchmark | ips | vs ETF |
|-----------|-----|--------|
| Codec Small (8) | 40.74 M | **12.3x faster** |
| Codec Medium (32) | 4.43 M | **3.6x faster** |
| Codec Large (33) | 4.29 M | **4.9x faster** |

### Decode Performance

| Benchmark | ips | vs ETF |
|-----------|-----|--------|
| Codec Small (8) | 16.58 M | **4.6x faster** |
| Codec Medium/Large | ~1 M | ~1x (struct overhead) |

---

## Summary: When to Use What

| Scenario | Best Method | Performance |
|----------|-------------|-------------|
| Single field from 8-field map | Map.get | 101M ips |
| Single field from 32-field map | **get(bin, field)** | **58M ips (2x faster!)** |
| Single field from HAMT (>32) | Map.get (hit) | 99M ips |
| Extract 3+ fields from binary | **match macro** | Single pattern match |
| Extract all fields | **full decode** or **match** | 14M ips |
| Runtime field name | get(bin, field) | 30M ips |
| Serialization | **GridCodec** | 4-12x faster encode |

## API Summary

```elixir
# Direct binary access (NEW!)
value = MyCodec.get(binary, :field_name)

# Match macro for multiple fields (compile-time)
case binary do
  MyCodec.match(user_id: uid, price: p) -> handle(uid, p)
end

# Full decode when you need everything
{:ok, struct} = MyCodec.decode(binary)

# Envelope for compatibility (slightly slower)
env = MyCodec.wrap(binary)
value = MyCodec.get(env, :field_name)
```
