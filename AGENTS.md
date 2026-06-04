# Agent Instructions for GridCodec

This document provides instructions for AI agents working with the GridCodec library.

## Project Overview

GridCodec is a high-performance binary codec for BEAM/Elixir with direct field access. The library uses compile-time code generation to create optimized encode/decode functions for structs.

### Key Directories

- `lib/` - Main library code
- `example_app/` - Example application with benchmarks and profiling
- `profile/` - Production profiling tools (Docker-based)
- `test/` - Test suite
- `docs/` - Design documentation

## Performance Profiling

### When to Profile

Profile code when:
- Investigating performance bottlenecks
- Evaluating optimization attempts
- Comparing before/after changes
- Understanding where time is spent in encode/decode

### Running the Profiler

```bash
# Full profile (encode + decode)
./profile/run.sh

# Encode only
./profile/run.sh --mode=encode

# Decode only
./profile/run.sh --mode=decode

# Custom iterations
./profile/run.sh --iterations=1000000 --warmup=50000
```

### How the Profiler Works

The profiler uses a **two-phase approach** for accurate, noise-free profiling:

1. **Phase 1: JIT Warmup (no perf)**
   - Runs warmup iterations WITHOUT profiling
   - Allows BEAM JIT to compile and optimize hot paths
   - Eliminates warmup noise from profile data

2. **Phase 2: Profile Only (with perf)**
   - Starts `perf record` ONLY for actual encode/decode operations
   - Uses `+JPperf true` OTP flag for JIT symbol resolution
   - Captures clean, warmup-free performance data

#### JIT Symbol Resolution (`+JPperf true` + `perf inject --jit`)

OTP 24+ includes the `+JPperf true` flag which generates perf map files. Combined with `perf inject --jit`, this resolves JIT-compiled addresses to readable function names:

```
# Without JIT resolution: Unreadable hex addresses
0xffff68216838 → ???

# With JIT resolution: Full Elixir function names
jitted-182-44445.so → 'Elixir.ExampleApp.Events.OrderCreated':decode/1
jitted-182-44501.so → 'Elixir.GridCodec.Types.TimestampMicros':encode_value/1
```

This enables you to see **exactly which Elixir functions** are consuming CPU time.

#### What's NOT Resolved (and why)

Some `beam.smp` addresses may still appear as hex (e.g., `0x000000000027d7b8`). These are:
- Internal BEAM runtime functions
- Symbols stripped in release builds
- Would require debug Erlang builds to resolve

**These are rarely actionable** - focus on the named functions which represent your actual code.

### Understanding Profile Output

The profiler generates two outputs in `profile/output/`:

1. **`report.txt`** - Text report with top CPU-consuming functions
2. **`flamegraph.svg`** - Interactive visualization

#### Reading the Text Report

With JIT symbol resolution, you'll see both BEAM runtime functions AND your Elixir code:

```
# Overhead  Command   Shared Object     Symbol
  3.67%     erts_..   libc.so.6         __memcpy_generic
  2.89%     erts_..   beam.smp          beam_jit_get_map_elements
  2.28%     erts_..   [JIT] tid 182     $'Elixir.ExampleApp.Events.OrderCreated':decode/1
  1.64%     erts_..   [JIT] tid 182     $'Elixir.ExampleApp.Events.OrderCreated':encode/1
```

**Symbol Types:**
- `[JIT] tid N` - JIT-compiled Elixir/Erlang code (your code!)
- `beam.smp` - BEAM runtime internals
- `libc.so.6` - System library calls

**Key BEAM Runtime Functions:**

| Function | What It Does | Optimization Target |
|----------|--------------|---------------------|
| `beam_jit_get_map_elements` | Reading struct fields | Reduce field access count |
| `__memcpy_generic` | Copying bytes | Avoid intermediate binaries |
| `erts_new_bs_put_binary_all` | Writing binary segments | Batch writes |
| `erts_bs_append_checked` | Appending to binary | Pre-allocate size |
| `iolist_to_binary_1` | IOList → binary conversion | Return iolist directly |
| `erts_gc_update_map_exact` | Map/struct updates | Fewer struct updates |
| `erts_bs_start_match_3` | Pattern match on binary | Reduce pattern matches |
| `erts_extract_sub_binary` | Extract sub-binary | Avoid sub-binary creation |

#### Reading the Flame Graph

