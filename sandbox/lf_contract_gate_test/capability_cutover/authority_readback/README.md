# AUTHORITY_READBACK cutover v1

`SADM-PP-L5-022` isolated capability cutover.

The cutover reuses the existing `AUTHORITY_READBACK_V1` core and read-only adapters without changing their behavior. It registers version `1.0.0`, promotes only the exact manifest to `public.lf_capability_current`, and moves the existing candidate asset to `VIGENTE / ACTIVO` under administrative owner `LF_GOVERNANCE`.

Exact functional identities at source revision `c2f0d008d8588d2c439ea14b6143a522f38370e5`:

- core blob `686c21c49efa21f6ea83ae20d91dec046722c92c`;
- adapters blob `6ffc635c25b70472e28229f4d5da290555a77728`;
- core validator blob `f941564eb3e8d05056eb6b23fcb1576335412403` — 16 checks;
- adapter validator blob `4634ab5ab99528e47ab95acc33cf9dd59b893d57` — 10 checks.

No applicability decision, mutation, promotion of business assets, runtime/deploy action, or next-gate selection is added to this capability. Existing mutation/reconciliation functions remain untouched until their owning work is explicitly retired.

`AUTHORITY_READBACK_cutover_rollback_v1.sql` removes only the exact current pointer, marks the new binding authority non-active, and restores the candidate read-only asset state while preserving immutable version history and legacy paths.

Required evidence before apply: exact-head PASE, source/currentness readback, blob identity, representative DB ROLLBACK, and post-apply registry/current/assets/relations readback. ZIP is never terminal authority.
