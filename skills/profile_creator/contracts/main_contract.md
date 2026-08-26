# Main Contract — LF Profile Creator

## Contract

Given a governed request to create a profile, the Profile Creator must produce a complete profile pack candidate and route it to review gates. It must not bypass governance or create final operational profiles directly.

A created-state claim is an outcome claim, not a label. When `status=PROFILE_PACK_CREATED`, the result must deliver an exact, resolvable candidate artifact that the declared receiver can inspect without reconstructing missing content or intent.

## Acceptance criteria

A valid output must include:

- `status`.
- `profile_pack_id`.
- `source_authority`.
- `deliverable_created`.
- `files_created`.
- `evidence_map`.
- `blocking_codes`.
- `next_gate`.

When `status=PROFILE_PACK_CREATED`, it must additionally include `deliverable_artifact_ref`. That reference must resolve to the created candidate, match `profile_pack_id`, and contain every component claimed in `files_created` with developed content.

## Required evidence

- Router decision applied.
- Supabase source verification requested or confirmed.
- Active governing asset identified.
- Existing assets checked to avoid duplicates.
- The created artifact is observable when creation is claimed.
- The next worker can consume the artifact without inventing its missing structure or content.
- Runtime and automatic impact remain blocked.

## Rejection criteria

Reject when the output is only a prompt, prose description, checklist, or non-validated profile text.
Reject a `PROFILE_PACK_CREATED` claim when only filenames, prose, an ID, or an unresolved reference is delivered instead of the created candidate artifact.