Open `profile/output/flamegraph.svg` in a browser:

- **Width** represents time spent (wider = more CPU time)
- **Height** represents call stack depth
- **Colors** are random (not meaningful)
- Click on a bar to zoom into that subtree
- Look for wide bars at the bottom - those are hot paths
- **Search**: Use Ctrl+F to find specific functions like "encode" or "decode"

**What to Look For:**
- Wide `$'Elixir.YourModule':function/N` bars = hot Elixir functions
- Deep call stacks under encode/decode = potential inlining opportunities
- Multiple calls to `erts_bs_append_checked` = binary fragmentation

### Interactive Profiling

For custom profiling scenarios:

```bash
# Enter container shell
./profile/run.sh shell

# Inside container:
cd example_app
MIX_ENV=prod mix compile

# Run custom profile WITH JIT symbols
ERL_FLAGS="+JPperf true" perf record -g -F 9999 -- mix run -e '
  # Your test code here
  order = %ExampleApp.Events.OrderCreated{...}
  Enum.each(1..1_000_000, fn _ ->
    ExampleApp.Events.OrderCreated.encode(order)
  end)
'

# View results
perf report --stdio --no-children --percent-limit 0.5

# Generate flame graph
perf script | stackcollapse-perf.pl | flamegraph.pl > /workspace/custom_flamegraph.svg
```

**Important:** Always use `ERL_FLAGS="+JPperf true"` for readable function names in custom profiles.

### Output Files for Analysis

The profiler generates multiple output files in `profile/output/`:

| File | Description | Best For |
|------|-------------|----------|
| `report.txt` | Summary with call graphs | Quick overview |
| `report_flat.txt` | Flat list, no call graphs | AI parsing, scripting |
| `report_full.txt` | Complete data, no filtering | Deep analysis |
| `report_callers.txt` | Caller/callee relationships | Understanding call chains |
| `perf.data` | Raw perf data | Custom perf commands |
| `flamegraph.svg` | Interactive visualization | Visual exploration |
| `stacks.folded` | Collapsed stack traces | Programmatic analysis |
| `jit.map` | JIT symbol map | Debugging symbol issues |

### AI Agent Analysis Guide

AI agents can use the profiling data to make optimization recommendations. Here's how:

#### 1. Reading `report_flat.txt` (Recommended for AI)

This file provides a clean, parseable format:

```
# Overhead  Samples  Command      Shared Object          Symbol
  2.20%       32     erts_sched_1 libc.so.6              __memcpy_generic
  2.06%       30     erts_sched_1 [JIT] tid 182          $'Elixir.ExampleApp.Events.OrderCreated':decode/1
  1.99%       29     erts_sched_1 beam.smp               beam_jit_get_map_elements
```

**Key columns:**
- `Overhead` - Percentage of total CPU time
- `Shared Object` - Where the code lives (`[JIT]` = your Elixir code)
- `Symbol` - Function name

#### 2. Identifying Optimization Targets

**Look for these patterns:**

| Pattern | What It Means | Optimization |
|---------|---------------|--------------|
| High `beam_jit_get_map_elements` | Many struct field accesses | Reduce field access, cache values in variables |
| High `__memcpy_generic` | Lots of binary copying | Use single binary construction, avoid concatenation |
| High `erts_bs_append_checked` | Binary growing dynamically | Pre-allocate binary size |
| High `iolist_to_binary_1` | Converting iolists to binary | Return iolist directly if possible |
| High `erts_extract_sub_binary` | Creating sub-binaries | Avoid unnecessary slicing |
| Your encode/decode function high | Function itself is hot | Look at what BEAM functions it calls |

#### 3. Reading Call Chains (`report_callers.txt`)

This shows what calls what:

```
$'Elixir.GridCodec.Types.String':encode16/1
  <- erts_new_bs_put_binary_all (1.14%)
  <- beam_jit_bs_init_bits (0.68%)
```

This tells you that `String.encode16/1` spends time in binary initialization and writing.

#### 4. Using `stacks.folded` for Custom Analysis

The folded stacks format is ideal for programmatic analysis:

```
beam.smp;$global::process_main;$'Elixir.ExampleApp.Events.OrderCreated':encode/1;erts_bs_append_checked 500
```

Each line is: `stack;trace;separated;by;semicolons count`

#### 5. Running Custom Analysis in Container

