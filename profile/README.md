# GridCodec Profiling Tool

A containerized profiling environment for analyzing GridCodec performance at the machine-code level.

## Quick Start

```bash
# Run full profile (builds container if needed)
./profile/run.sh

# Profile encode only
./profile/run.sh --mode=encode

# Profile decode only
./profile/run.sh --mode=decode

# Interactive shell for manual profiling
./profile/run.sh shell
```

## Output

After profiling, results are saved to `profile/output/`:

- **`report.txt`** - Text report with top functions by CPU time
- **`flamegraph.svg`** - Interactive flame graph (open in browser)

## Commands

| Command | Description |
|---------|-------------|
| `./profile/run.sh profile` | Run automated profiling (default) |
| `./profile/run.sh shell` | Enter interactive container shell |
| `./profile/run.sh build` | Build Docker image only |
| `./profile/run.sh help` | Show usage help |

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--mode=MODE` | `all` | Profile mode: `all`, `encode`, `decode` |
| `--iterations=N` | `5000000` | Number of profiled iterations |
| `--warmup=N` | `100000` | JIT warm-up iterations before profiling |
| `--no-flamegraph` | | Skip flame graph generation |

## What Gets Profiled

The profiler:

1. **Compiles in PROD mode** - Ensures production optimizations
2. **Warms up JIT** - Runs 100K iterations to fully optimize hot paths
3. **Profiles with `perf`** - High-frequency sampling (9999 Hz) of actual execution
4. **Generates reports** - CPU time breakdown and flame graphs

This captures the **actual production performance** of GridCodec, not cold-start or compilation overhead.

## Iterative Development

The workspace is mounted into the container, so:

1. Make code changes locally
2. Run `./profile/run.sh` to see impact
3. Iterate without committing

The profiler reports git status including uncommitted changes, so you can track what code is being profiled.

## Manual Profiling

Enter the interactive shell for custom profiling:

```bash
./profile/run.sh shell
```

Inside the container:

```bash
cd example_app

# Compile
MIX_ENV=prod mix compile

# Run perf manually
perf record -g -F 9999 -- mix run -e 'your_code_here'

# View report
perf report --stdio

# Generate flame graph
perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg
```

## Available Tools in Container

- **perf** - Linux performance counters (CPU profiling)
- **valgrind** - Memory analysis and profiling
- **strace** - System call tracing
- **gdb** - Debugger
- **FlameGraph** - Flame graph visualization scripts

## Understanding the Results

### Top Functions Report

```
  5.35%  beam.smp  beam.smp  [.] beam_jit_get_map_elements
  5.24%  beam.smp  libc.so   [.] __memcpy_generic
```

- First column: % of total CPU time in that function
- Functions with `erts_` or `beam_` are BEAM VM internals
- `__memcpy_generic` is memory copying (binary operations)

### Flame Graph

- **Width** = time spent (wider = more time)
- **Height** = call stack depth
- Click to zoom into specific call stacks
- Look for wide bars at the bottom - those are your hot paths

## Troubleshooting

### Docker not found
Install Docker Desktop or Docker Engine.

### Permission denied on run.sh
```bash
chmod +x profile/run.sh
```

### perf permission errors
The container runs with `--privileged` to enable perf. If issues persist:
```bash
# On host (Linux)
echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid
```

