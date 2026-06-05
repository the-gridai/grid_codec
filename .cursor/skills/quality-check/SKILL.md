---
name: quality-check
description: Run a comprehensive quality check across the entire GridCodec codebase — code, tests, docs, performance, and architecture. Use when asked to do a quality review, health check, audit, or general code quality assessment.
---

# Quality Check — Full Codebase Audit

Run these checks sequentially. Report findings after each phase before proceeding.

## Phase 1: Build & Static Analysis

### Library

```bash
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors
mix test
```

### Example app (consumer surface)

The example app exercises the public API as a real consumer would.
Compilation warnings here surface issues users will hit.

**Mirror `.github/workflows/ci.yml` `example-app-quality`:** this job is a
separate Mix project with its own formatter paths. Root `mix format` does **not**
guarantee `example_app/` is formatted; always run checks **inside**
`example_app/`.

```bash
cd example_app && mix deps.get
cd example_app && mix compile --warnings-as-errors
cd example_app && MIX_ENV=test mix compile --warnings-as-errors
cd example_app && mix format --check-formatted
cd example_app && mix credo --strict
cd example_app && mix test
```

### Dialyzer (optional, slow)

```bash
mix dialyzer
cd example_app && mix dialyzer --force-check
```

Use `--force-check` for the example app because `grid_codec` is a local path
dependency there; without a forced PLT check, Dialyzer can report stale
unknown-function/type warnings or miss generated-code regressions.

**Pass criteria:** Zero format issues, zero credo issues, zero compile warnings
in both projects, all tests green. If any fail, fix before proceeding.

## Phase 2: Test Coverage Audit

**Read the testing-strategy skill** for patterns and conventions.

Check:
- [ ] Every public module in `lib/grid_codec/` has a corresponding test file
- [ ] Every built-in type has a roundtrip test (check `struct_all_types_test.exs`)
- [ ] Custom composite types (PrefixedId, CharArray, Bitset) have dedicated tests
- [ ] Custom type meta introspection (`__prefixed_id_meta__/0`, `__char_array_meta__/0`, `__bitset_meta__/0`) tested
- [ ] Groups with custom types have property-based tests (check `auto_group_test.exs`)
- [ ] Typed group lookups have tests (check `lookup_test.exs` or equivalent)
- [ ] Batch strategies (padded_union, typed_frames) have roundtrip tests
- [ ] Match and Transcoder have correctness tests
- [ ] Validation has positive + negative tests per error code (check `validation_test.exs`)
- [ ] Telemetry has emission + disabled tests (check `telemetry_test.exs`)
- [ ] `new/1` has tests for valid, invalid, and edge cases (including OOR integers, unknown enum values, malformed UUIDs)
- [ ] Schema export affinity (`schema:` option on custom types) tested
- [ ] Breaking change rules have tests for all 27 WIRE and 9 SOURCE rules
- [ ] Breaking rule severity/policy changes have both rule-level tests and
  `mix grid_codec.breaking` task tests, so non-blocking warnings stay
  non-blocking by default and can still be escalated.
- [ ] Generated-code warning regressions have fixtures in `test/support` and
  `example_app/lib` that compile under `--warnings-as-errors`; when the issue is
  Dialyzer-specific, verify with `mix dialyzer` and
  `cd example_app && mix dialyzer --force-check`.

**Find gaps:**
```bash
# List all public modules without test coverage:
ls lib/grid_codec/types/*.ex | while read f; do
  mod=$(basename "$f" .ex)
  grep -rl "$mod" test/ > /dev/null || echo "MISSING: $f"
done
```

## Phase 3: Documentation Audit

**Read the documentation-quality skill** for standards.

Check:
- [ ] Every public module has `@moduledoc`
- [ ] CHANGELOG.md has entries for all shipped versions
- [ ] CHANGELOG dates match commit dates
- [ ] Version in `mix.exs` matches latest CHANGELOG entry
- [ ] Options documented in `GridCodec.Struct` moduledoc are complete (includes `schema:`, `grid_file:`, `types:`, `validate:`, `telemetry:`)
- [ ] AGENTS.md reflects current architecture and profiling workflow
- [ ] PrefixedId docs cover both generator and macro-only paths
- [ ] Custom type `schema:` option documented in PrefixedId, CharArray, and Bitset moduledocs

**Quick check for missing moduledocs:**
```elixir
# In iex:
for {mod, _} <- :code.all_loaded(),
    mod |> to_string() |> String.starts_with?("Elixir.GridCodec"),
    !Code.fetch_docs(mod) do
  mod
end
```

## Phase 4: Architecture Review

**Read the architecture-review skill** for review dimensions.

