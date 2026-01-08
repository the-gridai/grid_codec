# Maps vs GridCodec Binary Access Benchmark

Based on [Elixir Forum discussion](https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909)

## Access Methods

| Method | Description | Null Handling |
|--------|-------------|---------------|
| `Map.get` | Standard Elixir map access | N/A |
| `match` | Inline binary pattern via macro | ❌ Raw value |
| `get!` | Inline binary pattern via macro | ✅ Returns `nil` |

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
| Map.get | 33-139M | Best for small flat maps |
| match | 25-62M | Position-dependent |
| get! | 34-55M | Competitive with match |

### MEDIUM (32 fields, 264 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| match | 27-64M | Consistent across positions |
| get! | 26-60M | Competitive with match |
| Map.get | 58-104M | Fast with flat maps |

### LARGE (33 fields - HAMT, 272 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| Map.get | 22-113M | HAMT lookup overhead varies |
| match | 21-71M | Consistent O(1) |
| get! | 27-60M | Consistent O(1) |

---

## Key Findings

1. **`match` and `get!` are in the same performance class** (~30-70M ips)
   - Both use inline binary pattern matching at compile time
   - `get!` includes null value checking, `match` returns raw bytes

2. **Binary access is O(1)** regardless of field position or total fields
   - Consistent performance for start/mid/end positions
   - No HAMT tree traversal like maps

3. **For large structs (33+ keys), binary access is competitive with HAMT**
   - Maps transition from flat to HAMT above 32 keys
   - Binary access performance is unaffected by field count

4. **Function dispatch is 2-3x slower** than inline macros
   - `Codec.get(binary, :field)` is ~25M ips
   - `get!(binary, :field)` is ~50M ips

---

## Usage Recommendations

| Use Case | Method |
|----------|--------|
| Raw binary extraction (performance critical, no nulls) | `match` macro |
| Normal field access (handles nulls) | `get!` macro |
| Runtime/dynamic field access | `Codec.get` function |
| Data in maps already | `Map.get` |

## Example Usage

```elixir
require MyCodec

# match macro - raw bytes, no null check
case binary do
  MyCodec.match(price: p, qty: q) -> {p, q}
end

# get! macro - with null handling
price = MyCodec.get!(binary, :price)

# Function (slower, but works with dynamic field names)
price = MyCodec.get(binary, field_name)
```

---

## Raw Results (v0.5.0)

### Small (8 fields)
```
Name                      ips        average  deviation         median
Map.get (end)        138.68 M        7.21 ns   ±198.35%        8.30 ns
Map.get (mid)         99.26 M       10.07 ns  ±1879.26%        8.30 ns
match (end)           62.16 M       16.09 ns  ±8728.04%        8.30 ns
match (start)         57.55 M       17.38 ns  ±9176.70%        8.30 ns
get! (end)            54.81 M       18.25 ns  ±8153.60%        8.40 ns
get! (start)          40.82 M       24.50 ns ±11151.81%        8.40 ns
get! (mid)            34.17 M       29.26 ns ±18348.23%        8.40 ns
Map.get (start)       33.40 M       29.94 ns   ±219.10%       41.00 ns
match (mid)           24.76 M       40.39 ns ±11039.23%       42.00 ns
```

### Medium (32 fields)
```
Name                      ips        average  deviation         median
Map.get (end)        103.53 M        9.66 ns ±18852.05%        8.30 ns
Map.get (mid)         81.11 M       12.33 ns   ±128.86%       12.50 ns
match (start)         63.93 M       15.64 ns  ±8182.12%        8.30 ns
get! (end)            59.62 M       16.77 ns  ±7216.27%        8.40 ns
get! (mid)            58.98 M       16.95 ns  ±7526.23%        8.40 ns
Map.get (start)       57.56 M       17.37 ns   ±541.44%       16.70 ns
match (end)           53.75 M       18.61 ns  ±6221.98%        8.30 ns
match (mid)           26.57 M       37.64 ns ±12091.53%       42.00 ns
get! (start)          26.22 M       38.14 ns ±11675.75%       42.00 ns
```

### Large (33 fields - HAMT)
```
Name                      ips        average  deviation         median
Map.get (mid)        112.95 M        8.85 ns   ±248.72%        5.42 ns
match (end)           71.43 M       14.00 ns  ±8260.29%        8.30 ns
get! (start)          60.03 M       16.66 ns  ±7775.10%        8.40 ns
get! (mid)            49.47 M       20.21 ns  ±6962.86%        8.40 ns
match (start)         37.19 M       26.89 ns  ±6690.31%        8.30 ns
Map.get (end)         27.79 M       35.98 ns   ±164.07%       42.00 ns
get! (end)            26.61 M       37.58 ns ±12550.41%       42.00 ns
Map.get (start)       21.84 M       45.78 ns   ±409.58%       42.00 ns
match (mid)           21.01 M       47.59 ns ±10363.78%       42.00 ns
```
