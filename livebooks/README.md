# GridCodec Livebooks

Interactive, visual notebooks for learning about GridCodec and binary serialization in Elixir.

## Philosophy

These Livebooks are designed for **visual learners**. Each notebook includes:

- **Interactive charts** with VegaLite
- **ASCII diagrams** explaining memory layouts and data flow
- **Live benchmarks** you can modify and re-run
- **Deep explanations** of "why" not just "how"
- **Mermaid diagrams** for architecture and decision flows

## Notebooks

### [01_performance_comparison.livemd](01_performance_comparison.livemd)
**Audience:** Everyone (users, evaluators, documentation)

Compares GridCodec against JSON (including jiffy NIF), ETF, Protobuf, MessagePack:
- Binary size comparison
- Encoding and decoding speed
- Field access patterns
- Trade-offs for each format

**Key Visualizations:**
- Binary size comparison chart
- Encoding/decoding speed benchmarks
- Memory allocation per operation
- Decision flowchart for format selection

---

### [02_subbinary_fanout.livemd](02_subbinary_fanout.livemd)
**Audience:** Users building high-throughput systems

Explains O(1) field access and memory-efficient fan-out patterns:
- How BEAM handles large binaries (refc binaries)
- Why decoded maps get copied but binaries don't
- The "defer decode" pattern for message routing
- Memory usage at scale (1, 10, 100, 1000 subscribers)

**Key Visualizations:**
- Memory usage vs subscriber count
- Binary layout diagram with offsets
- Fan-out architecture pattern
- Field access benchmark

---

### [03_internal_analysis.livemd](03_internal_analysis.livemd)
**Audience:** Contributors and curious developers

Under-the-hood analysis of how GridCodec generates code:
- The compilation pipeline (defcodec → BEAM bytecode)
- Schema structure and field offset calculation
- BEAM instruction analysis (what does encode/1 actually do?)
- Comparison with hand-written "optimal" code
- Potential optimizations (pattern match, || vs case)

**Key Visualizations:**
- Compilation pipeline flowchart
- Bytecode instruction breakdown
- Optimization roadmap
- Performance delta analysis

## Running the Livebooks

### Option 1: Livebook Desktop (Recommended)
1. Download [Livebook](https://livebook.dev/)
2. Open any `.livemd` file

### Option 2: CLI
```bash
# Install (one time)
mix escript.install hex livebook

# Run
livebook server
```
Navigate to http://localhost:8080 and open the `livebooks/` folder.

### Option 3: In Project
```bash
cd /path/to/grid_codec
livebook server --home .
```

## Quick Development Benchmark

For fast iteration during development, use the standalone script:

```bash
mix run benchmarks/quick_bench.exs
```

This runs in ~1 second and gives you encode/decode/get timing.

## Learning Path

**New to GridCodec?**
1. Start with `01_performance_comparison.livemd` to understand the serialization landscape
2. Continue to `02_subbinary_fanout.livemd` to learn about field access and fan-out patterns

**Want to contribute?**
1. Read `03_internal_analysis.livemd` to understand the internals
2. Check the "Optimization Roadmap" section for ideas

## Design Principles

These Livebooks follow these principles:

1. **Show, don't tell** - Every concept has a visualization
2. **Explain the "why"** - Not just benchmarks, but context for decisions
3. **Interactive exploration** - Readers can modify and re-run cells
4. **Layered depth** - Overview → Details → Implementation
5. **Real-world context** - Examples from trading, event sourcing, PubSub
