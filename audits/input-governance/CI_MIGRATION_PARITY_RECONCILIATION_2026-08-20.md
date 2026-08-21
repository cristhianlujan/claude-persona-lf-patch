# CI Migration Parity Reconciliation — Input Governance

**Scope:** PR #179 · `INPUT_GOVERNANCE_AGENT` · contract 5.11
**Boundary:** `20260818213426` inclusive
**Status:** CI validation pending; this note is not a PASS verdict.

## Controls introduced

- Existing LF global migration parity remains authoritative for its existing managed families.
- `input_governance_*`, `programacion_input_governance_*`, and the exact `retire_b2b_auth005_legacy_totp_screen` name are delegated to a dedicated parity gate rather than silently ignored.
- Dedicated parity compares exact migration version set, exact migration name, and SHA-256 of canonical SQL against `supabase_migrations.schema_migrations`.
- Duplicate migration versions, malformed ledger SQL, empty source sets, out-of-bound remote rows, version drift, name drift, and content drift fail closed.
- Historical Input Governance migrations before the boundary remain a separately documented legacy synchronization gap; the new gate does not claim to repair or attest that earlier range.

## Source reconciliation

Three post-boundary ledger sources missing from the branch were restored from the authoritative Supabase migration registry:

- `20260819123111_input_governance_auth_transversal_links_validation_cleanup_20260819.sql`
- `20260819181508_input_governance_r5_11_rate_builder_sync_6.sql`
- `20260819231953_input_governance_r5_11_semantic_assertion_recuration.sql`

Six recent migration files were renamed to the versions actually assigned by the Supabase migration registry. The exact SQL bytes are sourced from the authoritative migration registry:

- `20260821031021_input_governance_v511_auth001_visual_recuration_template.sql`
- `20260821031447_input_governance_v511_canonical_drift_successors.sql`
- `20260821031614_input_governance_v511_canonical_drift_successor_screen52.sql`
- `20260821031702_input_governance_v511_canonical_drift_successor_screen53.sql`
- `20260821031748_input_governance_v511_canonical_drift_successor_screen54.sql`
- `20260821031832_input_governance_v511_canonical_drift_successor_screen56.sql`

The parity gate also identified a serialization mismatch in:

- `20260819040924_input_governance_r4_contract_v5_constraint.sql`

That file and the six recent files were replaced with the exact bytes stored in `supabase_migrations.schema_migrations`; no database row was changed or replayed.

## Explicit non-actions

- No historical Supabase migration ledger row was edited.
- No database guard was disabled.
- No migration was reapplied.
- No PR merge, promotion, Golden/Human activation, EKB activation, or production authorization is implied.

Final closure requires GitHub Actions readback on the reconciled HEAD.
