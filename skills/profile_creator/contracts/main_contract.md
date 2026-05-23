# Main Contract — LF Profile Creator

## Contract

Given a governed request to create a profile, the Profile Creator must produce a complete profile pack candidate and route it to review gates. It must not bypass governance or create final operational profiles directly.

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

## Required evidence

- Router decision applied.
- Supabase source verification requested or confirmed.
- Active governing asset identified.
- Existing assets checked to avoid duplicates.
- Runtime and automatic impact remain blocked.

## Rejection criteria

Reject when the output is only a prompt, prose description, checklist, or non-validated profile text.
