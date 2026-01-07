# Maps vs GridCodec Binary Access Benchmark

Based on [Elixir Forum discussion](https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909)

## Access Methods Compared

| Method | Description |
|--------|-------------|
| `Map.get` | Standard Elixir map access |
| `match` | Inline binary pattern match via macro |
| `Codec.get` | `MyCodec.get(binary, :field)` - direct module dispatch |
| `GridCodec.get` | `GridCodec.get(binary, spec)` - generic dispatch |

---

## SMALL (8 fields) - Flat map

Binary size: 64 bytes

| Benchmark | ips | avg (ns) |
|-----------|-----|----------|
| match (end) | 128M | 7.8 |
| Map.get (start) | 120M | 8.3 |
| Map.get (mid) | 76M | 13.2 |
| Map.get (end) | 32M | 31.1 |
| match (start/mid) | 28M | 35 |
| Codec.get | 21-29M | 35-47 |
| GridCodec.get | 26M | 39 |

---

## MEDIUM (32 fields) - Flat map limit

Binary size: 256 bytes

| Benchmark | ips | avg (ns) |
|-----------|-----|----------|
| match (start) | 115M | 8.7 |
| match (mid) | 61M | 16.5 |
| match (end) | 45M | 22.1 |
| Map.get (mid/end) | 30M | 33 |
| Codec.get | 23-29M | 35-44 |
| GridCodec.get | 21-24M | 41-48 |
| Map.get (start) | 22M | 45 |

---

## LARGE (33 fields) - HAMT map

Binary size: 264 bytes

| Benchmark | ips | avg (ns) |
|-----------|-----|----------|
| Map.get (end) | 113M | 8.9 |
| Codec.get (start) | 99M | 10.1 |
| match | 28-29M | 35 |
| Map.get (mid/start) | 27M | 36-37 |
| Codec.get (mid/end) | 27-29M | 34-36 |
| GridCodec.get | 23-25M | 39-43 |

---

## Key Findings

1. **match macro** - Fastest for small binaries (115-128M ips) due to inline pattern match
2. **Map.get** - Varies significantly by key position (8-120M ips)
3. **Codec.get** - Consistent performance, comparable to match (~28M ips)
4. **GridCodec.get** - ~15% slower than Codec.get due to type dispatch (~23-26M ips)

## Recommendations

| Use Case | Best Method |
|----------|-------------|
| Known field at compile time | `match` macro |
| Direct module access | `Codec.get(binary, :field)` |
| Generic/runtime field access | `GridCodec.get(binary, spec)` |
| In-memory data | `Map.get` |

## Usage

```elixir
# Match macro (fastest for known fields)
require MyCodec
case binary do
  MyCodec.match(price: p, qty: q) -> {p, q}
end

# Direct module access
value = MyCodec.get(binary, :price)

# Generic access with field spec
value = GridCodec.get(binary, MyCodec.field(:price))
```
