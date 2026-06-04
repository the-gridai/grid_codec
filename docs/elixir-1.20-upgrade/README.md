# Elixir 1.20 / OTP upgrade experiment

Tracks clean compile times and gradual type-checking results when moving from the previous toolchain to Elixir 1.20.

## Files

| File | Purpose |
|------|---------|
| `compile_times.tsv` | Machine-readable timing rows (`timestamp`, `label`, toolchain, project, seconds) |
| `type_warnings.log` | Short list of lib/ gradual-type findings (post-fix) |
| `warnings-registry.md` | **Full warning inventory** with legit vs false-positive classification |
| `github-issues-draft/` | **Draft** upstream feedback for Elixir team (not published) |
| `example_app_warnings_full.log` | Latest `example_app` compile (includes deps) |
| `summary.md` | Human-readable notes and conclusions |

## Reproduce timings

```bash
./scripts/benchmark_clean_compile.sh before   # or after, post-upgrade label
```

## Reproduce type warnings (Elixir 1.20+)

Gradual types run during `mix compile`; no separate task is required.

```bash
cd /path/to/grid_codec
mix clean && mix compile --force 2>&1 | tee docs/elixir-1.20-upgrade/type_warnings_full.log
grep -E 'type (violation|warning)|typing|inferred' docs/elixir-1.20-upgrade/type_warnings_full.log > docs/elixir-1.20-upgrade/type_warnings.log || true
mix test
```
