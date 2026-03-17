---
name: documentation-quality
description: Audit and improve GridCodec documentation quality — moduledocs, typedocs, CHANGELOG, README, AGENTS.md, and inline code docs. Use when reviewing docs, writing changelogs, updating README, or checking documentation coverage.
---

# Documentation Quality for GridCodec

## Documentation Layers

| Layer | File(s) | Audience | Standard |
|-------|---------|----------|----------|
| Module docs | `@moduledoc` in each `.ex` | Developers using the API | Every public module |
| Function docs | `@doc` on public functions | Developers calling the function | Every public function |
| Type docs | `@typedoc` on types | Developers reading typespecs | Every public type |
| Changelog | `CHANGELOG.md` | Upgraders, release notes | Every version bump |
| README | `README.md` | First-time users | Feature overview + quick start |
| Agent guide | `AGENTS.md` | AI agents working with the code | Architecture + workflows |
| Design docs | `docs/` | Deep technical reference | As needed |

## Changelog Standards

Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/):

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added       ← new features
### Changed     ← changes to existing features
### Deprecated  ← soon-to-be-removed features
### Removed     ← removed features
### Fixed       ← bug fixes
### Documentation ← doc-only changes
### Performance ← performance improvements (optional, custom)
```

**Rules:**
- Every commit that changes behavior gets a changelog entry
- Bold the feature name: `- **Feature name** — description`
- Include benchmark numbers for performance changes
- Reference the version where something was introduced
- Group related changes under a single bullet

**Bad:**
```markdown
- Updated encoder  ← what changed? why?
```

**Good:**
```markdown
- **Decimal encode inlined**: `encode_ast` now generates inline case expressions
  that pattern-match `%Decimal{}` directly into binary segments, eliminating
  `encode_value/1` and `from_decimal/1` function calls and tuple allocation
```

## Moduledoc Standards

Every public module needs `@moduledoc` with:

1. **One-sentence summary** — what this module does
2. **Wire format** (for types) — ASCII diagram of binary layout
3. **Usage example** — minimal working code
4. **Options table** (if configurable) — name, type, default, description

**Template for types:**
```elixir
@moduledoc """
One-sentence description.

## Wire Format

    ┌─────────────────────────────┐
    │  field (type, size)         │
    └─────────────────────────────┘
    Total: N bytes

## Usage

    defcodec do
      field :name, :type_atom
    end

## Null Representation

Uses `SENTINEL` as the null sentinel.
"""
```

**Template for feature modules:**
```elixir
@moduledoc """
One-sentence description.

## Features

- Feature 1
- Feature 2

## Example

    MyModule.function(args)

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
"""
```

## Function Doc Standards

```elixir
@doc """
One-sentence description.

## Examples

    iex> MyModule.function(input)
    expected_output

## Options

- `:option` — description (default: `value`)
"""
```

**Skip `@doc` for:**
- Private functions (`defp`)
- Functions marked `@doc false`
- Generated internal functions (`__encode_*`, `__decode_*`, `__validate__`)

## Documentation Review Checklist

### ExDoc Build
- [ ] `mix docs` produces zero warnings
- [ ] All public modules appear in sidebar groups (`groups_for_modules` in `mix.exs`)
- [ ] Guide pages are listed in `extras` in `mix.exs`

### Coverage
- [ ] Every public module has `@moduledoc`
- [ ] Every public function has `@doc`
- [ ] Every public type has `@typedoc`
- [ ] `CHANGELOG.md` is up to date with latest version
- [ ] `AGENTS.md` reflects current architecture

### Quality
- [ ] Examples are copy-pasteable (no `...` or `# your code here`)
- [ ] Wire format diagrams match actual binary layout
- [ ] Options tables list ALL options with defaults
- [ ] Changelog entries explain WHY, not just WHAT
- [ ] No stale references to removed features or old API

### Consistency
- [ ] Type names match between docs and code (`:u64` not "unsigned 64-bit")
- [ ] Module references use backticks (`GridCodec.Group`)
- [ ] Function signatures match actual arities
- [ ] Version numbers in docs match `mix.exs`

## When to Update Docs

| Trigger | What to update |
|---------|---------------|
| New feature | CHANGELOG, moduledoc, README if user-facing |
| API change | CHANGELOG, affected moduledocs, migration notes |
| Performance change | CHANGELOG with numbers, AGENTS.md if profiling workflow changed |
| Bug fix | CHANGELOG, add test docstring explaining the fix |
| New option | CHANGELOG, moduledoc options table, README if important |
| Version bump | CHANGELOG date, mix.exs version |
| New field option | CHANGELOG, `.grid` parser/formatter moduledocs, breaking rules moduledocs |
| New breaking rule | CHANGELOG, rules module `@moduledoc`, AGENTS.md rule count |
| Schema evolution change | CHANGELOG, AGENTS.md "Schema Evolution" section |
| `@syntax` version change | Parser `@moduledoc`, Formatter `@moduledoc`, CHANGELOG |
| Formatter API change | Formatter `@moduledoc`, codec-development skill, AGENTS.md |
| Cross-schema feature | AGENTS.md, codec-development skill, export task `@moduledoc` |

## .grid Schema Modules Documentation

The schema evolution layer includes several modules that need documentation:

| Module | Required docs |
|--------|--------------|
| `GridCodec.Schema.Parser` | Formal `.grid` syntax 1 spec in `@moduledoc`; `@syntax` directive; `current_syntax/0`; `parse_file_with_imports/2` |
| `GridCodec.Schema.Formatter` | Output format; `format/5`, `format_master/5`, `format_struct_file/3`, `format_enum_file/2` accept `opts` (`:syntax`, `:imports`); `current_syntax/0`; `detect_all_enums/1`, `referenced_enums/2` |
| `GridCodec.Breaking.Checker` | API usage, options (`category`, `except`), git baseline usage |
| `GridCodec.Breaking.Rules.Wire` | List of all 22 WIRE rules (incl. `WIRE_SYNTAX_VERSION_CHANGED`) |
| `GridCodec.Breaking.Rules.Source` | List of all 8 SOURCE rules |
| `GridCodec.Breaking.Config` | `.grid_codec.exs` format and defaults |
| `GridCodec.Registry` | `lookup_enum_by_name/1` for `.grid` type auto-resolution |
