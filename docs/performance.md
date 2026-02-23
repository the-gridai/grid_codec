# Performance Guide

GridCodec is optimized for high-throughput BEAM workloads. This guide focuses on
practical performance decisions.

## Use `get/2` for Hot Reads

For fixed-size fields, prefer zero-copy access:

```elixir
require MyCodec
price = MyCodec.get(binary, :price)
```

This avoids full decode when only a subset of fields is needed.

## Keep Integer Inputs In Range

Integer encoders now validate range. Validation failures are cheap and explicit,
but invalid upstream values will raise during encode. Validate upstream data at
boundaries for stable throughput.

## Groups

- Use groups for repeated fixed-size entries.
- Keep group entry structure compact.
- Avoid unnecessary full `to_list/1` on very large groups when stream/reduce is enough.

## Profile Before Optimizing

Use the profiling workflow:

```bash
./profile/run.sh
./profile/run.sh --mode=encode
./profile/run.sh --mode=decode
```

Inspect `profile/output/report.txt` and `flamegraph.svg` to identify actual hot paths.

## Benchmark in Context

Use `example_app/benchmarks` to evaluate realistic encode/decode workloads before
and after changes. Favor measured improvements over intuition.
