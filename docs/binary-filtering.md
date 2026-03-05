# Binary Filtering, Transcoding, and ETS Patterns

GridCodec binaries can be filtered, routed, and transcoded without full decode.
This guide covers three modules and one storage pattern that make this possible.

## GridCodec.Match — compile-time matchspecs

`GridCodec.Match` generates predicate functions that extract fields at
compile-time known offsets and evaluate guard expressions. No full decode is
performed — each field read is O(1).

### Basic usage

```elixir
defmodule SpanFilters do
  use GridCodec.Match

  # Simple equality check
  defmatch :sampled?, MyApp.BinaryEnvelope do
    where flags == 1
  end
end

SpanFilters.sampled?(binary)  #=> true | false
```

`use GridCodec.Match` auto-imports `Bitwise`, so `band`, `bor`, `bxor`, and
friends are available in `where` expressions.

### Bitwise guards

```elixir
defmatch :trace_sampled?, BinaryEnvelope do
  where band(flags, 0x01) == 1
end
```

This matches when the lowest bit of `flags` is set, regardless of other bits.

### Cross-field comparisons

Field names in `where` expressions resolve to their decoded values at the
field's binary offset. You can reference multiple fields and compare them:

```elixir
defmatch :slow_span?, BinaryTraceContext do
  where end_time_ns - start_time_ns > 1_000_000_000
end
```

### Multiple conditions

Multiple `where` clauses are ANDed together:

```elixir
defmatch :sampled_server_span?, BinaryTraceContext do
  where band(flags, 1) == 1
  where kind == 3
end
```

### Field selection

Add `select:` to extract field values on match instead of returning a boolean:

```elixir
defmatch :extract_context, BinaryEnvelope, select: [:trace_id, :span_id] do
  where flags == 1
end
```

Returns `{:match, %{trace_id: ..., span_id: ...}}` on match, or `:no_match`.

### Using with `Enum.filter`

Match predicates are regular functions — use them anywhere:

```elixir
sampled_spans = Enum.filter(span_binaries, &SpanFilters.sampled?/1)
```

### Payload-only binaries

By default, `defmatch` expects framed binaries (with the 8-byte header from
`encode/1`). For payload-only binaries, pass `header: false`:

```elixir
defmatch :fast_check?, MyCodec, header: false do
  where status == 1
end
```

### Guard-compatible types

All integer types (`u8`–`u64`, `i8`–`i64`), floats (`f32`, `f64`), booleans,
and timestamps produce values that work in Elixir guard expressions (`==`, `<`,
`>`, `band`, arithmetic, etc.).

Types that decode to structs or binaries (decimal, UUID, bitset) can be used in
`select:` but cannot appear in arithmetic/comparison `where` guards.

### How it works

At compile time, `defmatch` calls the codec's `__match_meta__/0` to resolve
field offsets and type modules. It then:

1. Walks the `where` AST to find field name references
2. Generates extraction code for each referenced field at its known offset
3. Rewrites the guard expression to use the extracted values
4. Emits a function clause with `when is_binary(binary)` and a fallback

The generated function performs one binary read per referenced field and
evaluates the guard — no intermediate struct, no full decode.

---

## GridCodec.Transcoder — codec-to-codec without structs

`GridCodec.Transcoder` generates a `transcode/1` function that reads fields
from a source GridCodec binary and passes them directly to a target encoder.
The source binary is never fully decoded and no intermediate struct is created.

### Defining a transcoder

```elixir
defmodule SpanToProto do
  use GridCodec.Transcoder,
    source: MyApp.BinaryTraceContext,
    target: MyApp.ProtoTarget

  field :trace_id
  field :flags
  field :start_time_ns, to: :start_time_unix_nano
  field :span_id, transform: &<<&1::64>>
end
```

### Target module

The target must implement `encode/1` that accepts a map of field values:

```elixir
defmodule MyApp.ProtoTarget do
  def encode(fields) when is_map(fields) do
    proto = struct!(MyApp.ProtoSpan, fields)
    {:ok, MyApp.ProtoSpan.encode(proto)}
  end
end
```

### Field options

| Option | Description |
|--------|-------------|
| `to:` | Rename the field in the output map |
| `transform:` | Apply a function to the extracted value before passing to the target |

### How it works

At compile time, `use GridCodec.Transcoder` resolves field offsets from the
source codec via `__match_meta__/0`. In `__before_compile__`, it generates a
`transcode/1` function that:

1. Extracts each mapped field at its known offset (O(1) per field)
2. Applies any `transform:` functions
3. Builds the output map with the (possibly renamed) keys
4. Calls `target_module.encode(map)`

The cost is proportional to the number of mapped fields, not the total number
of fields in the source codec.

---

## Binary-first ETS patterns

BEAM ETS tables copy Erlang terms into and out of the table on every
operation. For structs, this means the full map structure is deep-copied on
every `ets:lookup` or `ets:foldl` iteration.