```bash
./profile/run.sh shell

# Inside container, the perf.data is available:
cd /workspace/profile/output

# Filter to only Elixir functions
perf report -i perf.data --stdio -g none | grep "Elixir\."

# Show only encode functions
perf report -i perf.data --stdio -g none | grep -i "encode"

# Get detailed call graph for a specific function
perf report -i perf.data --stdio --call-graph=caller | grep -A20 "OrderCreated.*encode"
```

#### 6. Example AI Analysis Workflow

1. **Read `report_flat.txt`** to identify top CPU consumers
2. **Categorize** functions as: runtime (`beam_jit_*`, `erts_*`), system (`__memcpy*`), or application (`$'Elixir.*`)
3. **Look for patterns** in runtime function names (see table above)
4. **Examine call chains** in `report_callers.txt` to see which application code triggers expensive operations
5. **Propose optimizations** based on patterns found
6. **Re-profile after changes** to verify improvement

#### 7. Example: DateTime Optimization Discovery

From actual profiling, an AI agent might notice:

```
0.62%  $'Elixir.DateTime':to_unix/2
0.48%  $'Elixir.Calendar.ISO':'ensure_day_in_month!'/3
0.48%  $'Elixir.Calendar.ISO':days_in_previous_years/1
≈2.6%  Total DateTime/Calendar overhead
```

**Analysis:** The `:timestamp_us` field triggers `DateTime.to_unix/2` which performs expensive calendar calculations.

**Code inspection** (in `lib/grid_codec/types/timestamp.ex`):
```elixir
def encode_value(%DateTime{} = dt), do: <<DateTime.to_unix(dt, :microsecond)::little-signed-64>>
def encode_value(n) when is_integer(n), do: <<n::little-signed-64>>  # Fast path!
```

**Optimization:** Use `System.system_time(:microsecond)` instead of `DateTime.utc_now()` to bypass calendar conversions.

**Result:** ~2.6% CPU reduction by avoiding DateTime struct creation and conversion

### Profile Markers (Tagging Operations)

Profile markers let you tag specific operations with named identifiers that appear distinctly in perf output:

```elixir
require ExampleApp.ProfileMarkers, as: Markers

# Tag an encode operation
Markers.mark(:encode_order) do
  OrderCreated.encode(order)
end

# In profiles, you'll see:
# 'Elixir.ExampleApp.ProfileMarkers':'__profile_encode_order__'/1
```

**Finding markers in profiles:**

```bash
# In report_flat.txt
grep "__profile_" profile/output/report_flat.txt

# In flame graph (browser): Ctrl+F and search "profile_encode"
```

**Why markers are powerful:**

- Show as distinct named functions in perf/flame graphs
- Allow tracking time spent in specific code paths
- Can be nested for hierarchical analysis
- Low overhead (~1-2 function call overhead)

**Available markers:**

```elixir
# Encoding
:encode, :encode_order, :encode_header, :encode_payload, :encode_field

# Decoding  
:decode, :decode_order, :decode_header, :decode_payload, :decode_field

# Roundtrip/Phase
:roundtrip, :full_roundtrip, :encode_phase, :decode_phase

# Custom
:custom_1, :custom_2, :custom_3, :batch_operation, :single_operation
```

### Profile-Driven Optimization Workflow

1. **Establish baseline**
   ```bash
   ./profile/run.sh
   # Review profile/output/report.txt
   ```

2. **Make optimization changes**
   - Edit code in `lib/` 
   - Changes are immediately available (workspace is mounted)

3. **Re-profile**
   ```bash
   ./profile/run.sh
   ```

4. **Compare results**
   - Check if target function % decreased
   - New bottlenecks may emerge - that's expected

5. **Iterate until satisfied**

### Common Optimization Opportunities

Based on profiling data, common optimization patterns:

#### 1. Reduce Struct Field Access
```elixir
# Before: Multiple field accesses
<<struct.field1::32, struct.field1::32>>  # field1 accessed twice

# After: Single access
field1 = struct.field1
<<field1::32, field1::32>>
```

#### 2. Pre-allocate Binary Size
```elixir
# Before: Dynamic growth
acc <> <<field1::32>> <> <<field2::64>>

# After: Single allocation
<<field1::32, field2::64>>
```

