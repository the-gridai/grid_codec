#!/bin/bash
#
# GridCodec Profiling Tool
# ========================
# 
# Runs production-representative profiling of GridCodec encode/decode operations
# inside a Linux container with full profiling tools (perf, valgrind, flamegraph).
#
# Key features:
# - JIT symbol resolution via OTP's +JPperf flag (resolves BEAM JIT addresses)
# - Isolated profiling: warmup runs BEFORE perf starts, so only encode/decode is captured
# - Flame graphs with full Elixir function names
#
# Usage:
#   ./profile/run.sh [command] [options]
#
# Commands:
#   profile     Run perf profiling (default)
#   shell       Enter interactive shell in container
#   build       Build the Docker image only
#   help        Show this help
#
# Options:
#   --mode=MODE     Profile mode: all, encode, decode (default: all)
#   --iterations=N  Number of profiled iterations (default: 5000000)
#   --warmup=N      Number of warmup iterations (default: 100000)
#   --no-flamegraph Skip flame graph generation
#
# Examples:
#   ./profile/run.sh                    # Full profile with defaults
#   ./profile/run.sh --mode=encode      # Profile encode only
#   ./profile/run.sh shell              # Interactive shell
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="gridcodec-profile"

# Defaults
COMMAND="profile"
MODE="all"
ITERATIONS=5000000
WARMUP=100000
GENERATE_FLAMEGRAPH=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        profile|shell|build|help)
            COMMAND="$1"
            shift
            ;;
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        --iterations=*)
            ITERATIONS="${1#*=}"
            shift
            ;;
        --warmup=*)
            WARMUP="${1#*=}"
            shift
            ;;
        --no-flamegraph)
            GENERATE_FLAMEGRAPH=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

show_help() {
    head -28 "$0" | tail -23
}

build_image() {
    echo "=== Building profiling container ==="
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
}

get_version_info() {
    cd "$PROJECT_DIR"
    VERSION=$(grep '@version "' mix.exs | head -1 | sed 's/.*"\(.*\)".*/\1/')
    GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        GIT_DIRTY=""
    else
        GIT_DIRTY="+dirty"
    fi
    echo "${VERSION} (${GIT_BRANCH}@${GIT_COMMIT}${GIT_DIRTY})"
}

