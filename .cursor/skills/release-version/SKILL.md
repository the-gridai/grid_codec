---
name: release-version
description: Release a new GridCodec version — bump version, update CHANGELOG, run quality checks, verify CI, commit, tag, and push to main. Use when the user asks to release, push a version, cut a release, or ship changes to main.
---

# Release Version — Push a New GridCodec Version

## Pre-Release Checklist

Run these before bumping the version:

```bash
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors
mix test
```

All must pass with zero issues. If any fail, fix before proceeding.

## Release Steps

### 1. Determine Version Bump

Follow [Semantic Versioning](https://semver.org/):

| Change Type | Bump | Example |
|-------------|------|---------|
| Breaking API change | Major (X.0.0) | Removed public function, changed return type |
| New feature, backward-compatible | Minor (0.X.0) | New type, new option, new module |
| Bug fix, docs, performance | Patch (0.0.X) | Fixed coerce_ast, updated docs |

### 2. Update `mix.exs` Version

```elixir
# In mix.exs, line ~4:
@version "X.Y.Z"
```

### 3. Update CHANGELOG.md

Move `[Unreleased]` entries under a dated version header:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Fixed
- ...
```

Keep an empty `## [Unreleased]` section at the top for future changes.

### 4. Verify Version Consistency

Check that these all match:
- `@version` in `mix.exs`
- Top version entry in `CHANGELOG.md`
- Any version references in `README.md`

### 5. Regenerate .grid Baselines

If any field options, types, or schema metadata changed:

```bash
cd example_app && mix grid_codec.export --output-dir priv/schemas
cd example_app && mix grid_codec.export --check        # verify they match
cd example_app && mix grid_codec.breaking               # should report no issues
```

Use `--syntax N` to target a specific `.grid` format version (defaults to latest).
Commit the regenerated `.grid` files with the release.

### 6. Final Quality Gate

```bash
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors
mix test
cd example_app && mix run benchmarks/quick_bench.exs
```

### 7. Commit and Tag

```bash
git add -A
git commit -m "Release vX.Y.Z

<one-line summary of the release>"

git tag -a vX.Y.Z -m "vX.Y.Z"
```

### 8. Push to Remote

```bash
git push origin main
git push origin vX.Y.Z
```

### 9. Verify CI Passes

After pushing, **wait for CI to complete** and confirm all jobs pass:

```bash
# Watch CI status (poll until completed)
gh run list --branch main --limit 1

# If CI fails:
# 1. Check the failure logs: gh run view <run-id> --log-failed
# 2. Fix the issue locally
# 3. Push the fix (do NOT force-push the tag yet)
# 4. Verify CI passes on the new commit
# 5. If the tag needs updating:
#    git tag -d vX.Y.Z
#    git push origin :refs/tags/vX.Y.Z
#    git tag -a vX.Y.Z -m "vX.Y.Z"
#    git push origin vX.Y.Z
```

**CI must be green before considering the release complete.** A red CI means the release is broken for consumers.

### 10. Post-Release

After CI passes:
- Verify the tag appears on GitHub
- If publishing to Hex: `mix hex.publish`
- Update consumer repos (e.g., downstream apps) to reference the new version

## Common CI Failures

| Failure | Cause | Fix |
|---------|-------|-----|
| `generator/0 is undefined` | Type module compiled before `GridCodec.Generators` | Change `Code.ensure_loaded?(GridCodec.Generators)` to `Code.ensure_loaded?(StreamData)` in the guard |
| `--warnings-as-errors` | Unused variable, unreachable code | Fix the warning in source |
| Format check | Unformatted file | `mix format` then re-commit |
| Credo strict | Style violation | Fix the issue or add `# credo:disable-for-this-file` if intentional |

## Emergency Hotfix

For critical bug fixes on a released version:

1. Create a branch from the tag: `git checkout -b hotfix/vX.Y.Z vX.Y.Z`
2. Apply the fix
3. Bump patch version
4. Follow steps 2-9 above
5. Merge the hotfix branch back to main

## Version Pinning in Consumers

Consumer `mix.exs` should pin GridCodec:

```elixir
{:grid_codec, git: "git@github.com:Spectral-Finance/grid_codec.git", tag: "vX.Y.Z"}
```

Or for development against latest main:

```elixir
{:grid_codec, git: "git@github.com:Spectral-Finance/grid_codec.git", branch: "main"}
```
