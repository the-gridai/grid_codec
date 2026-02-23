# Schema Evolution

This guide covers safe changes to GridCodec schemas over time.

## Compatibility Rules

- Preserve existing `template_id` for a message type.
- Keep existing fixed fields stable in type and order.
- Add new fields as optional where possible.
- Bump `version` when introducing non-backward-compatible changes.

## Safe Changes

- Add optional variable-length fields.
- Add new message types with new `template_id`s.
- Add enum values when consumers can handle unknown variants.

## Risky Changes

- Changing field type width (`u32` -> `u16`).
- Reordering fixed-size fields.
- Reusing `template_id` for a different shape.

## Recommended Rollout

1. Add new producer with backward-compatible payload.
2. Deploy decoders that accept both versions.
3. Migrate producers to the new format.
4. Remove old paths only after all consumers are updated.

## Header-Based Version Checks

Generated decoders validate headers and return structured errors for
schema/template/version mismatches. Keep versioning explicit for predictable
deployments.