#### 3. Use IOLists When Possible
```elixir
# Before: Force binary
IO.iodata_to_binary([header, body, footer])

# After: Keep as iolist (if consumer accepts it)
[header, body, footer]
```

## Running Tests

```bash
# All tests
mix test

# Specific test file
mix test test/grid_codec/struct_test.exs

# With coverage
mix test --cover
```

### Doctest harness for generated codecs

GridCodec can emit deterministic `iex>` examples on codec modules (default). Consumer apps can treat `import ExUnit.DocTest` plus `for mod <- codec_modules, do: doctest(mod)` as bulk coverage for generated `new/1`, `encode/2`, and `decode/2`. Pair that with a small meta-test that uses `Code.fetch_docs/1` to assert each codec’s docs include `"iex>"`, so empty-doc regressions do not slip through. See `test/grid_codec/codec_doctest_test.exs` and `example_app/test/example_app/codec_doctest_test.exs`. Opt out per module with `use GridCodec.Struct, doc_examples: false`.

## Code Quality

```bash
# Format check
mix format --check-formatted

# Static analysis (requires Credo >= 1.7.18 on Elixir 1.20)
mix credo --strict

# Type checking
mix dialyzer

# Elixir 1.20: also compile test/support and assert zero warnings in tests
MIX_ENV=test mix compile --warnings-as-errors
mix test   # grep for warning: — should be empty
```

**Elixir 1.20 upgrade notes** (gradual types, dead generated clauses, `getter_returns_binary?/0`,
bitstring `^pin` in tests): see [`docs/elixir-1.20-upgrade/`](docs/elixir-1.20-upgrade/README.md).

## Benchmarks

Benchmarks live in `example_app/benchmarks/`:

```bash
cd example_app
mix run benchmarks/encode_decode.exs
mix run benchmarks/parameterized_bench.exs
```

Note: Benchmarks measure throughput. Use profiling for understanding WHERE time is spent.

## Architecture Notes

### Compile-Time Code Generation

GridCodec generates encode/decode functions at compile time based on the struct definition:

```elixir
defmodule MyEvent do
  use GridCodec.Struct

  defcodec do
  field :id, :u64, doc: "Event identifier."
  field :name, GridCodec.Types.String, doc: "Human-readable event name."
  end
end
```

This generates:
- `MyEvent.encode/1` - Convert struct → `{:ok, binary} | {:error, ValidationError.t()}`
- `MyEvent.decode/1` - Convert binary → `{:ok, struct} | {:error, term()}`
- `MyEvent.new/1` - Coerce + validate → `{:ok, struct} | {:error, ValidationError.t()}`
- `MyEvent.new_binary/1` - Coerce + validate + encode → `{:ok, binary} | {:error, ...}`

### Key Modules

- `GridCodec.Struct.Compiler` - Generates encode/decode AST
- `GridCodec.Types.*` - Type implementations (includes `:datetime_us`/`:datetime_ns` for DateTime-domain timestamps, `PrefixedId` for tagged entity IDs)
- `GridCodec.Transcoder` - Compile-time codec-to-codec field extraction with `validate: false | :source | :target | :both`, source `validate_binary/1` support, and target `new_binary/1` fast-path integration
- `GridCodec.Header` - Binary header handling
- `GridCodec.Binary` - Sub-binary lifecycle utilities (`detach/1`, `copy_field/1`)
- `GridCodec.Lookup` - Runtime engine for Elixir-side `lookups do` accessors over decoded `group` and `batch` fields (not part of `.grid`)
- `GridCodec.Validations` - Builtin validation descriptors (`compare/3`, `present/1`, `one_of/2`) for struct validation pipelines
- `GridCodec.ValidationErrors` - Container for accumulated validation failures
- `GridCodec.Batch` - Heterogeneous batch wrapper with strategy dispatch
- `GridCodec.Batch.PaddedUnion` - Fixed-size padded entries (default strategy)
- `GridCodec.Batch.TypedFrames` - Length-prefixed entries (compact strategy)
- `GridCodec.Schema.Parser` - Parse `.grid` schema files with `import` resolution (`parse_file_with_imports/2`), `@syntax` validation, `current_syntax/0`
- `GridCodec.Schema.Formatter` - Generate `.grid` files: `format/5`, `format_master/5`, `format_struct_file/3`, `format_enum_file/2`, `format_custom_type_file/2` (all accept `opts` with `:syntax`, `:imports`); `current_syntax/0`, `detect_all_enums/1`, `detect_custom_types/1`, `detect_all_custom_types/1`, `referenced_enums/2`, `referenced_custom_types/2`
- `GridCodec.Breaking.*` - Breaking change detection (Checker, Differ, Rules.Wire, Rules.Source, Config)
- `GridCodec.Registry` - Runtime codec lookup, dispatch, `lookup_enum_by_name/1` and `lookup_custom_type_by_name/1` for `.grid` type auto-resolution
- `GridCodec.Type.Refined` - Helper for field-local refinement-style custom types built on top of existing base types

