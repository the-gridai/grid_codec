# GridCodec Profiling Container
# 
# This container provides Linux profiling tools (perf, valgrind, strace)
# for accurate BEAM/Elixir performance analysis.
#
# Build: docker build -t gridcodec-profile profile/
# Run:   ./profile/run.sh
#
FROM elixir:1.19.4-otp-28

# Install profiling and debugging tools
RUN apt-get update && apt-get install -y \
    linux-perf \
    valgrind \
    strace \
    gdb \
    git \
    curl \
    wget \
    htop \
    procps \
    perl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install FlameGraph scripts for visualization
RUN git clone --depth 1 https://github.com/brendangregg/FlameGraph.git /opt/FlameGraph
ENV PATH="/opt/FlameGraph:${PATH}"

WORKDIR /workspace

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Default to bash for interactive use
CMD ["bash"]

