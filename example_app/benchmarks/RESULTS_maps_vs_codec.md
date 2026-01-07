# Maps vs GridCodec Binary Access Benchmark

Based on [Elixir Forum discussion](https://elixirforum.com/t/big-maps-versus-small-maps-performance/31909)

## Access Methods

| Method | Description | Null Handling |
|--------|-------------|---------------|
| `Map.get` | Standard Elixir map access | N/A |
| `match` | Inline binary pattern via macro | ❌ Raw value |
| `get!` | Inline binary pattern via macro | ✅ Returns `nil` |

---

## Performance Summary

At nanosecond scales, variance is high (~8000%+ deviation). Results are representative but ordering may vary between runs.

### SMALL (8 fields, 64 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| Map.get | 70-130M | Best for small flat maps |
| match | 24-76M | Position-dependent |
| get! | 27-69M | Competitive with match |

### MEDIUM (32 fields, 256 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| match | 71-77M | Consistent across positions |
| get! | 27-70M | Competitive with match |
| Map.get | 30-64M | Slower at end position |

### LARGE (33 fields - HAMT, 264 bytes)

| Method | IPS Range | Notes |
|--------|-----------|-------|
| Map.get | 32-143M | HAMT lookup overhead varies |
| match | 65-68M | Consistent O(1) |
| get! | 26-71M | Consistent O(1) |

---

## Key Findings

1. **`match` and `get!` are in the same performance class** (~60-80M ips)
   - Both use inline binary pattern matching at compile time
   - `get!` includes null value checking, `match` returns raw bytes

2. **Binary access is O(1)** regardless of field position or total fields
   - Consistent performance for start/mid/end positions
   - No HAMT tree traversal like maps

3. **For large structs, GridCodec beats Map.get** for some field positions
   - Maps degrade to HAMT (O(log n)) above 32 keys
   - Binary access stays constant

4. **Function dispatch is 2-3x slower** than inline macros
   - `Codec.get(binary, :field)` is ~25M ips
   - `get!(binary, :field)` is ~60M ips

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
