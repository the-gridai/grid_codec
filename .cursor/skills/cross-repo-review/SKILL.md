---
name: cross-repo-review
description: Review code from other repos (that consume GridCodec) that consume GridCodec. Use when analyzing consumer codebases, suggesting integration improvements, or writing specs for other teams.
---

# Cross-Repo Review

## How to Access Consumer Code

1. Clone the branch: `gh repo clone Org/repo /tmp/repo-checkout -- --branch branch-name --depth 1`
2. Read relevant files with Read tool (not `cat`)
3. Use explore subagents for broad codebase analysis

## Review Checklist for GridCodec Consumers

- [ ] Using latest grid_codec version (check `mix.exs` dep)
- [ ] Custom enums in groups (needs v0.11.0+ for alias resolution)
- [ ] Telemetry enabled on heavy codecs (`telemetry: true`)
- [ ] `telemetry_min_duration` set to filter cheap operations
- [ ] `to_lists_parallel/2` used for multi-group decode on large data
- [ ] `:i64` for fixed-point integers (not `:positive_decimal` when state is integer-native)
- [ ] `:uuid` in groups (not `:uuid_string` unless string format is needed internally)
- [ ] Unnecessary fields dropped from carry-forward groups
- [ ] `GridCodec.Telemetry.Metrics.prom_ex_metrics/1` for PromEx integration (NOT `use PromEx.Plugin` in grid_codec — it won't compile as a dep)

## Schema Evolution for Consumers

- [ ] Consumer has a `.grid_codec.exs` config if using breaking change detection
- [ ] `.grid` baselines committed to version control (`priv/schemas/`)
- [ ] All `.grid` files include `@syntax N` directive (currently `@syntax 1`)
- [ ] Individual struct files import their enum dependencies (self-contained)
- [ ] Cross-schema enum references use correct relative import paths (e.g., `../events/order_side.grid`)
- [ ] CI runs `mix grid_codec.breaking` on pull requests
- [ ] `mix grid_codec.export` regenerated after schema changes
- [ ] Field options (`wire_format:`, `since:`, `presence:`, etc.) reflected in `.grid` baselines
- [ ] If targeting a specific syntax version: `config :app_name, :grid_codec, syntax: N` or `--syntax N` flag

## Writing Specs for Consumer Teams

Create specs as local files (NOT in version control). Include:
1. Current state assessment
2. Numbered recommendations with code examples
3. Before/after benchmark numbers from grid_codec's example_app
4. Expected impact table

Do NOT push specs to git unless explicitly asked.
