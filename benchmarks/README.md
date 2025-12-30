# GridCodec Benchmarks

## Quick Benchmark

For fast development iteration:

```bash
mix run benchmarks/quick_bench.exs
```

This runs a simple encode/decode/get benchmark with timing output.

## Comprehensive Benchmarks

For detailed, interactive benchmarks with visualizations, use the **Livebooks** in the `livebooks/` directory:

| Livebook | Description |
|----------|-------------|
| `livebooks/01_performance_comparison.livemd` | GridCodec vs JSON, ETF, Protobuf, MessagePack |
| `livebooks/02_subbinary_fanout.livemd` | Direct field access & memory-efficient fan-out |
| `livebooks/03_internal_analysis.livemd` | BEAM bytecode analysis (for maintainers) |

To run Livebooks:
```bash
# Install livebook if needed
mix escript.install hex livebook

# Start server
livebook server
```

Then open http://localhost:8080 and navigate to the `livebooks/` folder.
