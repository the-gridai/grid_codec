# Consumer Integration

Checklist for applications that depend on GridCodec (e.g. market exchange services, event pipelines). Use this when upgrading grid_codec or when reviewing integration quality.

## Version and dependency

- [ ] **Latest grid_codec** — Prefer a recent tag or hex version. Check `mix.exs` and consider upgrading to get `new_binary/1`, UUID v4/v7 generators, `wire_format:`, and perf improvements.

## Schema and types

- [ ] **Custom enums in groups** — Requires grid_codec v0.11.0+ for alias resolution in groups.
- [ ] **Typed groups** — Use `group :name, of: EntryModule` when repeated entries already have a reusable fixed-size codec struct.
- [ ] **Fixed-point on the wire** — Use `:i64` (or `:u64`) with `wire_format:` when state is integer-native; avoid `:positive_decimal` encoding when a scaled integer is sufficient.
- [ ] **UUID in groups** — Use `:uuid` (binary) unless you need string format internally; then use `:uuid_string`.
- [ ] **Lookups for keyed access** — Prefer codec `lookups do` helpers for reusable runtime access paths like `reservations_by_id`; keep them out of `.grid` because they are Elixir-side lookup metadata, not wire schema.

## Performance

- [ ] **Telemetry** — Enable on heavy codecs: `use GridCodec.Struct, telemetry: true, telemetry_min_duration: 10_000` (or set globally in config).
- [ ] **Large groups** — Use `GridCodec.Group.to_lists_parallel/2` for multi-group decode when payloads are large (e.g. 256KB+).
- [ ] **Carry-forward / rotation** — Drop unnecessary fields from carry-forward groups to reduce decode and GC cost.

## Observability

- [ ] **PromEx** — Use `GridCodec.Telemetry.Metrics.prom_ex_metrics/1` for PromEx/Prometheus. Do not `use PromEx.Plugin` inside grid_codec; use the metrics in the consumer app.

## Cross-repo review

To review a consumer that lives in another repo:

1. Clone the consumer (e.g. `gh repo clone Org/my_app /tmp/my_app -- --branch main --depth 1`).
2. Run this checklist against its GridCodec usage (deps, enums in groups, telemetry, `to_lists_parallel`, wire types, PromEx).
3. Optionally produce a short **local** spec (not committed) with numbered recommendations and before/after benchmark snippets from `example_app`.

Use the **cross-repo-review** skill in Cursor when analyzing that codebase from this project.

## See also

- [Getting started](getting-started.md) — First codec and encode/decode.
- [Schema evolution](schema-evolution.md) — Versioning and rollout (deploy consumers first when adding optional fields).
- [Performance](performance.md) — Profiling and optimization.
