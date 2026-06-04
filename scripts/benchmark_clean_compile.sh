#!/usr/bin/env bash
# Measure clean compile time for grid_codec root and example_app.
# Usage: ./scripts/benchmark_clean_compile.sh [label]
# Appends one row to docs/elixir-1.20-upgrade/compile_times.tsv

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/docs/elixir-1.20-upgrade"
TSV="$OUT_DIR/compile_times.tsv"
LABEL="${1:-manual}"

mkdir -p "$OUT_DIR"

elixir_v="$(elixir -v 2>&1 | tr '\n' ' ' | sed 's/  */ /g')"
otp_v="$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null)"

measure_compile() {
  local dir="$1"
  cd "$dir"
  rm -rf _build
  MIX_ENV=dev mix deps.get --only dev >/dev/null 2>&1 || MIX_ENV=dev mix deps.get >/dev/null
  local t0=$SECONDS
  MIX_ENV=dev mix compile --force >&2
  echo $((SECONDS - t0))
}

if [[ ! -f "$TSV" ]]; then
  printf 'timestamp\tlabel\telixir_otp\tproject\tseconds\n' >"$TSV"
fi

timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
meta="${elixir_v} | OTP ${otp_v}"

root_sec="$(measure_compile "$ROOT" grid_codec)"
example_sec="$(measure_compile "$ROOT/example_app" example_app)"

printf '%s\t%s\t%s\tgrid_codec\t%s\n' "$timestamp" "$LABEL" "$meta" "$root_sec" >>"$TSV"
printf '%s\t%s\t%s\texample_app\t%s\n' "$timestamp" "$LABEL" "$meta" "$example_sec" >>"$TSV"

cat <<EOF

Compile benchmark ($LABEL)
  Elixir/OTP: $meta
  grid_codec:  ${root_sec}s
  example_app: ${example_sec}s
  Logged to: $TSV
EOF