### Batch Strategies

The `batch/2` macro supports two encoding strategies:

| Strategy | Wire Size | Random Access | Best For |
|----------|-----------|---------------|----------|
| `:padded_union` | `n × (max_bl + 5)` | O(1) from raw binary | Similar-size types |
| `:typed_frames` | `8 + Σ(payload_i + 7)` | O(1) after decode | Varied-size types |

Choose `:typed_frames` when `max_block / min_block > 3` to avoid padding waste.

### Virtual Fields

Fields that exist on the struct but are excluded from binary encoding:

```elixir
defcodec do
  field :id, :u64
  virtual :cache, default: %{}
  virtual :metadata, default: nil, validate: false
end
```

- `validate: true` (default) — included in `new/1` coercion
- `validate: false` — skipped by `new/1` entirely
- Skipped by `.grid` export

### Struct Lifecycle Hooks

Codecs may define optional `before_encode/2` and `after_decode/2` callbacks to
normalize between runtime shape and wire shape:

```elixir
@impl GridCodec.Struct
def before_encode(%__MODULE__{} = struct, header_or_nil), do: struct

@impl GridCodec.Struct
def after_decode(%__MODULE__{} = struct, header_or_nil), do: {:ok, struct}
```

- `before_encode/2` runs before generated validation and binary encoding. Use it
  to copy durable state out of runtime caches/indexes into `.grid` fields.
- `after_decode/2` runs after wire decode and receives decoded header metadata
  when available (or `nil` for payload-only decode). Use it to rebuild derived
  virtual fields such as lookup maps.
- Hooks may return the struct directly, `{:ok, struct}`, or `{:error, reason}`.
- Hooks are runtime-only Elixir behavior and are not exported to `.grid`.

### Validation Pipelines

GridCodec supports three validation layers:

- **Coercion/cast validation** - `new/1`, `update/2`, and `new_binary/1` convert external input into field domain values
- **Type validation** - `validate: true` runs per-type checks like range, format, and refined-type rules
- **Struct validation pipelines** - `validations do` / `invariants do` add accumulating, non-raising state checks over the decoded struct

Use `GridCodec.Type.Refined` for field-local rules like non-negative values or
non-empty strings. Use `validations do` for cross-field state invariants like
`end_time >= start_time`.

Binary-capable validators are a subset: they require fixed-size getter-based
field access and are what power `validate_binary/1`, `decode(validate: :binary | :both)`,
and `GridCodec.Transcoder` source-side validation. Decoded-only validators
(for example callback validators and expression invariants over variable-width
fields) still require a decoded struct.

Important boundary: validation declarations are **runtime-only Elixir metadata**.
They are not exported to `.grid`, not parsed from `.grid`, and do not affect the
wire protocol.

### Framed Groups

Groups with variable-length entries use length-prefixed framing:

```elixir
defcodec do
  group :bills, of: Bill, framing: :length_prefixed
end
```

Wire format: `numEntries (u32 LE) | [payload_len (u16 LE) | payload]*`.
Eagerly decodes to a plain list. Compatible with `lookups` for map-keyed access.

### Scalar Groups

Homogeneous lists of scalar values, using the same `of:` keyword as typed groups:

```elixir
defcodec do
  group :tag_ids, of: :uuid         # fixed-size → standard group wire format
  group :labels, of: :string16      # variable-length → auto-selects framed encoding
  group :scores, of: :u32           # fixed-size integers
end
```

The compiler detects whether `of:` refers to a struct module or a scalar type atom
and dispatches accordingly. Fixed-size types use the standard group header.
Variable-length types auto-select `framing: :length_prefixed`. Both eagerly decode
to a plain list.

Note: `.grid` schema format does not yet support scalar groups.

### Binary Memory Model

