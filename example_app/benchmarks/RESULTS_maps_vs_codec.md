# Maps vs GridCodec Binary Access Benchmark

Based on [Elixir Forum discussion](https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909)

## Access Methods

| Method | Description | Null Handling |
|--------|-------------|---------------|
| `Map.get` | Standard Elixir map access | N/A |
| `match` | Inline binary pattern via macro | ❌ Raw value |
| `get` | Inline binary pattern via macro | ✅ Returns `nil` |

---

## Binary Sizes

All binaries include 8-byte header (schema_id, template_id, version) for dispatch support.

| Struct | Fields | Payload | Total |
|--------|--------|---------|-------|
| Small | 8 | 64 bytes | 72 bytes |
| Medium | 32 | 256 bytes | 264 bytes |
| Large | 33 | 264 bytes | 272 bytes |

---

## Performance Summary

At nanosecond scales, variance is high (~8000%+ deviation). Results are representative but ordering may vary between runs.

### SMALL (8 fields, 72 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| Map.get | 33-101M | Best for small flat maps |
| match | 62-69M | Consistent across positions |
| get | 26-27M | Consistent across positions |

### MEDIUM (32 fields, 264 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| match | 25-64M | Position-dependent |
| get | 49-62M | Competitive with match |
| Map.get | 31-58M | Slower at end position |

### LARGE (33 fields - HAMT, 272 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| match | 26-69M | Consistent O(1) |
| get | 24-62M | Consistent O(1) |
| Map.get | 32-33M | HAMT overhead |

---

## Key Findings

1. **`match` and `get` are in the same performance class** (~30-70M ips)
   - Both use inline binary pattern matching at compile time
   - `get` includes null value checking, `match` returns raw bytes

2. **Binary access is O(1)** regardless of field position or total fields
   - Consistent performance for start/mid/end positions
   - No HAMT tree traversal like maps

3. **For large structs (33+ keys), binary access beats HAMT maps**
   - Maps transition from flat to HAMT above 32 keys
   - Binary access performance is unaffected by field count

4. **Envelope.get uses runtime dispatch** via GridCodec.get/2
   - Slower than `get` macro but works dynamically
   - For hot paths, use `get` macro with `require`

---

## Usage Recommendations

| Use Case | Method |
|----------|--------|
| Raw binary extraction (performance critical, no nulls) | `match` macro |
| Normal field access (handles nulls) | `get` macro |
| Envelope field access (runtime dispatch) | `Envelope.get` function |
| Data in maps already | `Map.get` |

## Example Usage

```elixir
require MyCodec

# match macro - raw bytes, no null check
case binary do
  MyCodec.match(price: p, qty: q) -> {p, q}
end

# get macro - with null handling
price = MyCodec.get(binary, :price)

# Envelope.get (for envelope access, uses runtime dispatch)
env = MyCodec.wrap(binary)
price = GridCodec.Envelope.get(env, :price)
```

---

## Raw Results (v0.5.0)

### Small (8 fields)
```
Name                      ips        average  deviation         median
Map.get (start)      101.12 M        9.89 ns  ±1640.18%        8.40 ns
match (start)         68.73 M       14.55 ns  ±8070.90%        8.30 ns
match (mid)           65.88 M       15.18 ns  ±8060.70%        8.30 ns
match (end)           61.56 M       16.25 ns  ±8325.27%        8.30 ns
Map.get (mid)         33.25 M       30.08 ns   ±174.15%       41.00 ns
Map.get (end)         33.03 M       30.27 ns   ±186.26%       41.00 ns
get (start)           26.86 M       37.23 ns ±11659.85%       42.00 ns
get (mid)             26.54 M       37.68 ns ±11655.93%       42.00 ns
get (end)             26.28 M       38.05 ns ±12492.09%       42.00 ns
```

### Medium (32 fields)
```
Name                      ips        average  deviation         median
match (end)           64.11 M       15.60 ns  ±8071.79%        8.30 ns
get (mid)             62.28 M       16.06 ns  ±6989.08%        8.40 ns
get (end)             60.91 M       16.42 ns  ±7050.58%        8.40 ns
Map.get (start)       58.29 M       17.16 ns   ±101.74%       16.70 ns
get (start)           48.93 M       20.44 ns  ±8007.11%        8.40 ns
Map.get (mid)         31.15 M       32.10 ns   ±174.91%       42.00 ns
Map.get (end)         30.80 M       32.47 ns   ±170.39%       42.00 ns
match (mid)           26.49 M       37.75 ns ±12717.17%       42.00 ns
match (start)         24.66 M       40.55 ns ±11563.42%       42.00 ns
```

### Large (33 fields - HAMT)
```
Name                      ips        average  deviation         median
match (end)           69.39 M       14.41 ns  ±8630.23%        8.30 ns
match (mid)           66.98 M       14.93 ns  ±8369.22%        8.30 ns
get (start)           61.80 M       16.18 ns  ±7295.84%        8.40 ns
Map.get (mid)         32.63 M       30.64 ns   ±179.52%       41.00 ns
Map.get (start)       31.73 M       31.52 ns   ±195.39%       41.00 ns
Map.get (end)         31.51 M       31.73 ns   ±193.16%       41.00 ns
get (mid)             26.81 M       37.30 ns ±11834.78%       42.00 ns
match (start)         26.30 M       38.03 ns ±12403.79%       42.00 ns
get (end)             24.02 M       41.63 ns ±11836.03%       42.00 ns
```