Check:
- [ ] No runtime function calls in type `encode_ast` (should all be inline)
- [ ] No IIFE patterns in any type module
- [ ] `__before_compile__` complexity is under credo threshold (50)
- [ ] Generated code has no intermediate allocations in the hot path
- [ ] Group batch encoder/decoder use direct local calls (not captures)
- [ ] Lookup generation produces efficient accessor code (no runtime `Enum.find`)
- [ ] `validate: true` generates code only when enabled (zero overhead when off)
- [ ] `telemetry: true` generates code only when enabled
- [ ] Custom type `schema:` option is compile-time only (zero runtime cost)
- [ ] Dependencies are minimal: runtime = `:decimal`, `:telemetry`, `:telemetry_metrics`; dev/test = `:stream_data`, `:credo`, `:dialyxir`, `:ex_doc`

## Phase 5: Schema Evolution

Check:
- [ ] `.grid` parser supports all field options (`wire_format`, `since`, `default`, `presence`, `value`, parameterized types)
- [ ] `.grid` parser supports custom type declaration blocks (`prefixed_id`, `char_array`, `bitset`)
- [ ] `.grid` formatter exports all field metadata from `__schema__/0`
- [ ] Breaking rules cover all wire-affecting changes (27 WIRE rules) and source-affecting changes (9 SOURCE rules)
- [ ] `generate_from_struct_def` passes all field options through when loading `.grid` via `grid_file:`
- [ ] All generated `.grid` files start with `@syntax N` directive
- [ ] Individual struct files import their enum and custom type dependencies (self-contained)
- [ ] Cross-schema references generate correct relative import paths (enums and custom types)
- [ ] Custom type `schema:` affinity overrides the "lowest referencing schema" heuristic in export
- [ ] Example app `.grid` baselines are up to date: `cd example_app && mix grid_codec.export --check`
- [ ] Example app covers: multi-enum structs (TradeSettled), cross-schema enum refs (TaggedMetric), PrefixedId types
- [ ] Breaking change detection returns clean: `cd example_app && mix grid_codec.breaking`
- [ ] Parser round-trips: parse `.grid` -> format -> re-parse produces equivalent schema

## Phase 6: Performance Baseline

**Read the performance-optimization skill** for profiling workflow.

Run the benchmark suite and record baselines:
```bash
cd example_app && mix run benchmarks/quick_bench.exs
cd example_app && mix run benchmarks/group_bench.exs
cd example_app && mix run benchmarks/lookup_bench.exs
```

Check:
- [ ] Encode throughput matches expected range (see AGENTS.md)
- [ ] Decode throughput matches expected range
- [ ] No regression from previous known baselines
- [ ] Lookup benchmarks show generated accessors outperform manual pipelines

## Phase 7: Cross-Repo Compatibility

**Read the cross-repo-review skill** if consumer codebases are available.

Check:
- [ ] Consumer apps compile cleanly against current grid_codec main
- [ ] No breaking API changes in unreleased CHANGELOG section
- [ ] Custom types in groups work (alias expansion)
- [ ] Telemetry events fire correctly in consumer context

## Reporting

After all phases, produce a summary:

```markdown
## Quality Check Summary — GridCodec vX.Y.Z

### Phase 1: Build
- Format: PASS/FAIL
- Credo: PASS/FAIL (N issues)
- Library compile (--warnings-as-errors): PASS/FAIL
- Example app compile (--warnings-as-errors): PASS/FAIL
- Library tests: PASS/FAIL (N tests, N failures)
- Example app tests: PASS/FAIL

### Phase 2: Tests
- Coverage gaps: [list or "none"]
- Missing property tests: [list or "none"]

### Phase 3: Documentation
- Missing moduledocs: [list or "none"]
- Changelog up to date: YES/NO
- Version mismatch: YES/NO

### Phase 4: Architecture
- Inline violations: [list or "none"]
- Complexity warnings: [list or "none"]
- Dependency issues: [list or "none"]

### Phase 5: Schema Evolution
- .grid feature parity: PASS/FAIL
- @syntax directive: present in all generated files / missing
- Self-contained files: struct files import enum + custom type deps / missing imports
- Cross-schema imports: correct paths / broken
- Custom type schema affinity: working / broken
- Breaking rules coverage: 27 WIRE + 9 SOURCE rules
- Example app baselines: up to date / stale

### Phase 6: Performance
- Encode baseline: X ns/op (simple), Y ms (groups)
- Decode baseline: X ns/op (simple), Y ms (groups)
- Lookup baseline: X ms (keyed map), Y ms (filtered list)
- Regressions: [list or "none"]

### Recommendations
1. [Prioritized action items]
```