GridCodec binaries are almost always > 64 bytes, making them **refc binaries**
(reference-counted, stored in `binary_alloc`). Key implications:

- **Sending is O(1)**: `send/2` copies only the ProcBin pointer (~5 words), not
  the payload. This is why "encode once, fan out to N" is efficient.
- **ETS insertion is O(1)**: ETS gets its own ProcBin reference.
- **Sub-binary retention**: `get/2` on `:uuid` and `char_array` fields returns
  sub-binaries that pin the entire original. Use `get(bin, :field, copy: true)`
  or `GridCodec.Binary.detach/1` to release the original.
- **GC and binary virtual heap**: The `bin_vheap_sz` threshold triggers GC of
  dead ProcBin references. Tune `min_bin_vheap_size` for binary-heavy processes.

See [The BEAM Book — Memory](https://github.com/happi/theBeamBook/blob/master/chapters/memory.asciidoc)
for the full BEAM binary memory model.

### Type System

Each type implements callbacks:
- `encode_ast/4` - Generate encoding AST
- `decode_pattern_ast/2` - Generate decode pattern
- `size/0` - Fixed size (if known)
- `validate_ast/3` - (optional) Pre-encode type validation used by `validate: true`
- `coerce_ast/1` - (optional) External-input coercion used by `new/1` / `new_binary/1`
- `compare_values/2` - (optional) Type-aware comparisons for invariants and binary validation
- `encode_to_wire_ast/2` - (optional) Convert domain value to wire type value
- `decode_as_ast/2` - (optional) Decode-time wire→domain type transformation (used by `wire_format:`)

### PrefixedId (Composite Type)

Define entity-specific ID types with a wire tag byte for DB-level filtering.

**Generated source (recommended)** — creates a full `.ex` file with visible functions, docs, specs:

```bash
mix grid_codec.gen.prefixed_id MyApp.Types.UserId --prefix user --tag 1
```

The generated module contains `use GridCodec.Types.PrefixedId` (slim: only `@impl` callbacks)
plus all public helpers as visible source code. The macro detects user-defined `generate/0`
and skips injecting helpers, so both modes coexist without conflict.

**Compact macro-only** — all helpers injected at compile time (invisible in source):

```elixir
defmodule MyApp.Types.UserId do
  use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01
end
```

Wire format: 17 bytes (u8 tag + 16-byte UUID). Provides `generate/0`, `from_uuid/1`,
`to_uuid/1`, `valid?/1`, `prefix/0`, `tag/0`. SQL generation (`gridcodec.read_prefixed_id`)
reconstructs the prefixed string at the DB level.

### Parameterized Types and `wire_format:`

Fields support parameterized types and explicit wire format override:

```elixir
# Domain type: Decimal with 8 decimal places
# Wire format: i64 (8 bytes, faster than full 9-byte decimal)
field :price, {:decimal, scale: 8}, wire_format: :i64
```

The type argument is the **domain type** (what the field IS). The `wire_format:`
option overrides the binary encoding. The compiler uses the wire type for
size/alignment/binary patterns and the domain type for value conversion.

### Schema Evolution & Breaking Change Detection

GridCodec includes a schema evolution system inspired by [Buf](https://buf.build/docs/breaking/).

**`.grid` files** are a versioned, language-neutral schema format. Every file starts with
`@syntax N` declaring the format version (currently syntax 1). The formal specification
lives in `GridCodec.Schema.Parser`'s `@moduledoc`.

The export generates a directory per `schema_id`, each containing a `schema.grid` master
file plus individual struct/enum/custom-type files. Individual struct files import their
enum and custom type dependencies, making each file self-contained.

Export includes only codecs that set `schema_id:` or `schema:` on `use GridCodec.Struct`.
Codecs that omit both still default to `schema_id: 0` on the wire but are excluded from
`.grid` output (`__schema__/0` includes `grid_schema_export: boolean`). Use
`mix grid_codec.export --prune` to delete stale generated files after removing a codec
or its schema options.

**Custom type declaration blocks** allow full specification of composite types:

```
prefixed_id UserId {
  prefix: "user"
  tag: 1
}

char_array Symbol {
  length: 8
}

bitset Permissions : u8 {
  read = 0
  write = 1
  execute = 2
}
```

These are exported to their own `.grid` files and imported by struct files that reference them.

```bash
# Export schemas (creates events/schema.grid, events/order_created.grid, etc.)
cd example_app && mix grid_codec.export --output-dir priv/schemas

# Target a specific syntax version
mix grid_codec.export --syntax 1

# Verify schemas are up to date (CI mode)
mix grid_codec.export --check

# Regenerate and remove orphaned files after deletions/renames
mix grid_codec.export --prune

# Detect breaking changes against git baseline
mix grid_codec.breaking --against HEAD~1
```

`mix grid_codec.export --check` is an artifact-sync check: it fails when generated
`.grid` files are missing, stale, or unexpectedly present. Use
`mix grid_codec.breaking` alongside it to determine whether the schema change
itself is compatible (for example `WIRE_STRUCT_REMOVED` after deleting a struct).

**Directory structure:**
```
priv/schemas/
  events/
    schema.grid              # master: @syntax + schema block + import directives
    order_created.grid       # struct file (imports order_side.grid)
    order_side.grid          # enum file
    trade_settled.grid       # struct importing enums from same + other schemas
  bench_sizes/
    schema.grid              # imports ../events/order_side.grid (cross-schema)
    tagged_metric.grid       # struct importing cross-schema enum
```

**Schema directory names and syntax version** are configured via application config:
```elixir
config :my_app, :grid_codec,
  schemas: %{100 => "events", 200 => "bench_sizes"},
  syntax: 1
```

Modules can reference schemas by name instead of numeric ID. The `schema:` option
resolves at compile time from the same config map:
```elixir
use GridCodec.Struct, template_id: 1, schema: "events", name: "OrderCreated"
# Equivalent to: schema_id: 100 (resolved from config)
```
`schema:` and `schema_id:` are mutually exclusive. Unknown names raise at compile time.
Unconfigured schema_ids default to `schema_{id}`. File paths are derived from the
struct's `name:` option (e.g., `"Namespace.EventName"` → `namespace/event_name.grid`).
Syntax version precedence: `--syntax` CLI flag > config > `Formatter.current_syntax()`.

**`import` directives** are resolved automatically by the parser (`parse_file_with_imports/2`),
the breaking change checker, and the `grid_file:` compiler option. Cross-schema imports
use relative paths (e.g., `../events/order_side.grid`).

**Compiling from `.grid` files with custom types:**
```elixir
use GridCodec.Struct,
  grid_file: "priv/schemas/events/order.grid",
  message: :Order,
  types: %{OrderSide: MyApp.Types.OrderSide}
```
The `types:` option maps `.grid` type names to Elixir modules. When omitted,
`GridCodec.Registry.lookup_enum_by_name/1` auto-resolves enum modules by matching
their last module segment.

`doc:` metadata on fields, groups, and enum values is exported as structured schema
data rather than comments so it can round-trip through parsing, surface in generated
ExDoc, and participate in breaking-change review.

**Rule categories:**
- **WIRE** (27 rules) — Binary compatibility: field removal, type changes, size changes, reordering, `wire_format` changes, `since` changes, `presence` changes, constant value changes, type parameter changes, syntax version changes (`WIRE_SYNTAX_VERSION_CHANGED`), custom type changes (`WIRE_PREFIXED_ID_TAG_CHANGED`, `WIRE_CHAR_ARRAY_LENGTH_CHANGED`, `WIRE_BITSET_UNDERLYING_CHANGED`, `WIRE_BITSET_FLAG_REMOVED`, `WIRE_BITSET_FLAG_VALUE_CHANGED`)
- **SOURCE** (9 rules) — API compatibility: struct removal, field renames, default changes, required field additions, `SOURCE_PREFIXED_ID_PREFIX_CHANGED`
- **DOCS** — Documentation drift for field, group, group-field, and enum-value `doc:` metadata, with policy-controlled severities (`include_docs`, `fail_on`, `severity_overrides`)

**Configuration** via `.grid_codec.exs`:
```elixir
%{
  against: "HEAD~1",
  except: [:SOURCE_FIELD_DEFAULT_CHANGED],
  category: :source,
  include_docs: true,
  fail_on: [:error],
  severity_overrides: %{DOC_FIELD_DOC_REMOVED: :error}
}
```

**CI integration:** The `breaking` job in `.github/workflows/ci.yml` runs `mix grid_codec.breaking` on pull requests with `fetch-depth: 0` for git history access.

