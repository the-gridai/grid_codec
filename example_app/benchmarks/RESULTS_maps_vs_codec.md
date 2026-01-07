# Maps vs GridCodec Binary Access Benchmark

Based on [Elixir Forum discussion](https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909)

## Summary

| Size | Map.get | match macro | GridCodec.get |
|------|---------|-------------|---------------|
| Small (8) | 26-28M ips | 24-40M ips | 19-21M ips |
| Medium (32) | 21-26M ips | 12-21M ips | 19-23M ips |
| Large (33 HAMT) | 22M ips | 19M ips | 15-16M ips |

**Key findings:**
- `match` macro is fastest for small binaries (inline pattern match)
- GridCodec shows consistent O(1) performance regardless of field position
- Map.get varies with key position in large maps
- For batch access (3 fields), `match` is 1.46x faster than Map.get x3

---

## SMALL (8 fields) - Flat map

Binary size: 64 bytes

| Benchmark | ips | avg (ns) |
|-----------|-----|----------|
| match (start) | 39.63 M | 25.24 |
| Map.get (end) | 27.87 M | 35.88 |
| Map.get (mid) | 27.42 M | 36.47 |
| Map.get (start) | 25.76 M | 38.81 |
| match (mid) | 24.93 M | 40.11 |
| match (end) | 23.82 M | 41.97 |
| GridCodec.get | 19-21 M | 47-51 |

---

## MEDIUM (32 fields) - Flat map limit

Binary size: 256 bytes

| Benchmark | ips | avg (ns) |
|-----------|-----|----------|
| Map.get (end) | 25.57 M | 39.10 |
| GridCodec.get (start) | 23.39 M | 42.76 |
| Map.get (mid) | 22.17 M | 45.11 |
| match (end) | 21.23 M | 47.10 |
| Map.get (start) | 20.84 M | 47.98 |
| GridCodec.get (mid/end) | 19-20 M | 51 |
| match (start/mid) | 12-18 M | 57-81 |

---

## LARGE (33 fields) - HAMT map

Binary size: 264 bytes

| Benchmark | ips | avg (ns) |
|-----------|-----|----------|
| Map.get | 22 M | 44-46 |
| match | 19 M | 51-53 |
| GridCodec.get | 15-16 M | 61-65 |

---

## BATCH ACCESS - 3 fields from 32-field structure

| Method | ips | vs fastest |
|--------|-----|------------|
| match (3 fields) | 17.00 M | baseline |
| Map.get x3 | 11.64 M | 1.46x slower |
| GridCodec.get x3 | 7.52 M | 2.26x slower |
| full decode | 0.81 M | 21x slower |

---

## Recommendations

| Use Case | Best Method |
|----------|-------------|
| Known field(s) at compile time | `match` macro |
| In-memory data access | `Map.get` |
| Runtime field selection | `GridCodec.get(bin, Codec.field(:name))` |
| Need most/all fields | Full decode |

## Usage

```elixir
# Match macro (fastest for known fields)
require MyCodec
case binary do
  MyCodec.match(price: p, quantity: q) -> {p, q}
end

# GridCodec.get with field spec
value = GridCodec.get(binary, MyCodec.field(:price))
```
