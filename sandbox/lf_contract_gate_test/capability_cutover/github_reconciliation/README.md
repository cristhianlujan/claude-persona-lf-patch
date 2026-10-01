# GITHUB_RECONCILIATION cutover v1

`SADM-PP-L5-022` isolated capability cutover.

## Reuse only

- existing `GITHUB_RECONCILIATION_V1` functional core and contract;
- `LF_GOVERNANCE` as administrative super-admin root;
- `CURRENTNESS_AUTHORITY`;
- `CAPABILITY_EXECUTION_CONTRACT`;
- `ORCHESTRATOR_EXECUTION_GUARD_V1`;
- canonical capability registry/version/current tables and orchestrator binding entrypoint.

## Cutover

The cutover registers version `1.0.0`, promotes only that exact manifest to `public.lf_capability_current`, and changes the existing candidate asset to `VIGENTE / ACTIVO` with `owner_name=LF_GOVERNANCE`.

The functional core is unchanged: blob `2043574b30820aea3a1bde969366b196d23eb8f5`. The existing deterministic validator is unchanged: blob `b659d04e0485211a16b46a3788c5f04bb616ea59`, with 12 known checks.

## Boundaries

No applicability logic moves into the capability. No runtime/deploy/production action is performed. The legacy workflow and Edge function are preserved as rollback paths until `SADM-PP-L5-023`. No ZIP is used as authority.

## Rollback

`GITHUB_RECONCILIATION_cutover_rollback_v1.sql` removes only the exact current pointer, marks the registry entry non-active for new binding, and returns the asset to candidate read-only state. Immutable version history and legacy paths remain.

## Evidence required before apply

- exact-head PASE on this PR;
- source/currentness readback;
- functional core and validator blob identity;
- representative DB ROLLBACK of the cutover;
- post-apply readback from registry/current/assets/relations.
