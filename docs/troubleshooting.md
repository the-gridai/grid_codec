# Troubleshooting

Common GridCodec issues and how to resolve them.

## `{:error, :unknown_codec}` on decode

Cause:
- Header `{schema_id, template_id}` does not match any loaded codec.

Check:
- Encoder and decoder modules use the same `schema_id` and `template_id`.
- Consolidated registry is up to date (`mix compile`).

## `required field ... cannot be nil`

Cause:
- A field marked `presence: :required` was nil during encode.

Fix:
- Ensure required fields are present for both fixed-size and variable-size types.

## Integer encode raises `expects uN/iN integer`

Cause:
- Out-of-range or non-integer value passed to integer field.

Fix:
- Validate and clamp/coerce upstream values before struct construction.

## Group parse errors

Common errors:
- `{:insufficient_header, got, 4}`
- `{:insufficient_data, got, need}`
- `{:invalid_block_length, 0, count}`

Fix:
- Validate producer payload format and group entry encoder consistency.

## `.grid` parser rejects identifiers

Cause:
- Identifier is too long, invalid format, or exceeds parser safety budget.

Fix:
- Keep identifiers alphanumeric with underscores (and optional trailing `?` for optional fields).
- Increase parser options only for trusted schema input.

## Performance Regression

Checklist:
- Run `./profile/run.sh` and compare baseline report output.
- Confirm hot paths are in your code, not setup/noise.
- Prefer incremental optimizations and re-profile each step.
