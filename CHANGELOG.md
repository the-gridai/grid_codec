# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.44.0] - 2026-06-05

### Changed

- Open-sourced under the MIT license at [the-gridai/grid_codec](https://github.com/the-gridai/grid_codec). Historical issue links in this file still point at the pre-OSS private repository.

## [0.43.0] - 2026-05-13

### Changed

- **Dependency upgrade: `decimal ~> 3.1`** — bumped the `:decimal` requirement
  from `~> 2.0` to `~> 3.1`. Consumers pinning Decimal at `< 3.0` must upgrade.
  Decimal 3.x normalizes the `sign` field to integers (`1` / `-1`) instead of
  atoms; any consumer code that pattern-matches on `:decimal` internals should
  be reviewed. Refreshed transitive lockfile entries for `credo`, `ex_doc`,
  `jason`, `makeup_erlang`, `stream_data`, and `telemetry`.
- **Example app deps refreshed for Decimal 3.x** — `example_app` now pins
  `ecto 3.13.6`, `ecto_sql 3.13.5`, `postgrex 0.22.2`, `jason 1.4.5`,
  `db_connection 2.10.1`, and `telemetry 1.4.2`, the minimum versions that
  accept `decimal ~> 3.0`.
- **Credo `max_nesting` bumped from 4 → 5** — Credo 1.7.18 detects deeper
  nesting in the existing `Breaking.Checker.resolve_schema_imports/4` and
  `Struct.Compiler.__before_compile__/1` macros. The codec compiler already
  documents the need for deep AST nesting; the limit was raised to keep that
  intent unchanged without spurious refactor pressure.

## [0.42.0] - 2026-05-02

### Added

- **Struct lifecycle hooks for runtime/wire normalization** — generated codecs
  now honor optional `before_encode/2` and `after_decode/2` callbacks. Hooks can
  normalize runtime structs into persisted wire state before validation/encoding
  and rebuild derived runtime fields after decode with header metadata when
  available. Hook failures may return `{:error, reason}`. Closes
  [#20](https://github.com/Spectral-Finance/grid_codec/issues/20).

## [0.41.6] - 2026-04-28

### Fixed

- **Required-field helper nil checks avoid per-clause unreachability warnings** —
  generated codecs now use a single helper clause with an opaque runtime nil
  check for required fields without `:default`, avoiding Elixir 1.18
  `--warnings-as-errors` failures for domain string wrapper fields while
  preserving `{:error, {:required_field_absent, field}}`. Extended root and
  `example_app` fixtures to cover consumer-style `:string16` wrapper modules.
  Closes [#19](https://github.com/Spectral-Finance/grid_codec/issues/19).

## [0.41.5] - 2026-04-28

### Fixed

- **Required-field helper codegen emits only used arities** — codecs with
  required fields exclusively with or without `:default` no longer emit unused
  private helper clauses that fail `mix compile --warnings-as-errors`. Added
  root and `example_app` fixtures for no-default, default-only, and mixed
  required fields so this generated-code shape is covered. Closes
  [#19](https://github.com/Spectral-Finance/grid_codec/issues/19).

## [0.41.4] - 2026-04-28

### Changed

- **`WIRE_VAR_FIELD_ADDED` is informational by default** — now that GridCodec
  0.41.3 decoders synthesize missing optional/defaulted var-data for historical
  payloads, appended variable-length fields no longer block
  `mix grid_codec.breaking` under the default `fail_on: [:error]` policy.
  Projects that want to forbid var-data appends can still set
  `severity_overrides: %{WIRE_VAR_FIELD_ADDED: :error}`. Closes
  [#17](https://github.com/Spectral-Finance/grid_codec/issues/17).

### Fixed

- **Required-field decode no longer emits inline unreachable nil clauses** —
  generated decoders now route `presence: :required` nil enforcement through a
  runtime helper, preserving `{:error, {:required_field_absent, field}}` and
  `:default` behavior without triggering Dialyzer `pattern_match_cov` warnings
  for codecs that use required `:string*`, `:uuid`, or `:uuid_string` fields.
  Added root and `example_app` regression codecs so strict compile and Dialyzer
  paths keep covering this generated-code shape. Closes
  [#18](https://github.com/Spectral-Finance/grid_codec/issues/18).

## [0.41.3] - 2026-04-28

### Fixed

- **Runtime compatibility for appended optional fields** — decoders now
  synthesize missing trailing field values when reading historical payloads
  that predate an append. Short fixed blocks are padded from the codec's
  null-sentinel block, even when the codec author forgot to bump `version:`,
  and missing `:string8` / `:string16` / `:string32` length prefixes decode as
  `nil`. Required fields with `:default` still substitute the default; required
  fields without `:default` still return
  `{:error, {:required_field_absent, field}}`. Closes
  [#16](https://github.com/Spectral-Finance/grid_codec/issues/16).

## [0.41.2] - 2026-04-28

### Fixed

- **`WIRE_VAR_FIELD_ADDED` breaking-check rule** — `mix grid_codec.breaking`
  now flags newly added variable-length fields such as optional `:string16`.
  Historical payloads do not contain the new field's length prefix or payload
  bytes, so current decoders can fail while reading old events. The schema
  evolution guide now treats var-data appends as breaking until runtime
  mitigation exists. Closes
  [#15](https://github.com/Spectral-Finance/grid_codec/issues/15).

## [0.41.1] - 2026-04-24

### Fixed

- **Required `CharArray` under `mix compile --warnings-as-errors`:** `CharArray`
  `decode_value_ast/1` never yields Elixir `nil`, so the generic `:required`
  nil-guard from 0.41.0 produced an unreachable `nil` clause and failed strict
  compilation (reported downstream on the 0.41 bump). The compiler now omits
  that guard when a type opts in via the optional `GridCodec.Type` callback
  `required_field_decode_never_nil?/0` (implemented for `CharArray`). The guard
  is **never** skipped for `wire_format:` fields, where `decode_as_ast/2` may
  still return `nil`. Closes
  [#14](https://github.com/Spectral-Finance/grid_codec/issues/14).

### Added

- **`required_field_decode_never_nil?/0` callback** — optional behaviour callback
  documented in `GridCodec.Type`. A `test/support` fixture codec
  (`GridCodec.TestSupport.RequiredCharArrayFixture`) is compiled in `MIX_ENV=test`
  so CI’s `mix compile --warnings-as-errors` step covers this path.

## [0.41.0] - 2026-04-24

### Changed

- **Decode-time enforcement of `presence: :required`** (typespec preservation).
  The decoder now refuses to surface `nil` for a `:required` field: when a
  historical (shorter) payload is padded from the type's null sentinel or a
  current payload carries a sentinel-equivalent value in a required slot,
  `decode/2` returns `{:error, {:required_field_absent, field}}` instead of
  silently producing a struct whose required field is `nil` — which would have
  violated the declared `@type t :: %__MODULE__{required_field: non_nil}` and
  been rejected by a subsequent `encode/1` anyway. This applies uniformly to
  every built-in type (integers, floats, decimals, uuid, char_array, bitset,
  enum, prefixed_id) and to any custom type whose `decode_value_ast/1` maps
  its null sentinel to `nil`. Custom types that do not map to `nil` are
  unaffected (the nil branch is dead code by construction). The fix is the
  default; there is no flag to disable it because the previous behavior
  violated the public type contract.

### Added

- **`:default` on `:required` fields is now a decode-time fallback too.**
  Previously `:default` was encode-only: it filled in missing struct fields
  at encode time but did not participate in decode. It now serves double duty:
  when a `:required` field's wire value would otherwise decode as `nil` (e.g.
  historical padding or a sentinel-valued slot), the decoder substitutes the
  declared `:default` and the struct round-trips cleanly through `encode/1`.
  This is the recommended way to safely append a new `:required` field to an
  existing schema — declare a sensible default and old events decode to that
  value with no consumer changes required.

- **`WIRE_FIELD_ADDED_REQUIRED` breaking-check rule** — `mix grid_codec.breaking`
  flags appended fixed-block fields with `presence: :required` when no
  `:default` is declared. With the new decode-time enforcement, such appends
  cause every historical event to decode to
  `{:error, {:required_field_absent, field}}`; the rule catches this at CI
  time before the schema ships. Declaring a `:default` suppresses the rule
  (and makes the append genuinely safe). `presence: :optional`, `:constant`
  value fields, variable-length fields, and added-but-unchanged schemas do
  not trigger. Resolves
  [#12](https://github.com/Spectral-Finance/grid_codec/issues/12). See
  `docs/schema-evolution.md` ("Safely appending a required field").

- **Regression and evolution test coverage** — shared codecs in
  `test/support/z_schema_evolution_fixtures.ex`; deterministic tests for
  `padded_union` batches, scalar `group … of:` lists, lazy `Group.stream/1`
  required-field propagation, and payload-only (`header: false`) decode
  boundaries; generative cross-version checks in
  `test/grid_codec/schema_evolution_generative_test.exs`; required-field
  contract property in `test/grid_codec/required_fields_invariant_test.exs`;
  decode contract tests in `test/grid_codec/required_decode_test.exs`; example
  app migration smoke in
  `example_app/test/example_app/schema_evolution_migration_test.exs`.
  `docs/schema-evolution.md` documents the new tests and payload-only
  evolution limits.

## [0.40.1] - 2026-04-03

### Fixed

- **Example App Quality CI** — `example_app/test/example_app/codec_doctest_test.exs`
  formatted with `cd example_app && mix format` so CI’s in-app
  `mix format --check-formatted` matches (root `mix format` does not cover the
  example app tree).

## [0.40.0] - 2026-04-03

### Added
- **Doctest-ready generated codec docs** — `use GridCodec.Struct` modules get runnable
  `iex>` examples in `@doc` for `new/1`, `new_binary/1`, `encode/2`, `decode/2`, and
  `validate_struct/1` when the layout is supported and deterministic literals can be
  synthesized. Host apps can run `doctest/1` over discovered codec modules so
  generated code is exercised under `mix test` and contributes to coverage.
- **`doc_examples` option** — set `doc_examples: false` on `use GridCodec.Struct` to
  keep prose-only docs for shapes where auto-examples are unsafe or unwanted.
- **Doc example synthesis** (`lib/grid_codec/doc_example_values.ex`, not a public API
  surface) — compile-time attribute fragments for generated `iex>` lines; types may
  implement optional `doc_example_source/0`.
- **Library meta-tests** — `test/grid_codec/codec_doctest_test.exs` runs doctests over
  representative test-support codecs and asserts `Code.fetch_docs/1` contains
  `iex>` so empty-example regressions do not slip through.
- **Example app smoke** — `example_app/test/example_app/codec_doctest_test.exs` mirrors
  the consumer pattern (allowlist + discovery sync test + `iex>` guard).

### Documentation
- **README, AGENTS.md, testing-strategy skill** — document the doctest harness pattern,
  structural `iex>` guard, and `doc_examples` opt-out.

## [0.39.0] - 2026-04-03

### Changed
- **`.grid` export requires explicit schema namespace** — `mix grid_codec.export`
  now emits only codecs compiled with `schema_id:` or `schema:` on
  `use GridCodec.Struct`. Codecs that omit both still default to `schema_id: 0` on
  the wire but are skipped in export, so utility-only codecs are not grouped
  under `schema_0/`. Introspection adds `grid_schema_export: boolean` to
  `__schema__/0`. To keep a codec in exported trees, set `schema_id:` or
  `schema:` (including `schema_id: 0` if you rely on the zero namespace). See
  [#11](https://github.com/Spectral-Finance/grid_codec/issues/11).

### Fixed
- **`mix grid_codec.export` control flow** — when no struct modules exist or none
  are eligible for export, the task no longer continues into grouping after
  printing the informational message.

### Tests
- **Export guard** — regression coverage that implicit-schema codecs do not create
  a `schema_0/` output directory.

## [0.38.0] - 2026-03-18

### Added
- **Declaration-local schema docs** — `field`, `group`, and enum `value`
  declarations now accept `doc:` metadata that flows through generated ExDoc,
  `__schema__/0`, `.grid` export, `.grid` parsing, and `.grid` reload paths.
- **Documentation-aware breaking checks** — `mix grid_codec.breaking` now emits
  `:docs` issues for field, group, group-field, and enum-value doc drift, with
  per-rule severity policy support via `include_docs`, `fail_on`, and
  `severity_overrides` config.

### Changed
- **Example app schema coverage** — `example_app` event, view, typed-group, and
  enum examples now use `doc:` metadata so exported `.grid` files and generated
  docs exercise the new declaration-local documentation flow end to end.
- **Breaking task output policy** — `mix grid_codec.breaking` now reports issue
  severity/category in terminal output and treats documentation drift as
  non-blocking by default unless the configured policy escalates it.

### Fixed
- **Decoded validation sequencing** — `validate_struct/1` and other decoded
  validation paths now stop after type-validation failures instead of continuing
  into invariant callbacks, so function validators only run on type-safe
  structs and no longer need defensive field-type guards.
- **Nested-app schema detection in breaking checks** — the breaking task now
  detects master `.grid` files by actual schema-block syntax instead of a naive
  string search, avoiding false positives when standalone schema files contain
  the word `schema` inside documentation text.

### Tests
- **Decoded validation short-circuit coverage** — added regression coverage for
  function validators after type-validation failures, ensuring malformed
  manually-constructed structs return the type error without running invariant
  callbacks.

### Documentation
- **Schema docs release guidance** — updated `README.md` and `AGENTS.md` to show
  `doc:` metadata in DSL examples and document docs-aware breaking policy knobs
  (`include_docs`, `fail_on`, `severity_overrides`).

## [0.37.2] - 2026-03-18

### Fixed
- **Required-field validator nil inference** — built-in validators like
  `compare/3` and `one_of/2` now infer `allow_nil?: false` when every
  referenced field is declared `presence: :required`, aligning generated
  validation code and reflected metadata with the existing non-`nil` field
  contract while still honoring explicit `allow_nil?` overrides.

### Tests
- **Compile-warning guardrails** — virtual-field compile-time failure tests now
  capture and assert the exact expected duplicate-key warning, so unexpected
  extra compiler warnings fail the test instead of being silently swallowed.

## [0.37.1] - 2026-03-18

### Fixed
- **Breaking change presence labels** — breaking change reports now render
  omitted field presence as `optional` instead of `nil`, so CI output reflects
  the effective field contract when presence is not explicitly declared.

## [0.37.0] - 2026-03-18

### Added
- **Transcoder validation modes** — `GridCodec.Transcoder` now supports
  `validate: false | :source | :target | :both` (plus `true` as `:both`) so
  binary-first transcoding can opt into source-side binary validation,
  validated target encoding via `new_binary/1`, or both without forcing an
  intermediate source struct decode.

### Changed
- **Native validation/invariant coverage** — string, char array, and bitset
  native types now participate in the generated validation pipeline, and
  timestamp/date-time compare-based invariants now use explicit type-aware
  comparisons instead of relying on generic term ordering.

### Documentation
- **Transcoder validation guidance** — updated `GridCodec.Transcoder`,
  `README.md`, and `docs/binary-filtering.md` with the new validation modes,
  target `new_binary/1` fast path, and the boundary between binary-capable and
  decoded-only source validators.

## [0.36.0] - 2026-03-18

### Added
- **`field_defaults` option** — `use GridCodec.Struct, field_defaults: [presence: :required]`
  applies default options to every `field` declaration in the codec. Explicit per-field
  options take precedence. Reduces boilerplate in structs where most fields share the
  same options.

### Changed
- **Breaking change CI job is now informational** — the `breaking` CI job uses
  `continue-on-error: true` so example app schema changes no longer block PR merges.
  Breaking changes are still reported for visibility.
- **Example app `TradeExecuted`** now uses `field_defaults: [presence: :required]`
  as a showcase for the new option.

## [0.35.0] - 2026-03-17

### Added
- **Validation pipelines** — `GridCodec.Struct` now supports accumulating,
  non-raising `validations do` / `invariants do` checks on decoded structs,
  plus `validate_struct/1`, `validate_binary/1`, decode-time `validate:`
  modes, and runtime validation metadata.
- **Refined type helper** — added `GridCodec.Type.Refined` so field-local rules
  like non-negative numbers or constrained time/domain wrappers can live in the
  type system and survive `new/1 -> encode/1 -> decode/1` roundtrips cleanly.
- **Validation pipeline benchmark coverage** — added
  `example_app/benchmarks/validation_bench.exs` plus the `mix bench.validation`
  alias to compare generated `validate_struct/1` / `validate_binary/1`
  against hand-rolled struct checks, hand-rolled binary pattern matches, and
  generic map-validator pipelines built from anonymous functions.

### Changed
- **Example app validation usage** — `ExampleApp.Views.Reservation` now uses a
  real struct validation, so the consumer surface exercises the new API outside
  library-only tests and benchmarks.

### Performance
- **Validation pipeline baseline numbers** — recorded an Apple M3 Max / OTP 28.3
  reference run for the new validation benchmark. After specializing the
  generated hot path to use compile-time-bound field locals and direct binary
  getter ASTs, `validate_struct/1` now runs at `14.08 M ips` (`71.02 ns`) on
  the happy path, beating the generic map-validator pipeline
  (`13.04 M ips`, `76.69 ns`) while remaining behind hand-rolled struct
  validation (`24.56 M ips`, `40.72 ns`). `validate_binary/1` improved to
  `8.97 M ips` (`111.44 ns`), which is now close to the decode-plus-manual
  path (`9.58 M ips`, `104.37 ns`) but still behind a fully hand-written
  binary pattern match (`23.11 M ips`, `43.27 ns`).

### Documentation
- **Validation benchmark guidance** — updated `README.md`,
  `docs/validations.md`, `docs/performance.md`, and `example_app/README.md`
  with the new validation benchmark command, coverage, and performance
  positioning for generated validators vs hand-rolled code.
- **Validation pipeline guide** — added ExDoc coverage and architecture/runtime
  boundary docs for `GridCodec.Validations`, `GridCodec.ValidationErrors`,
  `GridCodec.Type.Refined`, and the fact that validations remain runtime-only
  metadata outside the `.grid` schema format.

## [0.34.0] - 2026-03-17

### Added
- **Prunable `.grid` export cleanup** — `mix grid_codec.export --prune` now removes
  orphaned generated `.grid` files left behind after codec deletions or renames,
  so checked-in schema directories can be regenerated back to a clean baseline.

### Changed
- **Strict `.grid` export verification** — `mix grid_codec.export --check` now
  fails when generated schema files are unexpectedly present as well as when they
  are stale or missing, closing the gap where deleted codecs could leave behind
  silently accepted orphaned files.

### Tests
- **Deterministic export regression coverage** — schema formatter and export task
  tests now assert byte-identical output across repeated runs and across shuffled
  codec input order, locking down `.grid` generation stability.

### Documentation
- **Export vs breaking checks guidance** — `README.md`, `docs/schema-evolution.md`,
  and `AGENTS.md` now explain the difference between artifact drift
  (`mix grid_codec.export --check`) and schema compatibility
  (`mix grid_codec.breaking`), including when to use `--prune`.

## [0.33.3] - 2026-03-16

### Changed
- **Example app quality gate** — CI now compiles `example_app` in both `dev` and
  `test` environments with `--warnings-as-errors` and runs `example_app` tests,
  so consumer-side generated-code warnings are caught on the same boundary that
  downstream apps hit.
- **Example app consumer fixtures** — added `CharArray` wrapper modules and
  coverage in `example_app` so consumer-style fixed-width wrapper usage is
  exercised continuously as part of the consumer surface.

### Fixed
- **PrefixedId test-env compile warning** — generated `PrefixedId` wrapper
  modules no longer depend on `GridCodec.Generators.uuid/0` during consumer test
  compilation, avoiding `mix test --warnings-as-errors` failures in downstream
  apps with StreamData available.

## [0.33.2] - 2026-03-16

### Fixed
- **CharArray consumer-wrapper Dialyzer noise** — `GridCodec.Types.CharArray`
  now specializes the public `encode/1` overflow path at macro expansion time
  as well as `encode_ast/4`, avoiding constant-branch code in consumer wrapper
  modules that can trigger false positive Dialyzer warnings.

## [0.33.1] - 2026-03-16

### Added
- **Coverage and test-audit gate** — `mix check` now runs `mix grid_codec.test_audit`
  plus `mix test --cover`, turning the existing coverage threshold into an enforced
  quality gate and failing fast when a new public `GridCodec.*` module ships
  without any matching `*_test.exs` reference.
- **Example app Dialyzer gate** — `example_app` now includes `:dialyxir`, a local
  `mix check` Dialyzer step, and a dedicated GitHub Actions Dialyzer job with its
  own PLT cache so consumer-facing examples stay type-check clean.

### Changed
- **CI test job** — now audits public module test references before running the
  library test suite with coverage enabled, keeping test coverage checks aligned
  between local development and GitHub Actions.

### Fixed
- **Nested-app breaking checks** — `mix grid_codec.breaking` now resolves baseline
  schema paths relative to the Git repository root and exits non-zero on git
  lookup failures instead of printing errors and reporting a false clean result.
- **`datetime_ns` coercion precision safety** — sub-microsecond integer nanosecond
  inputs are now rejected by `new/1` and `encode/1` instead of being silently
  truncated through `%DateTime{}` coercion.
- **Bitset coercion error handling** — unknown string or atom flags now return a
  structured cast error from `new/1` instead of raising via
  `String.to_existing_atom/1`.
- **Inline-group `.grid` custom type names** — schema export now applies the same
  short-name resolution to inline group fields as top-level fields, preventing
  fully qualified Elixir module names from leaking into generated `.grid` files.
- **Lookup codegen Dialyzer compatibility** — typed-group and batch lookups no
  longer emit constant-boolean branches for empty or simple filters, eliminating
  false positive unreachable-branch warnings in normal consumer lookup modules.
- **Registry regeneration warning noise** — the `:grid_codec` Mix compiler now
  suppresses intentional module-redefinition warnings while replacing the
  fallback `GridCodec.Registry` with the generated consolidated registry, so
  consumer apps no longer see spurious warnings during normal compilation.

### Tests
- **Native type roundtrip fuzzing** — expanded property-based coverage for
  datetime coercion equivalence, `datetime_ns` precision rejection, bitset atom
  vs string normalization, and char array truncation determinism.

### Documentation
- **PrefixedId generator extension pattern** — `README.md`,
  `example_app/README.md`, and `mix grid_codec.gen.prefixed_id` now show the
  supported way to add deterministic `UUID.generate_v5/2` constructors to
  generated PrefixedId modules without giving up the visible-source workflow.

## [0.33.0] - 2026-03-16

### Added
- **Virtual fields** — `virtual :name, default: value` declares struct fields excluded
  from the wire format. Useful for transient metadata, caches, or derived state.
  Supports `validate: true` (default) to include in `new/1` coercion, or
  `validate: false` to skip validation entirely.
- **Framed groups** — `group :items, of: Module, framing: :length_prefixed` enables
  groups of structs with variable-length fields. Wire format:
  `numEntries (u32 LE) | [payload_len (u16 LE) | payload]*`. Eagerly decodes to a
  plain list. Works with `lookups` for map-keyed access.
- **Scalar groups** — `group :tag_ids, of: :uuid` supports homogeneous lists of
  scalar values (UUIDs, integers, strings) using the same `of:` keyword as typed
  groups. Fixed-size types use the standard group wire format; variable-length types
  (strings) auto-select framed encoding. Eagerly decodes to a plain list.
- **`.grid` schema support for scalar groups** — scalar group fields are now
  exported and parsed in `.grid` schema files.
- **Example app quality gate** — `example_app` now has its own `.credo.exs` with
  strict checks, a `credo` dependency, and a `mix check` alias that runs
  `compile --warnings-as-errors`, `format --check-formatted`, and `credo --strict`.
- **CI: example-app-quality job** — new GitHub Actions job runs compile, format,
  and credo checks on `example_app/` in every push and PR, catching consumer-facing
  issues like missing aliases in generated code.
- **README: `import_deps` documentation** — installation section now documents the
  `.formatter.exs` setup so DSL macros format correctly out of the box.
- **Version consistency test** — `VersionConsistencyTest` verifies the README
  installation tag and CHANGELOG entries stay in sync with `mix.exs` version.

### Fixed
- **PrefixedId generator aliases** — `mix grid_codec.gen.prefixed_id` now generates
  `alias GridCodec.Types.{PrefixedId, UUID, UUIDString}` and uses short-form calls,
  preventing Credo `AliasUsage` warnings in consumer projects.
- **Formatter export completeness** — `.formatter.exs` export block now includes
  `batch`, `lookups`, and `virtual` macros alongside `field`, `group`, and `defcodec`.
  Consumers with `import_deps: [:grid_codec]` get correct formatting for all DSL
  macros without manual `locals_without_parens` configuration.

### Changed
- **Strict Credo configuration** — enabled `AliasUsage` (4+ segments),
  `AliasOrder`, `MultiAlias` (bans grouped `alias Foo.{Bar, Baz}` syntax),
  `MapJoin`, `FilterFilter`, `LazyLogging`, and `MixEnv` checks. All grouped aliases
  expanded to individual lines across `lib/`, `test/`, and `example_app/`.
- **Registry filter optimization** — combined chained `Enum.filter` calls into a
  single predicate in `GridCodec.Registry`.
- **Enum type error message** — replaced `Enum.map |> Enum.join` with
  `Enum.map_join` in `GridCodec.Types.Enum`.

## [0.32.0] - 2026-03-13

### Added
- **Custom type `schema:` affinity** — PrefixedId, CharArray, and Bitset macros
  accept a `schema:` option that controls placement of `.grid` files during export,
  overriding the default "lowest referencing schema" heuristic. The generator
  (`mix grid_codec.gen.prefixed_id --schema NAME`) emits the option automatically.
- **Required field validation in `new/1`** — fields with `presence: :required` are
  now validated in `new/1` and `update/2`, returning
  `{:error, %ValidationError{code: :required_field}}` when nil. Previously only
  `encode/1` caught nil required fields.

### Fixed
- **Consolidated Registry type checker compatibility** — the generated
  `GridCodec.Registry.encode/2` clauses now use map patterns
  (`%{__struct__: Module}`) instead of struct patterns (`%Module{}`) to avoid
  Elixir 1.19 type checker crashes during partial recompilation of consumer apps.

## [0.31.0] - 2026-03-13

### Added
- **`mix grid_codec.gen.prefixed_id` generator** — creates PrefixedId type modules
  as full `.ex` source files with visible functions, `@doc`/`@spec`, doctests, and
  a companion test file. Generated files include a version-stamped header comment.
- **PrefixedId slim mode** — the `use GridCodec.Types.PrefixedId` macro now detects
  user-defined helper functions (e.g. from the generator) and skips injecting
  duplicates via `@before_compile`, enabling a visible-source workflow without
  breaking existing macro-only usage.
- **PrefixedId `@moduledoc` merging** — the macro appends a standard "Prefixed ID"
  documentation section to any user-provided `@moduledoc`, or provides a default
  when none is set.
- **Example app PrefixedId types** — added `ExampleApp.Types.OrderId` (`ord-`, tag 1)
  and `ExampleApp.Types.UserId` (`user-`, tag 2) as generated-source examples with
  passing doctests.

### Fixed
- **Example app typespec test** — `encode_payload/1` now correctly pattern-matches
  the `{:ok, binary}` return value from `encode/2`.

### Changed
- **Compiler cleanup** — removed unused WIP "from blocks" private functions that
  caused `--warnings-as-errors` failures.

### Documentation
- **README.md** — updated PrefixedId section to recommend the generator workflow.
- **AGENTS.md** — updated PrefixedId section with both generator and macro-only paths.

## [0.30.0] - 2026-03-12

### Added
- **Typed groups and lookups DSL** — `group :name, of: Module` now reuses fixed-size
  child codecs as homogeneous group entries, and `lookups do` generates named runtime
  accessors over `group` and `batch` fields with compile-time validation,
  last-write-wins keyed map semantics, and codec-level introspection via `__lookups__/0`.

### Documentation
- **Typed groups and lookups guide** — added end-to-end usage guidance across
  `README.md`, `GridCodec.Struct`, `docs/getting-started.md`,
  `docs/consumer-integration.md`, and the new `docs/lookups.md` guide, including
  the boundary between Elixir-side lookups and `.grid` schema export.

### Performance
- **Lookup benchmark coverage** — added `example_app/benchmarks/lookup_bench.exs` to compare
  generated lookups against equivalent manual `GridCodec.Group.to_list |> Map.new` /
  `Enum.filter` pipelines in realistic typed-group and batch scenarios.
- **Generated keyed group lookups benchmarked** — on the Apple M3 Max reference run used
  during implementation, a generated typed-group keyed map lookup ran in `5.69 ms`
  and `6.94 MB` versus `6.21 ms` and `8.49 MB` for the equivalent manual
  `GridCodec.Group.to_list(...) |> Map.new(...)` pipeline, and the generated
  filtered list lookup ran in `3.47 ms` / `6.19 MB` versus `4.67 ms` / `7.81 MB`
  for `to_list |> Enum.filter`.

## [0.29.3] - 2026-03-11

### Fixed
- **CharArray `on_overflow: :error` warnings** — `GridCodec.Types.CharArray` now
  emits specialized overflow handling without impossible-branch compile warnings,
  while preserving strict error behavior for oversized strings.

## [0.29.2] - 2026-03-11

### Fixed
- **ExDoc changelog references** — corrected stale API references in `CHANGELOG.md`
  so `mix docs` builds cleanly without unresolved function warnings.

### Documentation
- **Schema evolution guidance** — documented the recommended compatibility model:
  keep `{schema_id, template_id}` stable for an existing wire message, bump
  `version`, use `since` for additive fields, and treat field removal/type
  changes as breaking migrations.
- **Breaking rule reference** — added rule inventories and practical guidance for
  `mix grid_codec.breaking` in `docs/schema-evolution.md`,
  `GridCodec.Breaking.Rules.Wire`, and `GridCodec.Breaking.Rules.Source`.
- **Identity and collision semantics** — clarified module identity, type-name
  lookup, duplicate handling, and the difference between consolidated and
  fallback registry behavior in `README.md`, `GridCodec.Struct`, and
  `GridCodec.Registry`.

## [0.29.1] - 2026-03-11

### Fixed
- **`%__MODULE__{}` in function heads** — `defstruct` is now emitted immediately after
  field definitions are accumulated (via `compute_struct_fields/3`) instead of being
  deferred to `@before_compile`. This allows modules using `defcodec` or `grid_file:`
  to pattern-match on `%__MODULE__{}` in function heads defined after the codec block.
  All compile-time code generation (encoder/decoder AST, typespecs, macros) is unchanged.

## [0.29.0] - 2026-03-10

### Added
- **Custom type declaration blocks in `.grid` files** — `prefixed_id`, `char_array`, and
  `bitset` types can now be fully declared in `.grid` schemas, preserving configuration
  (prefix, tag, length, flags) for documentation, breaking change detection, and `grid_file:` compilation.
- **6 new breaking change rules** — `WIRE_PREFIXED_ID_TAG_CHANGED`, `WIRE_CHAR_ARRAY_LENGTH_CHANGED`,
  `WIRE_BITSET_UNDERLYING_CHANGED`, `WIRE_BITSET_FLAG_REMOVED`, `WIRE_BITSET_FLAG_VALUE_CHANGED`,
  `SOURCE_PREFIXED_ID_PREFIX_CHANGED` detect changes to custom type declarations.
- **`__char_array_meta__/0` and `__bitset_meta__/0`** introspection functions on custom type modules,
  matching the existing `__prefixed_id_meta__/0` pattern.
- **`GridCodec.Registry.lookup_custom_type_by_name/1`** for auto-resolving custom
  types from `.grid` files.
- **`Formatter.detect_custom_types/1` and `detect_all_custom_types/1`** for discovering custom
  type modules referenced by codec fields.
- **`WireSizes.resolve/2`** extended for `prefixed_id` (17 bytes), `char_array` (length),
  and `bitset` (underlying type size) TypeDef kinds.

### Changed
- **`CompositeType` replaced by `TypeDef`** — The parser's internal struct now uses a `kind`
  discriminator (`:composite`, `:prefixed_id`, `:char_array`, `:bitset`) for unified custom
  type representation. Existing `.grid` `type` blocks continue to work as `kind: :composite`.
- **Export task generates custom type `.grid` files** alongside enum files, with proper
  import directives in struct files that reference them.

## [0.28.0] - 2026-03-10

### Added
- **`schema:` named option** — Modules can now reference schemas by name instead of
  numeric ID: `use GridCodec.Struct, schema: "events"`. The name is resolved
  at compile time from the host app's `:grid_codec` config (`schemas: %{1 => "events"}`).
  Mutually exclusive with `schema_id:`. Unknown names and type errors raise at compile time.
  Zero runtime cost — the resolved integer is inlined into the generated code.

## [0.27.1] - 2026-03-10

### Fixed
- **String/timestamp/decimal generators registered** — `Generators.for_type/1` now works
  for `:string8`, `:string16`, `:string32`, `:timestamp_us`, `:timestamp_ns`,
  `:datetime_us`, `:datetime_ns`, `:decimal`, `:positive_decimal`, and `:uuid_string`
  without relying on type module compile order.
- **`.grid` formatter handles PrefixedId types** — `Schema.Formatter` now detects
  modules with `__prefixed_id_meta__/0` and emits their short name instead of the
  full `Elixir.MyApp.Types.UserId` module path.

### Performance
- **UUID hot-path inlining** — `format_uuid/1`, `parse_uuid_string!/1`, and
  `parse_uuid_nodash!/1` are now `@compile {:inline}` in `UUIDString`, reducing
  call overhead for UUID, UUIDString, and PrefixedId encode/decode.

### Documentation
- **PrefixedId in AGENTS.md** — Key Modules and Type System sections updated.
- **PrefixedId in README.md** — "Custom Prefixed IDs" section with usage example.
- **ExDoc Types group** — `GridCodec.Types.PrefixedId` added to sidebar.
- **PrefixedId test coverage** — Added to `struct_all_types_test.exs` (roundtrip,
  nil, coercion) and `generators_test.exs` (generator validity, for_codec roundtrip).

## [0.27.0] - 2026-03-10

### Added
- **`PrefixedId` composite type** — new parameterized type for self-describing entity
  identifiers on the wire (17 bytes: u8 tag + 16-byte UUID). Define types with
  `use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01`. Includes full coercion
  (auto-prefixes plain UUIDs), O(1) getter, DB-level tag byte queries, SQL generation,
  and helpers (`generate/0`, `from_uuid/1`, `to_uuid/1`, `valid?/1`).
- **String coercion** — String types (`:string8`, `:string16`, `:string32`) now coerce
  atoms and numbers via `to_string/1` instead of rejecting them.

### Changed
- **Integer coercion rejects out-of-range values** — `new/1` now returns
  `{:error, %ValidationError{}}` for values outside the type's range (e.g., 300 for `:u8`)
  regardless of `validate:` setting. Previously, out-of-range values were silently accepted
  and only failed at `encode/1`.
- **Enum coercion rejects unknown values** — `new/1` now rejects unknown integer/atom
  values for enum fields. Only known variants (by atom, string, or integer) are accepted.
  Enum types also implement `validate_ast/3`.
- **Encode errors preserve field name** — `ArgumentError` during encode now extracts the
  field name from the error message instead of reporting `field: :unknown`.

### Fixed
- **UUID coercion no longer raises** — Malformed UUID strings (36-char or 32-char with
  invalid hex) now return `{:error, reason}` instead of raising `FunctionClauseError`.
- **Decimal rescue narrowed** — `Decimal.new/1` parse failures now rescue only
  `Decimal.Error` instead of catching all exceptions.

## [0.26.1] - 2026-03-09

### Added
- **Extended Coq formal verification** — 55 machine-checked theorems (up from 37),
  adding heterogeneous field width struct roundtrip, schema evolution forward
  compatibility, signed integer two's complement roundtrip, bool tri-state exhaustive
  proof, and batch concatenation isolation.

### Fixed
- **Compile warning** — `GridCodec.Registry.lookup_enum_by_name/1` no longer triggers
  "undefined or private" warning at compile time (uses `apply/3` for late binding).

## [0.26.0] - 2026-03-09

### Added
- **`.grid` format versioning (`@syntax 1`)** — Every generated `.grid` file now starts
  with an `@syntax N` directive declaring the format version. The parser validates the
  version and rejects files with unsupported syntax. Files without `@syntax` are assumed
  to use the latest version. The generator accepts `--syntax N` CLI flag and
  `config :app, :grid_codec, syntax: N` for targeting specific versions.
- **Formal `.grid` specification** — Complete format spec for syntax 1 added to
  `GridCodec.Schema.Parser` moduledoc, covering directives, blocks, types, field options,
  imports, comments, and type resolution rules.
- **Self-contained individual files** — Each struct `.grid` file now imports the enum types
  it references, making it independently parseable without the master file's import tree.
- **Cross-schema type imports** — When a struct in schema A references an enum defined in
  schema B, the export task generates correct cross-schema import paths. Enum files are
  generated in their home schema (lowest schema_id) and imported by reference from others.
- **Global type alias resolution** — `Formatter.build_type_aliases/2` and
  `Formatter.detect_all_enums/1` now operate across all schema groups, ensuring consistent
  type names in multi-schema exports.
- **Compiler `types:` option** — `use GridCodec.Struct, types: %{OrderSide: MyApp.OrderSide}`
  enables explicit mapping of `.grid` type names to Elixir modules when compiling from
  `.grid` files via `grid_file:`.
- **Auto-resolve enum types** — `GridCodec.Registry.lookup_enum_by_name/1` provides
  automatic resolution of `.grid` enum names to loaded Elixir enum modules, used as a
  fallback when no explicit `types:` mapping is provided.
- **`WIRE_SYNTAX_VERSION_CHANGED` breaking rule** — Breaking change detection now flags
  `@syntax` version changes between baseline and current schemas.
- **EBNF grammar** — Formal EBNF grammar (22 productions) added to `Parser` moduledoc,
  covering all `.grid` syntax constructs from lexical elements to top-level definitions.
- **VS Code / Cursor syntax highlighting** — TextMate grammar for `.grid` files in
  `editors/vscode-grid/` with full keyword, type, enum, and field highlighting.
- **Codec correctness proof suite** — `codec_proofs_test.exs` with 39 tests proving
  size consistency (P3), garbage rejection (P6+), type isolation (P7), formatter/parser
  agreement (P8), byte-level idempotence (P9), exhaustive finite-domain proofs (P10),
  and parser EBNF compliance (P11).

### Changed
- Formatter functions (`format/5`, `format_master/5`, `format_struct_file/3`,
  `format_enum_file/2`) now accept an `opts` keyword list with `:syntax` for version
  targeting and `:imports` for individual file dependencies.

### Removed
- **Legacy `message` keyword** — The deprecated `message` keyword is no longer accepted
  by the parser. Use `struct` instead.
- **Lenient struct attribute parsing** — Commas between struct attributes (e.g.,
  `template_id: 1, version: 2`) are now required.
- **Empty `any_of` lists** — `any_of: []` in batch blocks is now rejected as invalid.

### Fixed
- **`valid_identifier?` regex** — `?` is now restricted to trailing position only;
  `f?oo` is rejected while `filled?` is accepted.

## [0.25.0] - 2026-03-09

### Added
- **Structured `.grid` export** — `mix grid_codec.export` now generates a directory per
  `schema_id`, each containing a `schema.grid` master file with `import` directives plus
  individual files for each struct and enum. File paths are derived from the struct's
  `name:` option (e.g., `"Namespace.EventName"` → `namespace/event_name.grid`). Structs
  are sorted alphabetically by name.
- **`import` directive** — The `.grid` parser now supports `import "path"` directives.
  `parse_file_with_imports/2` resolves imports recursively with cycle detection. Breaking
  change detection and the `grid_file:` compiler option resolve imports automatically.
- **Configurable schema directory names** — Schema directories are configurable via
  application config: `config :my_app, :grid_codec, schemas: %{100 => "events"}`.
  Unconfigured schema_ids default to `schema_{id}`.
- **Formatter API** — New public functions: `format_master/4` (master file with imports),
  `format_struct_file/2` (standalone struct file), `format_enum_file/1` (standalone enum
  file), `build_type_aliases/2`, `struct_name/1`.

### Changed
- `.grid` export now produces directories instead of flat files. Old flat format is still
  fully supported by the parser and breaking change detection for backward compatibility.
- Struct ordering in generated `.grid` files changed from `template_id` to alphabetical
  by name.
- The `Schema` parser struct now includes an `imports` field (`[String.t()]`).

## [0.24.0] - 2026-03-09

### Added
- **Breaking change detection** — New `mix grid_codec.breaking` task compares `.grid`
  schema files against a baseline (git ref or file path) and reports wire-incompatible
  and source-incompatible changes. Inspired by [Buf](https://buf.build/docs/breaking/).
  Includes 21 WIRE rules (binary compatibility) and 8 SOURCE rules (API compatibility).
  Configurable via `.grid_codec.exs` with support for rule exclusions and category filters.
- **`.grid` schema export** — New `mix grid_codec.export` task generates declarative
  `.grid` schema files from compiled `defcodec` modules. Supports all field options
  (`wire_format`, `since`, `default`, `presence`, `value`), parameterized types
  (`decimal(scale: 8)`), groups, batches, and enums.
- **`.grid` schema parser** — Extended `GridCodec.Schema.Parser` to support batch/any_of
  syntax, parameterized type parameters, and all field options. Full round-trip fidelity:
  parse → format → re-parse produces equivalent schemas.
- **`--check` mode for `mix gridcodec.sql`** — Verifies the generated SQL file is up to
  date without writing to disk. Exits non-zero if stale or missing. Intended for CI and
  pre-push hooks.
- **`--check` mode for `mix grid_codec.export`** — Same check-without-write pattern for
  `.grid` schema files. Reports each stale or missing file individually.
- **CI breaking change job** — New `breaking` job in GitHub Actions runs
  `mix grid_codec.breaking` on pull requests with full git history.
- **Schema metadata in `__schema__/0`** — `batches` and `group_fields` are now included
  in the compile-time schema map, enabling the formatter and export task to produce
  complete `.grid` files.

## [0.23.2] - 2026-03-06

### Fixed
- **SQL signed integer decoding** — `sql_read_expr` used unsigned readers (`read_u16`,
  `read_u32`) for `:i16` and `:i32` types, producing incorrect positive values instead of
  negative values. Added `gridcodec.read_i8`, `gridcodec.read_i16`, `gridcodec.read_i32`
  helper functions with proper two's complement conversion. Also fixed `null_check_expr`
  to include signed integer null sentinels and corrected `sql_json_value_expr` signed null
  sentinel values.
- **F32/F64 NaN null decode** — `decode_value_ast` was missing for `:f32` and `:f64`,
  so IEEE 754 NaN (the null sentinel) was returned as-is instead of being converted to
  `nil`. Added `maybe_nil/1` helper that detects NaN via the canonical `v != v` check.

### Changed
- **UUID parsing uses arithmetic conversion** — Replaced `Base.decode16!/2` with a new
  `parse_uuid_nodash!/1` function that extracts individual bytes and converts hex chars
  to nibbles via arithmetic, avoiding sub-binary allocation and generic parsing overhead.
  Same approach already used by `parse_uuid_string!/1` for dashed UUIDs. Affects
  `uuid_string` encode hot path and both `uuid`/`uuid_string` coercion paths.
- **JSON pretty_format eliminates encode/decode round-trip** — `json_encode_map` now
  calls `do_pretty/2` directly on the map instead of encoding to JSON, decoding back,
  and then pretty-formatting.
- **PromEx metrics deduplicated** — `prom_ex_metrics/1` now delegates to
  `metric_definitions/1` instead of duplicating metric definitions.

### Deprecated
- **`GridCodec.Json.encode/2,3`** — Use `to_json/3` instead.
- **`GridCodec.Json.encode!/2,3`** — Use `to_json/3` with pattern matching instead.
- **`GridCodec.Json.decode/2,3`** — Use `from_json/3` instead.
- **`GridCodec.Json.decode!/2,3`** — Use `from_json/3` with pattern matching instead.

### Documentation
- Fixed `AGENTS.md` example using `gridcodec do` (should be `defcodec do`)
- Fixed `README.md` Elixir version requirement to match `mix.exs` (`1.18+`)

## [0.23.1] - 2026-03-06

### Added
- **Zero-surprise test suite** — 97 new tests (35 property-based, 62 unit) exercising
  every type invariant from first principles: roundtrip identity, `new/1` idempotence,
  encode determinism, `get/2` consistency, `new_binary` equivalence, multi-pass pipeline
  stability, content_hash reproducibility, concurrent thread safety, and decode resilience
  to garbage/truncated input. Covers integers, floats, strings, UUIDs, timestamps,
  datetimes, decimals, booleans, enums, bitsets, and char arrays.

### Fixed
- **CI compilation order bug** — Type modules guarded `generator/0` with
  `Code.ensure_loaded?(GridCodec.Generators)` which failed on fresh CI builds when
  the type file compiled before `generators.ex`. Changed to
  `Code.ensure_loaded?(StreamData)` across all 26 occurrences in 21 type files,
  eliminating the compilation order dependency.

## [0.23.0] - 2026-03-05

### Added
- **`:datetime_us` and `:datetime_ns` types** — DateTime-domain timestamp types
  that decode to `%DateTime{}` instead of raw integer microseconds/nanoseconds.
  Same 8-byte i64 LE wire format as `:timestamp_us`/`:timestamp_ns`, binaries
  are interchangeable. Use `:datetime_us` for application code, JSON APIs, and
  Ecto-like workflows; use `:timestamp_us` for hot paths where decode overhead
  matters.
- **`GridCodec.Batch` — heterogeneous batch encoding** with compile-time
  `any_of:` type sets. Preserves insertion order with O(1) count, random access,
  lazy streaming, and type-based filtering. Two strategies available:
  - **`:padded_union`** (default) — fixed-size entries padded to max block length,
    reuses `GridCodec.Group` wire format, O(1) random access from raw binary.
  - **`:typed_frames`** — length-prefixed entries with no padding waste, builds
    offset index on decode for O(1) access. 30% smaller wire size when types
    have different `block_length` values.
- **`batch/2` DSL macro** — `batch :commands, any_of: [PlaceOrder, CancelOrder],
  strategy: :typed_frames` generates compile-time union encoders/decoders with
  type-tag dispatch. Strategy is chosen once at compile time; the runtime API
  is identical regardless of strategy.
- **`GridCodec.Binary` module** — utilities for managing binary memory lifecycle.
  `detach/1` copies all binary-valued fields in a decoded struct, releasing
  sub-binary references to the original encoded data. `copy_field/1` is a
  nil-safe wrapper around `:binary.copy/1`.
- **`get/2` `:copy` option** — `get(binary, :field, copy: true)` wraps the
  result in `:binary.copy/1` to detach sub-binary references from the original
  encoded binary, preventing memory retention. Safe on any field type —
  non-binary values pass through unchanged.

### Changed
- **`GridCodec.Json` now uses Elixir's built-in `JSON` module** instead of
  `Jason`. The `:jason` dependency has been removed. Requires Elixir >= 1.18.
  Custom types should implement the `JSON.Encoder` protocol instead of
  `Jason.Encoder`. The `:pretty` and `:keys` options are preserved with the
  same behavior.

### Fixed
- **`coerce_ast` identity invariant** — fixed 6 types where `new/1` and
  `decode/1` produced different in-memory representations for the same value:
  - `:uuid_string` — coerce now normalizes to 36-char dash-separated string
    (was converting to raw 16-byte binary, breaking map key lookups)
  - `:timestamp_us`/`:timestamp_ns` — coerce now converts `%DateTime{}` and
    ISO 8601 strings to integer microseconds/nanoseconds (matching decode)
  - `:decimal`/`:positive_decimal` — `{mantissa, exponent}` tuple input now
    normalizes to `%Decimal{}` struct (matching decode)
  - Enum types — coerce now resolves known integer values to atoms (matching
    decode). Unknown integers still pass through.
  - `CharArray` — coerce now strips trailing null bytes (matching decode)

### Removed
- **`:jason` dependency** — `GridCodec.Json` now uses Elixir's native `JSON`
  module (available since 1.18). No external JSON library required.

### Documentation
- **Memory & Binary Lifecycle** section in performance guide — documents refc
  binary threshold (64 bytes), sub-binary retention problem, `on_heap` vs
  `off_heap` message queue strategy, `min_bin_vheap_size` tuning, the load
  balancer anti-pattern, and distribution wire efficiency.
- **Production Monitoring** section in performance guide — documents
  `erlang:memory(:binary)`, `recon:bin_leak/1`, common leak causes, and
  BEAM allocator flags for binary-heavy workloads.
- **AGENTS.md** updated with Binary Memory Model section explaining refc
  binary implications for GridCodec.
- **ExDoc**: All numeric type modules (U8–U64, I8–I64, F32, F64) now appear
  in the Types sidebar group. Consumer Integration guide added to extras.
- **Performance skill**: Documented that `iolist_to_binary` is NOT faster than
  `<<a::binary, b::binary>>` for encode assembly — the JIT optimizes binary
  concat into direct memcpy, avoiding iolist traversal overhead.

## [0.22.0] - 2026-03-05

### Added
- **`GridCodec.Match` — compile-time matchspec-like binary filtering** — Define
  predicate functions with `defmatch` that extract fields at compile-time known
  offsets and evaluate guard expressions without full decode.  Supports native
  Elixir guards (`==`, `<`, `band`, arithmetic), cross-field comparisons
  (`end_time_ns - start_time_ns > threshold`), multiple ANDed `where` clauses,
  and field selection via `select:`.  See [Binary filtering guide](docs/binary-filtering.md).
- **`GridCodec.Transcoder` — compile-time codec-to-codec transcoding** — Generate
  `transcode/1` functions that read fields from a source GridCodec binary at
  known offsets and pass them directly to a target encoder, skipping the full
  decode → struct → re-encode cycle.  Supports field rename (`to:`), value
  transforms (`transform:`), and partial field extraction.
- **`__match_meta__/0`** introspection function on all codec modules — exposes
  rich field metadata (wire module, domain module, offset, payload offset, size,
  endian) for use by `GridCodec.Match` and `GridCodec.Transcoder`.
- **UUID v5 generation** — `GridCodec.Types.UUID.generate_v5/2` (SHA-1
  name-based, RFC 4122 Section 4.3) with standard namespace helpers
  (`ns_dns/0`, `ns_url/0`, `ns_oid/0`, `ns_x500/0`).
- **Example app modules** — `ExampleApp.SpanFilters`, `ExampleApp.OrderFilters`,
  and `ExampleApp.SpanToEnvelope` demonstrating Match and Transcoder usage.
- **ETS binary-first benchmark** — `example_app/benchmarks/ets_binary_bench.exs`
  comparing struct-based vs binary-based ETS patterns across insert, lookup,
  scan+filter, batch export, and cross-field filtering.
- **Trace context benchmark** (revised) — `example_app/benchmarks/trace_context_bench.exs`
  with honest fan-out comparison: measures receive-side cost per recipient, full
  pipeline with real process sends, and cross-node ETF wire sizes.
- **Generators test suite** — `generators_test.exs` with property tests for all
  built-in type generators.
- **Property tests for Match and Transcoder** — randomized verification of
  predicate correctness and transcoding field preservation.

### Performance
- **Bitset `encode_ast` inlined** — `to_integer/1` call replaced with inline
  `MapSet.member?` + `Bitwise.bor` checks per flag, eliminating function call
  overhead in the encode hot path.
- **CharArray `encode_ast` inlined** — `encode/1` call replaced with inline
  `byte_size` + padding logic, eliminating function call overhead.

### Fixed
- **`__field_specs__/1`** now uses `effective_module` (respecting `wire_format:`
  overrides) instead of the raw domain module.  Previously, fields with
  `wire_format:` would return the domain type module, causing incorrect offset
  calculations in external tooling.
- **`defmatch` generated functions** no longer inject `@doc false`, allowing
  user-provided `@doc` annotations to flow through to ExDoc.
- **ExDoc warnings** — fixed stale top-level references for `new/1` and
  `new_binary/1` in the docs, plus broken `consumer-integration.md` links.

### Documentation
- **[Binary filtering guide](docs/binary-filtering.md)** — new guide covering
  `GridCodec.Match`, `GridCodec.Transcoder`, binary-first ETS patterns, and an
  end-to-end telemetry span pipeline example.
- **ExDoc sidebar** — Match and Transcoder now appear under "Core DSL" group;
  binary-filtering guide added to extras navigation.

## [0.21.0] - 2026-03-05

### Added
- **UUID v4 and v7 generation** — `GridCodec.Types.UUID.generate_v4/0` (RFC 4122)
  and `generate_v7/0` (RFC 9562, time-sortable). Also `v7_timestamp/1` to extract
  the millisecond timestamp from a v7 UUID.
- **Auto-inferred `wire_format:`** — `{:decimal, scale: N}` and
  `{:positive_decimal, scale: N}` now automatically select `:i64` / `:u64`
  wire format. Explicit `wire_format:` is no longer required for the common case.
- **Per-type micro benchmark** — `example_app/benchmarks/type_micro_bench.exs`
  measures encode, decode, and zero-copy get for every built-in type in isolation.
- **Ecto comparison benchmark** — `example_app/benchmarks/ecto_comparison.exs`
  compares GridCodec vs Ecto changeset + JSON across all pipeline stages.

### Performance
- **UUID parse/format**: `parse_uuid_string!/1` and `format_uuid/1` rewritten
  with direct nibble-level operations — no `String.replace`, no `Base.encode16`
  allocation chain.
- **Bitset inlined**: `to_integer/1` and `from_integer/1` now use compile-time
  generated `Bitwise.bor`/`Bitwise.band` checks instead of `Enum.reduce`.
- **Zero-overhead validation**: `__validate__/1` call eliminated entirely when
  `validate: false` — no function definition, no call site.
- **Static var decoder dispatch**: Replaced `apply/3` with direct module calls
  for string decode functions.

### Removed
- **`decode_as:` field option** — removed entirely (was deprecated in 0.20.0).
  Use `wire_format:` or parameterized types instead.

### Fixed
- **`compute_null_fixed_block`** now uses wire module for `wire_format:` fields.
- **Getter macro** uses wire module for offset calculation on `wire_format:` fields.

## [0.20.0] - 2026-03-04

### Added
- **Parameterized types** — field types can now accept options via tuple syntax:
  `field :amount, {:decimal, scale: 8}`. The type module receives these options
  to customize encoding behavior.
- **`wire_format:` field option** — explicitly control the binary encoding format
  while keeping the domain type for input/output. Works in both top-level fields
  and groups:
  ```elixir
  field :price, {:decimal, scale: 8}, wire_format: :i64
  ```
  This encodes as i64 on the wire (8 bytes) but accepts `Decimal.t()` as input
  and returns `Decimal.t()` on decode. Supported wire types: `:i8`, `:i16`, `:i32`,
  `:i64`, `:u8`, `:u16`, `:u32`, `:u64`, `:f32`, `:f64`.
- **`encode_to_wire_ast/2` callback** on `GridCodec.Type` — domain types implement
  this to convert their values to the wire type for encoding.
- **`int_pow10/1` helper** on `GridCodec.Types.Decimal` for efficient scaled integer
  arithmetic (lookup table for powers 0–8, recursive fallback).

### Changed
- **`field/3` macro** now accepts parameterized type tuples as the type argument.
- **Field documentation** now describes the Input/Wire/Output model clearly.

### Removed
- **`decode_as:` field option** — removed entirely. Use `wire_format:` instead.
  The `decode_as_ast/2` callback on `GridCodec.Type` is retained for internal use
  by the `wire_format:` mechanism.

## [0.19.0] - 2026-03-04

### Changed (BREAKING)
- **`encode/1,2` now returns `{:ok, binary()} | {:error, ValidationError.t()}`** instead
  of bare `binary()`. This applies to all generated codec modules and `GridCodec.encode/1,2`.
  Encode errors (validation failures, argument errors) are returned as `{:error, ...}`
  instead of raising.
- **Removed `new!/1`** — use `new/1` which returns `{:ok, struct} | {:error, ...}`.
  Libraries should not raise; callers can pattern-match on the result.
- **`GridCodec.Registry.encode/2`** no longer raises on unknown structs — returns
  `{:error, ValidationError.t()}` instead.

### Added
- `@spec encode(t(), keyword())` typespec on all generated encode functions
  (conditional on `generate_typespec: true`).

### Docs
- Updated docs/examples/tests to reflect new `{:ok, binary}` return type and
  removal of bang functions.

## [0.18.0] - 2026-03-04

### Added
- **`decode_as_ast/2` callback** on `GridCodec.Type` — general mechanism for
  decode-time type coercion. Any custom type can implement it. Source type module
  is passed via opts for generating optimized code (e.g., no unreachable clauses
  for integer source types).
- **`coerce_ast/1` for enum, bitset, chararray** — custom macro-based types now
  participate in `new/1` coercion. Enum: `"buy"` → `:buy`. Bitset: `["read"]` →
  `MapSet`. CharArray: string passthrough.
- **Group entry coercion** — `new/1` and `new_binary/1` now coerce group entry
  fields (string keys, string values). Error messages include group name context.

### Fixed
- **Unreachable clause warnings** in `decode_as` for integer source types — Elixir
  1.18 type checker no longer warns with `--warnings-as-errors`.

## [0.17.0] - 2026-03-04

### Added
- **`decode_as` option for group fields**: Wire-efficient types with typed decode
  output. `field :amount, :i64, decode_as: :decimal` stores as i64 on wire but
  decodes to `%Decimal{}`. `decode_as: {:decimal, scale: 8}` applies fixed-point
  scaling. Eliminates the double-scaling bug in period rotation carry-forward.
- **`new_binary/1`**: Coerce + validate + encode in one shot, zero struct allocation.
  Accepts maps (atom/string keys), keyword lists, or structs. Returns `{:ok, binary}`.
- **`content_hash/1`**: Deterministic SHA-256 from wire format for deduplication.
- **`decode_only/2`**: Selective field extraction using compile-time offsets.

### Changed
- **Unified `new/1` constructor**: Does coercion AND validation in one call.
  Accepts string keys, string values, atom keys, typed values — any mix.
  Returns `{:ok, struct}` or `{:error, %ValidationError{}}`.
- **`cast/1` removed**: `new/1` replaces it entirely — one constructor, one API.
- **Lazy error messages**: `ValidationError` message generated only when printed.
  Error path: 7.7x faster, 5x less memory.
- **Constructor optimized**: `:maps.find` short-circuit + `struct/2` (no key validation).
- **Decimal coercion**: `new(price: 100)` now returns `%Decimal{}` not raw integer.
- **Internal functions hidden** from ExDoc (`@doc false` on `__schema__`, `__type__`, etc.)
- **Auto `@moduledoc`** for custom enum/bitset/chararray modules (fixes ExDoc warnings).

### Fixed
- **Registry consolidation path**: Writes to `grid_codec/ebin/` not protocol consolidation dir.
- **Registry module discovery**: Scans beam files on disk, not `:code.all_loaded()`.
- **`ensure_all_loaded/0`** on Registry for runtime eager loading.

## [0.15.1] - 2026-03-04

### Fixed
- **CRITICAL: Consolidated Registry destroyed by protocol consolidation** — The
  `:grid_codec` Mix compiler was writing the Registry beam to
  `Mix.Project.consolidation_path()`, which Elixir's protocol consolidation
  recreates on every compile, destroying the Registry. Now writes to
  `_build/<env>/lib/grid_codec/ebin/` which is on the code path and not
  touched by protocol consolidation.
- **Fallback Registry finds 0 codecs due to lazy module loading** — `collect_codecs`
  now scans beam files on disk via `Path.wildcard` instead of relying on
  `:code.all_loaded()` which misses lazily-loaded modules.

### Added
- **`ensure_all_loaded/0` on Registry** — Eagerly loads all GridCodec modules from
  beam files on the code path. Call at application startup to ensure the fallback
  registry can find all codecs without the consolidated registry.

## [0.15.0] - 2026-03-04

### Added
- **`cast/1` coercion pipeline**: Converts external data (string keys, string values
  from JSON) to typed structs. Coerces `"100"` → integer, `"true"` → boolean,
  `"2026-01-01T00:00:00Z"` → DateTime, `"100.50"` → Decimal, UUID strings → binary.
  Returns `{:ok, struct}` or `{:error, field, reason}`.
- **`content_hash/1`**: Deterministic SHA-256 hash from the wire representation.
  Two structs with identical values always produce the same hash regardless of
  map key ordering. Useful for deduplication, idempotency, event fingerprinting.
- **`decode_only/2` projection**: Decodes only the requested fields from a binary
  using compile-time field offsets (O(1) per field). Returns a map with just
  the selected fields — no allocation for skipped fields.
- **`coerce_ast/1` optional callback** on `GridCodec.Type` — custom types can
  implement this for `cast/1` support. Implemented for all built-in types.

## [0.14.0] - 2026-03-04

### Added
- **Type-level validation** via `validate: true` option (per-module or global config).
  Generated at compile time — zero overhead when disabled. Catches type mismatches,
  integer overflow/underflow, invalid UUID formats, and wrong types for decimal/bool/
  timestamp fields BEFORE encoding, with structured `GridCodec.ValidationError` errors.
- **`GridCodec.ValidationError`** exception struct with `code` (`:type_mismatch`,
  `:out_of_range`, `:invalid_format`), `message`, and `details` (field, type, value,
  module). Pattern-matchable for programmatic error handling.
- **`validate_ast/3` optional callback** on `GridCodec.Type` behaviour — custom types
  can implement this to participate in pre-encode validation.
- Implemented `validate_ast` for all built-in types: u8-u64, i8-i64, f32, f64, bool,
  uuid, uuid_string, decimal, positive_decimal, timestamp_us, timestamp_ns.
- **`new/1` and `new!/1` constructors** on every codec struct. `new/1` returns
  `{:ok, struct}` or `{:error, %ValidationError{}}`. `new!/1` raises. Accepts
  maps or keyword lists. Runs validation when `validate: true` is enabled.

## [0.13.0] - 2026-03-04

### Added
- **`Group.to_lists_parallel/2`**: Decodes multiple groups in parallel, one
  process per group with pre-sized heaps (avoids GC during decode). Binary
  sharing is zero-copy. Auto-threshold at 256KB total group data; configurable
  via `:threshold` option. Falls back to sequential for small groups.
- **Property-based tests** for groups with custom types (enum roundtrip,
  multiple enums, decimal fields with nil values)

### Documentation
- Updated `GridCodec.Struct` moduledoc with `telemetry`, `telemetry_min_duration`
  options and global config example

## [0.12.0] - 2026-03-04

### Added
- **Optional telemetry** for encode/decode: per-module `telemetry: true` option
  or global `config :grid_codec, telemetry: true`. Emits `[:grid_codec, :encode]`
  and `[:grid_codec, :decode]` events with `duration` (native time), `bytes`,
  and metadata (`module`, `type_name`, `schema_id`, `template_id`). Zero
  overhead when disabled (default) — no timing code generated.
- **`telemetry_min_duration` option** — skip emitting events when duration is
  below a threshold (in `:native` time units). Filters out cheap operations
  so histograms focus on the latency you care about. Per-module or global config.
- **`GridCodec.Telemetry.Metrics`** — metric definitions for PromEx, LiveDashboard,
  or any `Telemetry.Metrics` consumer. `prom_ex_metrics/1` returns PromEx-compatible
  `Event.build` tuples; `metric_definitions/1` returns raw metric structs.
  Always compiles (no PromEx dependency required at grid_codec level).
- **Grafana dashboard** (`grafana/grid_codec.json`) — pre-built dashboard with
  encode/decode latency percentiles (p50/p90/p99), throughput, and binary sizes.

### Changed
- **Enum**: `to_integer/1` and `to_atom/1` now use pattern-matched function clauses
  instead of runtime map lookups (JIT compiles to direct comparisons).
  `encode_ast` and `decode_value_ast` generate fully inlined case clauses — no
  function calls in the encode/decode hot path. `getter_ast` also inlined.
- **Bitset**: Removed IIFE wrapper from `encode_ast`; uses direct case with nil
  handling instead of anonymous function allocation
- **CharArray**: Removed IIFE from `encode_ast`; `decode_value_ast` and `getter_ast`
  now use `:binary.match/2` for null-byte detection instead of
  `bin_to_list + take_while + list_to_bin` (pure binary ops, no list conversion).
  `decode/1` also updated.
- Added parallel decode benchmarks and threshold analysis scripts

## [0.11.0] - 2026-03-04

### Added
- **Custom types in groups**: Module aliases (enums, bitsets, char arrays, any
  `GridCodec.Type` implementation) now resolve correctly inside `group do` blocks
- **`:positive_decimal` type**: Optimized decimal for non-negative values (prices,
  quantities, balances). Skips sign handling on encode/decode. Wire-compatible
  with `:decimal` for positive values
- **`Group.encode_fast/3`**: Fast encoding with compile-time block length — skips
  per-entry size validation, single-pass count+encode via `:lists.mapfoldl`
- **`Group.parse_with_rest!/2,3`**: Combined parse + rest extraction in one call
- **Inline batch decoder**: Auto-generated `__decode_all_<group>__/2` function that
  pattern-matches all fields directly from the binary in a single recursive loop.
  No sub-binary allocation, no dynamic dispatch, no `{:ok, ...}` tuple per entry.
  Used automatically by `Group.to_list/1`
- **Inline batch encoder**: Auto-generated `__encode_<group>_group__/1` with direct
  local function calls to the entry encoder (JIT-inlineable), replacing anonymous
  function wrappers and dynamic captures

### Changed
- **Group encoding pipeline**: Struct encoder fast path now enabled for codecs with
  groups (previously fell back to `Map.from_struct`). Compile-time block length
  eliminates runtime size discovery
- **Group decoding pipeline**: Inline sequential parsing replaces `Enum.reduce` over
  runtime lists. Struct decoder builds the struct directly with all fields
  (fixed + groups + var) in a single literal — no `Map.merge` + `struct!`
- **`Group.to_list/1`**: Uses sequential binary walking instead of per-index access
  with bounds checking. When batch decoder is available, dispatches to it for
  maximum throughput
- **Decimal encode inlined**: `encode_ast` now generates inline `case` expressions
  that pattern-match `%Decimal{}` directly into binary segments, eliminating
  `encode_value/1` and `from_decimal/1` function calls and tuple allocation
- **Enum decode optimized**: `decode_pattern_ast` now extracts integers directly
  from binary patterns (not sub-binaries), and `decode_value_ast` calls
  `to_atom/1` directly instead of going through `decode/1` + tuple destructure
- **Timestamp encode inlined**: Integer timestamps write directly into the outer
  binary segment (`:: little-signed-64`) with no intermediate 8-byte binary

### Performance (TradingPeriodSettled shape, 5k users + 50k orders)

| Operation | v0.10.0 | v0.11.0 | Improvement |
|-----------|---------|---------|-------------|
| Encode | 38.8 ms / 17.0 MB | 33.8 ms / 9.4 MB | 1.15x faster, -45% memory |
| Decode+list | 56.2 ms / 49.2 MB | 25.0 ms / 30.1 MB | 2.25x faster, -39% memory |
| Full roundtrip | 90.5 ms / 66.6 MB | 64.6 ms / 40.7 MB | 1.40x faster, -39% memory |
| Lazy decode | 150 ns / 536 B | 249 ns / 1.16 KB | O(1) regardless of size |

## [0.10.0] - 2026-03-03

### Added
- **Auto-generated codec typespecs** for `GridCodec.Struct` modules (enabled by default)
  - `@type t() :: %__MODULE__{}`
  - `@type layout()` for payload binaries (`header: false`)
  - `@type framed_layout()` for binaries that include the 8-byte GridCodec header
- **`generate_typespec: false` option** to disable generated types and let modules
  provide custom `@type` declarations without conflicts

### Changed
- Generated `layout()` and `framed_layout()` are now size-aware:
  - Fixed-size codecs use exact bit-size binary types
  - Codecs with variable fields/groups use minimum fixed-block size plus byte-aligned tail

### Documentation
- Updated `GridCodec.Struct` docs with generated type details and the
  `generate_typespec` option
- Added Getting Started guide section for auto-generated typespecs and opt-out usage
- Updated README feature list to include `framed_layout()`

### Tests
- Added core tests for default type generation, opt-out behavior, and binary type shape
- Added example app tests that validate generated types in consumer usage, including:
  - opt-out modules with no generated types
  - custom user-defined types preserved when generation is disabled

## [0.9.0] - 2026-03-02

### Added
- **Stable type names**: `:name` option on `use GridCodec.Struct` for short,
  module-independent type strings (e.g., `"OrderSubmitted"` instead of
  `"Elixir.MyApp.Events.OrderSubmitted"`)
  - `__type__/0` generated on every codec module
  - Defaults to last segment of module name when not specified
  - Accepts string or atom values
  - Type name included in `__schema__/0` metadata
- **`GridCodec.Registry.lookup_by_type/1`**: Reverse lookup from type name
  string to codec module, enabling EventStore/Commanded serializer integration

## [0.8.0] - 2026-03-02

### Added
- **Schema evolution with `:since`**: Decoder pads shorter binaries from older
  schema versions using precomputed null sentinels — new fields decode as `nil`
  - `:since` option on field definitions for schema version tracking
  - `field_versions` map in `__schema__/0` metadata
  - Compile-time validation that `:since` values are non-decreasing in the fixed block
  - Zero overhead on same-version decode (single integer comparison fast path)
- **Auto-generated group entry codecs**: Groups with field declarations now
  generate entry encoder/decoder automatically from the type system
  - Eliminates manual binary encode/decode boilerplate for group entries
  - Compile-time rejection of variable-length fields in group entries
  - Group names included in `defstruct` with default `[]`
- **`GridCodec.BinaryInspector`**: Runtime binary inspection and diagnostics
  - `GridCodec.inspect_binary/2` top-level API
- **Type-aware field comparison**: `compare/5` and `compare_binaries/4` for
  comparing fields directly on encoded binaries without full decode
- **`encode_field/2` macro**: Pre-encode values for pin matching on custom types
- **JSON transcoding improvements**: Enhanced `GridCodec.Json` encoding/decoding

### Fixed
- Dead `nil` branch in group decoder generation (eliminated Elixir 1.19 type warnings)

## [0.7.0] - 2026-01-09

### Added
- **`.grid` schema files**: Define GridCodec structs in external schema files
  - Protobuf-inspired syntax with `.grid` file extension
  - New `struct` keyword with explicit header parameters: `struct Order (template_id: 1001) { ... }`
  - Support for per-struct version overrides: `struct Trade (template_id: 1002, version: 2) { ... }`
  - Schema-level metadata: `schema Trading { id: 100 version: 1 }`
  - Composite types: `type Price { mantissa: i64 exponent: i8 }`
  - Enums: `enum Side : u8 { buy = 1 sell = 2 }`
  - Optional fields with `?` suffix
  - Repeating groups support
  - Parser in `GridCodec.Schema.Parser`
- **Sigils for inline schemas**: `~g` (runtime) and `~G` (compile-time) sigils
  - Define schemas directly in Elixir code for tests and prototyping
  - `import GridCodec.Schema.Sigil` to use
- **Load structs from `.grid` files**: `use GridCodec.Struct, grid_file: "path/to/schema.grid", message: :Order`
- **Load structs from sigils**: `use GridCodec.Struct, grid_schema: ~G"...", message: :Order`
- **`:uuid_string` type**: UUID stored as 16 bytes but decoded to human-readable string format
  - JSON-safe: no need for custom encoder protocols
  - Same binary efficiency as `:uuid` type
- **`GridCodec.Json` module**: Simple JSON transcoder wrapper
  - `GridCodec.Json.encode(binary, Schema)` - binary → JSON string
  - `GridCodec.Json.decode(json, Schema)` - JSON string → binary
  - Works with structs that have JSON-safe types (use `:uuid_string` instead of `:uuid`)
- **Compile-time safety for `match/1,2` macro**: Matching on literal `nil` now raises
  a `CompileError` with a helpful message

### Changed
- Improved documentation for `match/1,2` macro to clearly explain that it returns
  raw sentinel values for nullable fields, not `nil`. Use `get/2` for null-safe access.

## [0.6.0] - 2026-01-08

### Removed
- **Breaking: Removed `GridCodec.Envelope` module entirely**
  - Use `MyCodec.get(binary, :field)` macro for zero-copy field access
  - Use `MyCodec.decode(binary)` for full decoding
- **Breaking: Removed `wrap/1` and `wrap/2` functions**
  - `MyCodec.wrap(binary)` is no longer available
  - `GridCodec.wrap(binary)` is no longer available
  - `Dispatch.wrap(binary)` is no longer available
- Removed `__field_info__/1` runtime function (was internal to Envelope)

### Rationale
- **Simplicity**: Envelopes added complexity without meaningful benefit
- **Performance**: Direct `get/2` macro is faster than envelope-based access
- **API clarity**: One clear way to access fields - the `get/2` macro

## [0.5.0] - 2026-01-08

### Changed
- **Breaking: New encode/decode API** - Header is now included by default
  - `encode(struct)` → includes 8-byte header (was payload only)
  - `encode(struct, header: false)` → payload only (new)
  - `decode(binary)` → expects header (was payload only)
  - `decode(binary, header: false)` → expects payload only (new)
  - Removed `encode!/1` and `decode!/1` (use `encode/1` and `decode/1` instead)
- **Breaking: Simplified field access API**
  - Renamed `get!/2` macro to `get/2` (no more bang suffix)
  - Removed slow function-based `get/2` - now only the fast macro exists
- **Zero-copy access updated for header-by-default**
  - `get/2` macro now expects framed binary with header by default
  - `get(binary, :field, header: false)` for payload-only access
  - `match/1` macro expects framed binary by default
  - `match([field: v], header: false)` for payload-only patterns
- `Dispatch.decode/1` updated for new API
- `GridCodec.Registry.encode/2` now accepts options
- Updated moduledoc with new API examples

### Rationale
- **Consistency**: `GridCodec.encode(struct)` and `MyCodec.encode(struct)` now produce identical binaries
- **Usability**: Follows pattern from popular libraries like Jason (`encode/2` with options)
- **Simplicity**: One way to access fields from binary (`get/2` macro), one way from envelope (`Envelope.get`)
- **Performance**: Fast path for `encode(struct)` (no options) has zero overhead
- **Dispatch**: Header enables `GridCodec.decode/1` to route to correct codec automatically

## [0.4.0] - 2026-01-08

### Added
- **`get/2` macro**: Inline field access with compile-time binary pattern matching
  - Expands at compile time to direct binary pattern, achieving ~70M ops/sec
  - Handles null values automatically (returns `nil` for sentinel values)
  - Use: `require MyCodec; MyCodec.get(binary, :field_name)`
- **`field/1` macro**: Generate field specs for generic access
  - Returns `{type_module, offset, endian}` tuple at compile time
  - Use: `GridCodec.get(binary, MyCodec.field(:price))`
- **`GridCodec.get/2`**: Generic field access with field specs
  - Runtime dispatch via type module's `get_value/3` callback
  - Used by `Envelope.get/2` for dynamic field access
- **`get_value/3` callback**: Added to `GridCodec.Type` behaviour
  - Implemented for `:u64`, `:i64`, `:u32`, `:uuid` types
  - Enables runtime field extraction with null handling
- **Benchmark suite**: Maps vs binary field access comparison
  - `example_app/benchmarks/maps_vs_codec.exs`
  - Results documented in `RESULTS_maps_vs_codec.md`

### Changed
- Updated moduledoc with Field Access Methods section documenting performance hierarchy:
  - `get/2` macro: ~70M ips (inline binary pattern with null handling)
  - `match/1` macro: ~70M ips (multi-field extraction, raw bytes)

## [0.3.0] - 2026-01-07

### Added
- **Mix Compiler**: New `:grid_codec` Mix compiler for automatic registry consolidation
  - Scans all loaded modules for GridCodec struct codecs at compile time
  - Generates optimized `GridCodec.Registry` module with pattern-match dispatch
  - Validates no conflicts (duplicate schema_id + template_id combinations)
  - Add to your project with `compilers: Mix.compilers() ++ [:grid_codec]`
- **Production Profiling Tools**: Docker-based profiling suite in `profile/`
  - Two-phase profiling: JIT warmup without perf, then clean profiling
  - JIT symbol resolution via `+JPperf true` for readable Elixir function names
  - Generates flame graphs and detailed reports
  - Profile markers for tagging specific operations in perf output
- **Example Application**: New `example_app/` with benchmarks and sample codecs
  - `OrderCreated` and `TradeExecuted` example events
  - Parameterized benchmarks for different payload sizes
  - Profile runner for integration with profiling tools
- **AI Agent Instructions**: `AGENTS.md` with comprehensive profiling and optimization guide

### Changed
- **Breaking**: Removed legacy map-based codec API - now struct-only via `GridCodec.Struct`
  - Use `use GridCodec.Struct` instead of `use GridCodec`
  - All codecs now define Elixir structs with generated encode/decode functions
  - Simplified API: `encode/1`, `decode/1`, `wrap/1`, `get/2`
- Reorganized compiler into GridCodec.Struct.Compiler (internal module)
- Updated README with struct-only examples and usage

### Fixed
- Dialyzer errors for Mix compiler module (added `:mix` to PLT)
- Bitset type warnings

### Removed
- Legacy `defcodec` macro and map-based codec API
- Old Livebook documentation (moved to example_app benchmarks)
- Planning docs and RFC documents

## [0.2.1] - 2025-12-31

### Added
- Interactive Livebooks for benchmarking and documentation:
  - `01_performance_comparison.livemd` - Compare GridCodec vs JSON, ETF, Protobuf, MessagePack
  - `02_subbinary_fanout.livemd` - Demonstrate BEAM's refc binary sharing for efficient fan-out
  - `03_internal_analysis.livemd` - Deep dive into generated code and BEAM bytecode
- Tests for refc binary sharing behavior (`refc_binary_test.exs`)
- NIF-based JSON benchmark comparison using `jiffy`

### Changed
- Consolidated 30+ benchmark scripts into 3 educational Livebooks
- Updated terminology: "zero-copy" → "direct field access" / "sub-binary sharing"
- `03_internal_analysis.livemd` now accurately reflects implemented optimizations

### Removed
- Legacy benchmark scripts (moved to Livebooks)

## [0.2.0] - 2025-12-30

### Added
- Fast-path encoder using `get_map_elements` BEAM instruction for fixed-only codecs
- Comprehensive nullable roundtrip tests for all types
- Property-based tests for codec correctness
- Fast-path comprehensive tests covering all type combinations
- Enum integration tests
- String variant tests (`:string8`, `:string16`, `:string32`)
- Benchmarking and profiling scripts in `benchmarks/`

### Changed
- **Performance**: Encode is now 1.6-1.7x faster for fixed-field codecs
- **Performance**: Decimal decode is 1.6x faster using direct struct creation
- **Performance**: UUID null check is 220x faster using equality instead of pattern match
- Replaced `Map.get/3` with `:maps.get/3` BIF in all type encoders (~7-8% faster)
- Skip unnecessary binary concatenation when no groups/var fields (5.6x faster)
- Skip unnecessary `Map.merge` in decoder when no groups/var fields
- Inline Decimal struct creation in decode (avoids `Decimal.new/3` validation overhead)

### Fixed
- Float types (`f32`, `f64`) now correctly handle `nil` values (encode as NaN sentinel)
- UUID type now correctly handles `nil` values (encode as all-zeros, decode back to `nil`)
- Enum `encode_ast` now returns proper binary segment expression for fast-path compatibility
- Bitset types now correctly use endianness in bitstring specifiers

## [0.1.0] - 2025-12-29

### Added
- Initial `defcodec` macro for defining binary schemas
- Support for fixed-size fields: `:u8`, `:u16`, `:u32`, `:u64`, `:i8`, `:i16`, `:i32`, `:i64`
- Support for float fields: `:f32`, `:f64`
- Support for `:uuid` (16-byte binary) and `:bool` fields
- Support for variable-length `:string` fields with `:string8`, `:string16`, `:string32` variants
- Support for `:decimal` (9-byte mantissa + exponent) fields
- Support for `:timestamp_us` and `:timestamp_ns` fields
- Support for custom enum types via `GridCodec.Types.Enum`
- Support for bitset types via `GridCodec.Types.Bitset`
- Support for char array types via `GridCodec.Types.CharArray`
- Support for repeating groups via `GridCodec.Group`
- `encode/1` - Encode map to binary
- `decode/1` - Decode binary to map
- `wrap/1` - Wrap binary for zero-copy access
- `get/2` - Get field from wrapped binary without full decode
- Configurable endianness (`:little` or `:big`)
- Schema versioning support
- SBE-style null sentinels for optional fields

