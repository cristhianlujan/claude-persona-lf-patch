# S31 CURRENTNESS_AUTHORITY — parity + material prewrite hardening v1

Governed execution: `EXEC-S31-CURRENTNESS-HARDENING-PREWRITE-20260914-001`  
Backlog: `public.lf_audit_backlog.id IN (58,59)`  
Capability reused: `CURRENTNESS_AUTHORITY 1.0.0` / manifest `9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09`.

## Scope

This lot adds one fail-closed prewrite guard candidate. It does **not** modify or relabel `CURRENTNESS_AUTHORITY 1.0.0`, create a parallel currentness capability, mutate a Strategy snapshot, enable runtime/production/Golden, or perform a durable DB change.

The guard composes two already-governed truths before a material write:

1. `CURRENTNESS_AUTHORITY` receipt: only `CURRENT` / `CURRENT_REBOUND`, `ready=true`, `dependency_completeness=COMPLETE`, exact authority ref, and exact effective revision are eligible.
2. `LF_MIGRATION_SOURCE_PARITY` evidence: `EXACT` is eligible for ordinary material writes. `SOURCE_FIRST_PENDING` is eligible only for the exact one pending migration applying itself, with existing managed parity exact and `remote_ahead=false`. `REMOTE_ONLY`, `MIXED`, unknown, malformed or mismatched evidence is `UNKNOWN_FAIL_CLOSED`.

Global `main` SHA drift alone is not a blocker; unrelated drift must already have been resolved upstream as `CURRENT_REBOUND`.

## Applicable consumer inventory found in live Supabase

- `ACTUALIZACION_DB_LF` — ACTIVE enforcement; owner of DB/MIGRATION/FUNCTION/TRIGGER updates. This is the first applicable material-write consumer for backlog 58.
- `RETIRO_ACTIVO_LF` — `OP_CANDIDATE`; RETIRE Router bindings for PERFIL/CARD/ADAPTER/SKILL are `CANDIDATO_READ_ONLY`. No durable retire writer function exists yet.
- `TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF` — `OP_CANDIDATE` / `CANDIDATO_READ_ONLY`; no durable transition writer function exists yet.
- No active PROMOTE or DEPRECATE Router operation was found in this readback; no consumer is invented.

Backlog 59 therefore remains open after this source candidate until each material consumer that can actually write binds the guard prewrite and demonstrates a receipt/readback. Candidate-only consumers must bind it before activation.

## Regression matrix

`./s31_currentness_hardening_v1_test.sql` covers:

1. EXACT + CURRENT positive.
2. EXACT + CURRENT_REBOUND positive for irrelevant drift.
3. REMOTE_ONLY fail-closed.
4. MIXED fail-closed.
5. Exact one SOURCE_FIRST_PENDING migration may apply itself.
6. SOURCE_FIRST_PENDING cannot authorize unrelated material write.
7. SOURCE_FIRST_PENDING cannot authorize another migration target.
8. STALE_AFFECTED blocks.
9. UNKNOWN_FAIL_CLOSED blocks.
10. dependency completeness not COMPLETE blocks.
11. effective revision mismatch blocks.
12. authority-ref mismatch blocks.

## Evidence / cross-assurance

EKB inputs: `CI-MIGRATION-SOURCE-PARITY-001`, `CURRENTNESS-AUTHORITY-CROSS-OWNER-DRIFT-GAP-001`, `CI-MIGRATION-PARITY-CROSS-OWNER-BLOCKING-001`, `STRATEGY-UPDATE-PREWRITE-CURRENTNESS-GATE-001`.

S36 cross-assurance remains downstream: `S36-INTAKE-MIGRATION-SOURCE-FIRST-DB-GIT-LAG-001`, `S36-INTAKE-S31-CURRENTNESS-AUTHORITY-V1`, `S36-INTAKE-ASSET-TRANSITION-RETIRE-DEPRECATE-001`.

Claim ceiling: `SOURCE_CANDIDATE_ROLLBACK_ONLY_NOT_DURABLE_ENFORCEMENT`.
