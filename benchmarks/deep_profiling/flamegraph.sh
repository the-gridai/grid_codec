#!/bin/bash
#
# Generate Flame Graphs for GridCodec
#
# Prerequisites:
#   git clone https://github.com/brendangregg/FlameGraph.git ~/FlameGraph
#   sudo apt-get install linux-tools-generic

set -e

FLAMEGRAPH_DIR="${HOME}/FlameGraph"
OUTPUT_DIR="/workspaces/grid_codec/artifacts/flamegraphs"
DURATION=${1:-30}

echo "=========================================="
echo "GridCodec Flame Graph Generator"
echo "=========================================="

# Check for FlameGraph tools
if [ ! -d "$FLAMEGRAPH_DIR" ]; then
    echo "FlameGraph not found. Installing..."
    git clone https://github.com/brendangregg/FlameGraph.git "$FLAMEGRAPH_DIR"
fi

# Check for perf
if ! command -v perf &> /dev/null; then
    echo "perf not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y linux-tools-generic linux-tools-$(uname -r) || true
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo ""
echo "Starting GridCodec workload..."
echo "Run duration: ${DURATION} seconds"
echo ""

# Start workload in background with JIT perf support
export ERL_FLAGS="+JPperf true"
cd /workspaces/grid_codec
mix run benchmarks/deep_profiling/perf_workload.exs &
WORKLOAD_PID=$!

# Wait for workload to start
sleep 2

# Get the beam.smp PID
BEAM_PID=$(pgrep -f "beam.smp" | head -1)

if [ -z "$BEAM_PID" ]; then
    echo "ERROR: Could not find beam.smp process"
    kill $WORKLOAD_PID 2>/dev/null || true
    exit 1
fi

echo "Found BEAM process: $BEAM_PID"
echo ""

# Record with perf
PERF_DATA="$OUTPUT_DIR/perf_$(date +%Y%m%d_%H%M%S).data"
echo "Recording perf data for ${DURATION} seconds..."
sudo perf record -F 999 -g -p $BEAM_PID -o "$PERF_DATA" -- sleep $DURATION || {
    echo "perf record failed - this may require kernel access"
    echo "Try running: sudo sysctl kernel.perf_event_paranoid=-1"
    kill $WORKLOAD_PID 2>/dev/null || true
    exit 1
}

# Stop workload
kill $WORKLOAD_PID 2>/dev/null || true

echo ""
echo "Generating flame graph..."

# Generate perf script
PERF_SCRIPT="$OUTPUT_DIR/perf.out"
sudo perf script -i "$PERF_DATA" > "$PERF_SCRIPT"

# Generate flame graph
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FLAME_SVG="$OUTPUT_DIR/gridcodec_flame_${TIMESTAMP}.svg"

cat "$PERF_SCRIPT" | \
    "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" | \
    "$FLAMEGRAPH_DIR/flamegraph.pl" \
        --title "GridCodec Flame Graph" \
        --subtitle "Encode/Decode/Get Workload" \
        > "$FLAME_SVG"

echo ""
echo "=========================================="
echo "RESULTS"
echo "=========================================="
echo "Perf data: $PERF_DATA"
echo "Flame graph: $FLAME_SVG"
echo ""
echo "Open the SVG in a browser to explore:"
echo "  firefox $FLAME_SVG"
echo "  google-chrome $FLAME_SVG"
echo ""
echo "WHAT TO LOOK FOR:"
echo "-----------------"
echo "1. Wide boxes at bottom = time spent there"
echo "2. Look for: process_main (main BEAM loop)"
echo "3. Look for: erts_garbage_collect (GC overhead)"
echo "4. Look for: erts_maps_get (map access)"
echo "5. Look for: your Elixir function names (JIT labeled)"
echo ""

# Also generate perf stat summary
echo "Running perf stat for quick metrics..."
export ERL_FLAGS="+JPperf true"
mix run benchmarks/deep_profiling/perf_workload.exs &
WORKLOAD_PID=$!
sleep 2
BEAM_PID=$(pgrep -f "beam.smp" | head -1)

STAT_OUTPUT="$OUTPUT_DIR/perf_stat_${TIMESTAMP}.txt"
sudo timeout 10 perf stat -e instructions,cycles,cache-references,cache-misses,branches,branch-misses -p $BEAM_PID 2>&1 | tee "$STAT_OUTPUT" || true

kill $WORKLOAD_PID 2>/dev/null || true

echo ""
echo "Perf stat saved to: $STAT_OUTPUT"
echo "Done!"