run_profile() {
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        build_image
    fi
    
    VERSION_INFO=$(get_version_info)
    OUTPUT_DIR="$PROJECT_DIR/profile/output"
    mkdir -p "$OUTPUT_DIR"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           GridCodec Production Profiler                      ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Version:     $VERSION_INFO"
    echo "║  Mode:        $MODE"
    echo "║  Warmup:      $WARMUP iterations"
    echo "║  Profile:     $ITERATIONS iterations"
    echo "║  Flamegraph:  $GENERATE_FLAMEGRAPH"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Create a temp script file for the container
    SCRIPT_FILE="$PROJECT_DIR/profile/.profile_script.sh"
    cat > "$SCRIPT_FILE" << 'INNERSCRIPT'
#!/bin/bash
set -e

MODE="$1"
ITERATIONS="$2"
WARMUP="$3"
GENERATE_FLAMEGRAPH="$4"

cd /workspace
echo "=== Compiling in PROD mode ==="
cd example_app
MIX_ENV=prod mix deps.get --quiet 2>/dev/null || true
MIX_ENV=prod mix compile --force 2>&1 | tail -3
echo ""

# Phase 1: JIT warmup WITHOUT perf (eliminates warmup noise)
echo "=== Phase 1: JIT Warmup (no profiling) ==="
echo "Running ${WARMUP} warmup iterations to optimize JIT..."
ERL_FLAGS="+JPperf true" MIX_ENV=prod mix run -e "
  Application.put_env(:gridcodec_profile, :mode, :${MODE})
  Application.put_env(:gridcodec_profile, :iterations, 0)
  Application.put_env(:gridcodec_profile, :warmup, ${WARMUP})
  ExampleApp.ProfileRunner.run_warmup_only()
" 2>&1
echo "Warmup complete."
echo ""

# Phase 2: Profile ONLY encode/decode with perf
# +JPperf true enables JIT symbol maps for perf (resolves hex addresses to function names)
# -k mono uses monotonic clock (required for perf inject --jit)
echo "=== Phase 2: Profiling encode/decode (${ITERATIONS} iterations) ==="
echo "Starting perf with JIT symbol resolution (+JPperf true)..."
ERL_FLAGS="+JPperf true" MIX_ENV=prod perf record -k mono -g -F 9999 -o /tmp/perf.data -- mix run -e "
  Application.put_env(:gridcodec_profile, :mode, :${MODE})
  Application.put_env(:gridcodec_profile, :iterations, ${ITERATIONS})
  Application.put_env(:gridcodec_profile, :warmup, 0)
  ExampleApp.ProfileRunner.run_profile_only()
" 2>&1

# Find the perf map generated by the BEAM JIT
PERF_MAP=$(ls /tmp/perf-*.map 2>/dev/null | head -1)
if [ -n "$PERF_MAP" ]; then
    echo ""
    echo "JIT symbols available: $PERF_MAP ($(wc -l < "$PERF_MAP") symbols)"
    
    # Copy the JIT map for reference
    cp "$PERF_MAP" /workspace/profile/output/jit.map
fi

# Inject JIT symbols into perf.data for FULL symbol resolution
# This merges the JIT-compiled function names directly into the perf data
echo ""
echo "=== Injecting JIT symbols into perf data ==="
if perf inject --jit -i /tmp/perf.data -o /tmp/perf.jitted.data 2>/dev/null; then
    echo "JIT injection successful - using enhanced symbol resolution"
    PERF_DATA="/tmp/perf.jitted.data"
    cp /tmp/perf.jitted.data /workspace/profile/output/perf.data
else
    echo "JIT injection not available - using standard perf data"
    PERF_DATA="/tmp/perf.data"
    cp /tmp/perf.data /workspace/profile/output/perf.data
fi
echo "Perf data saved: profile/output/perf.data"

echo ""
echo "=== Generating Reports ==="

# 1. Summary report (what we show on screen) - top functions with call graphs
echo "  → report.txt (summary with call graphs)"
perf report -i "$PERF_DATA" --stdio --no-children -n --percent-limit 0.3 2>&1 | head -200 > /workspace/profile/output/report.txt

# 2. Flat report (easier for AI parsing) - just function names and percentages
echo "  → report_flat.txt (flat list, AI-friendly)"
perf report -i "$PERF_DATA" --stdio --no-children -n --percent-limit 0.1 -g none 2>&1 > /workspace/profile/output/report_flat.txt

# 3. Full report (no filtering) - complete data for deep analysis
echo "  → report_full.txt (complete, no filtering)"
perf report -i "$PERF_DATA" --stdio --no-children -n --percent-limit 0 2>&1 > /workspace/profile/output/report_full.txt

# 4. Caller/callee report - shows what calls what
echo "  → report_callers.txt (caller/callee relationships)"
perf report -i "$PERF_DATA" --stdio -n --percent-limit 0.2 --call-graph=caller 2>&1 > /workspace/profile/output/report_callers.txt

# Display summary
echo ""
echo "=== TOP FUNCTIONS (Self Time) ==="
head -80 /workspace/profile/output/report.txt

if [ "$GENERATE_FLAMEGRAPH" = "true" ]; then
    echo ""
    echo "=== Generating flame graph ==="
    perf script -i "$PERF_DATA" | stackcollapse-perf.pl | flamegraph.pl \
        --title "GridCodec Profile (${MODE})" \
        --subtitle "${ITERATIONS} iterations" \
        > /workspace/profile/output/flamegraph.svg
    echo "Saved: profile/output/flamegraph.svg"
    
    # Also save the collapsed stacks (useful for programmatic analysis)
    perf script -i "$PERF_DATA" | stackcollapse-perf.pl > /workspace/profile/output/stacks.folded
    echo "Saved: profile/output/stacks.folded (collapsed stack traces)"
fi
INNERSCRIPT
    chmod +x "$SCRIPT_FILE"
    
    # Run in container
    docker run --rm --privileged \
        -v "$PROJECT_DIR:/workspace" \
        -w /workspace \
        -e MIX_ENV=prod \
        "$IMAGE_NAME" \
        bash /workspace/profile/.profile_script.sh "$MODE" "$ITERATIONS" "$WARMUP" "$GENERATE_FLAMEGRAPH"
    
    # Clean up temp script
    rm -f "$SCRIPT_FILE"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Profile complete! Output files:"
    echo ""
    echo "  Reports (for analysis):"
    echo "    - profile/output/report.txt        (summary with call graphs)"
    echo "    - profile/output/report_flat.txt   (flat list, AI-friendly)"
    echo "    - profile/output/report_full.txt   (complete, no filtering)"
    echo "    - profile/output/report_callers.txt (caller/callee relationships)"
    echo ""
    echo "  Raw data (for custom analysis):"
    echo "    - profile/output/perf.data         (raw perf data)"
    if [ "$GENERATE_FLAMEGRAPH" = true ]; then
        echo "    - profile/output/flamegraph.svg    (interactive flame graph)"
        echo "    - profile/output/stacks.folded     (collapsed stacks for scripting)"
    fi
    echo ""
    echo "  To run custom perf commands:"
    echo "    ./profile/run.sh shell"
    echo "    perf report -i /workspace/profile/output/perf.data [options]"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

run_shell() {
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        build_image
    fi
    
    echo "Entering profiling container..."
    echo "Your workspace is mounted at /workspace"
    echo ""
    
    docker run -it --rm --privileged \
        -v "$PROJECT_DIR:/workspace" \
        -w /workspace \
        -e MIX_ENV=prod \
        "$IMAGE_NAME" \
        bash
}

# Main
case $COMMAND in
    help)
        show_help
        ;;
    build)
        build_image
        ;;
    shell)
        run_shell
        ;;
    profile)
        run_profile
        ;;
esac
