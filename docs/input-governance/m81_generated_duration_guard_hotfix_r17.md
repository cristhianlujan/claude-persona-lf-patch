# M8.1 generated-duration guard hotfix — R17 preflight contract

Scope: `IG_CURATOR_VALIDATOR_REFACTOR_V2` / M8.1 regression hotfix.

- Baseline DB guard MD5: `ba81b944215d72bdba21c8f9fa3d17ea`.
- Change: in the `TERMINAL_SUCCESSOR` equality comparison, exclude only `curator_duration_ms` and `validator_duration_ms` in addition to the three invalidation fields already excluded.
- Rationale: both duration columns are generated from source timestamps and may arrive as `NULL` in `NEW` during `BEFORE UPDATE`; source timestamps remain in the equality comparison.
- Fail closed: migration aborts if the live guard MD5 differs from the pinned baseline.
- No production, no promotion, no data deletion.
- Readback source of truth: `pg_get_functiondef`, function MD5, representative successor closure, and currentness/readiness state in PostgreSQL.
- Independent evidence reference: `lf_eventos #19780` demonstrated the exact logical correction closes the full dispatcher → Curator → Validator flow under rollback, and identified no finding in N-7 itself.
- R17 v2 authority: `lf_eventos #19781`.