Binaries larger than 64 bytes are reference-counted (refc) — ETS stores a
pointer, and reads return a shared reference. GridCodec binaries are typically
65–200 bytes, so they naturally hit this fast path.

### Pattern: binary-native message store

```elixir
# Create the table
table = :ets.new(:spans, [:set, :public, {:write_concurrency, true}])

# Insert encoded binaries (pointer store, not deep copy)
{:ok, bin} = MySpan.encode(span)
:ets.insert(table, {span_id, bin})

# Read: shared reference, not a copy
[{_, bin}] = :ets.lookup(table, span_id)

# Filter without decode
:ets.foldl(
  fn {_key, bin}, acc ->
    if MySpan.get(bin, :flags) == 1, do: [bin | acc], else: acc
  end,
  [],
  table
)
```

### Pattern: OTel-style double-buffer batch export

The OpenTelemetry batch span processor uses two ETS tables. One accepts new
spans while the other is being exported. GridCodec binaries make the export
read cheaper because `tab2list` returns refc-shared references:

```elixir
# Drain the old table (refc shared — no deep copies)
entries = :ets.tab2list(old_table)

# Filter with Match predicates
sampled = Enum.filter(entries, fn {_k, bin} -> SpanFilters.sampled?(bin) end)

# Transcode to protobuf for gRPC export
protos = Enum.map(sampled, fn {_k, bin} -> SpanToProto.transcode(bin) end)
```

### Benchmark results (Apple M3 Max, 10K spans, OTP 28)

| Operation | Struct ETS | Binary ETS | Advantage |
|-----------|-----------|------------|-----------|
| Full scan + filter | 1.64 ms / 3.27 MB | **0.76 ms / 1.64 MB** | 2.2x faster, 2x less memory |
| Cross-field filter | 2.35 ms / 3.31 MB | **1.62 ms / 1.98 MB** | 1.5x faster, 1.7x less memory |
| tab2list (batch drain) | 1.43 ms / 1.90 MB | **1.20 ms / 0.64 MB** | 1.2x faster, 3x less memory |

The memory advantage compounds: at 100K spans the struct path allocates ~33 MB
of copies during a full scan while the binary path allocates ~16 MB of shared
references.

Run the benchmark yourself:

```bash
cd example_app && MIX_ENV=prod mix run benchmarks/ets_binary_bench.exs
```

---

## End-to-end example: telemetry span pipeline

Combining all three modules into a span processing pipeline:

```elixir
# 1. Define the codec
defmodule MyApp.Span do
  use GridCodec.Struct, template_id: 100, schema_id: 10

  defcodec do
    field :trace_id, :uuid
    field :span_id, :u64
    field :parent_span_id, :u64
    field :flags, :u32
    field :kind, :u8
    field :start_time_ns, :timestamp_ns
    field :end_time_ns, :timestamp_ns
    field :name, :string16
  end
end

# 2. Define filters
defmodule MyApp.SpanFilters do
  use GridCodec.Match

  defmatch :sampled?, MyApp.Span do
    where band(flags, 0x01) == 1
  end

  defmatch :slow?, MyApp.Span do
    where end_time_ns - start_time_ns > 5_000_000
  end

  defmatch :sampled_slow?, MyApp.Span, select: [:trace_id, :name] do
    where band(flags, 1) == 1
    where end_time_ns - start_time_ns > 5_000_000
  end
end

# 3. Define transcoder to export format
defmodule MyApp.SpanExporter do
  use GridCodec.Transcoder,
    source: MyApp.Span,
    target: MyApp.OTLPTarget

  field :trace_id
  field :span_id, transform: &<<&1::64>>
  field :flags
  field :kind
  field :start_time_ns, to: :start_time_unix_nano
  field :end_time_ns, to: :end_time_unix_nano
  field :name
end

# 4. Pipeline: store → filter → transcode → export
defmodule MyApp.SpanProcessor do
  def on_end(span_fields) do
    {:ok, bin} = MyApp.Span.encode(span_fields)
    :ets.insert(:span_buffer, {:erlang.unique_integer(), bin})
  end

  def export do
    entries = :ets.tab2list(:span_buffer)
    :ets.delete_all_objects(:span_buffer)

    entries
    |> Enum.filter(fn {_k, bin} -> MyApp.SpanFilters.sampled?(bin) end)
    |> Enum.map(fn {_k, bin} -> MyApp.SpanExporter.transcode(bin) end)
  end
end
```

In this pipeline, spans are encoded once on creation and stay as binaries
through ETS storage, filtering, and transcoding. The only full decode happens
inside the target module's `encode/1` for the final wire format conversion.

## See also

- [Getting started](getting-started.md) — define a codec, encode/decode
- [Performance](performance.md) — profiling and baseline numbers
