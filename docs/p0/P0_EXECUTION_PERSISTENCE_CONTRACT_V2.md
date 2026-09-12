# P0 execution persistence contract v2

## Purpose

Persist and reconstruct one source-bound P0 visual execution by `execution_id` without converting technical readiness into human acceptance, autonomy, P0-5, or production authorization.

This document supersedes the uploaded `P0_EXECUTION_PERSISTENCE_CONTRACT_V1.md` as the current contract for PR #140. V1 remains useful as historical design input, but it predates `20260812100613_lf_p0_execution_pass_integrity_v2.sql` and the stricter PASS invariants now deployed.

## Inventory decision

Existing private tables remain authoritative for review evidence objects, chunk upload, external durable evidence, human-review challenges, and authenticated human decisions. `public.lf_operation_execution` is a generic mutable operation model and has broader API-facing semantics. Neither structure represents the complete immutable visual execution graph, so this contract uses specialized private P0 tables and reuses `private.lf_p0_external_durable_evidence_v1` by foreign key for external artifacts.

No source binary is duplicated: the run stores a safe source reference, SHA-256, dimensions, and MIME type; artifact metadata may point to the existing owner-only external evidence registry.

## Normalized graph

| Relation | Responsibility |
|---|---|
| `private.lf_p0_execution_runs_v1` | identity, source, exact code/config/loop, runtime, terminal verdict, governance flags, supersession |
| `private.lf_p0_execution_elements_v1` | typed elements, parent hierarchy, text, bbox, confidence, modality |
| `private.lf_p0_execution_evidence_units_v1` | unique source-bound evidence units |
| `private.lf_p0_execution_element_evidence_v1` | exclusive one-owner evidence assignment |
| `private.lf_p0_execution_records_v1` | rules, validations, omissions, contamination, residuals, exceptions, pass results |
| `private.lf_p0_execution_artifacts_v1` | receipts, manifests, source/config/benchmark refs and hashes |
| `private.lf_p0_execution_transitions_v1` | ordered pass/state transitions |
| `private.lf_p0_execution_persist_attempts_v1` | insert/replay audit trail |
| `private.lf_p0_invalidated_loop_versions_v1` | append-only retroactive invalidation registry |

## Write and read APIs

- `private.fn_persist_lf_p0_execution_v1(jsonb)` validates and inserts the complete graph in one transaction.
- The request fingerprint is computed from PostgreSQL canonical `jsonb::text`. An exact retry returns `IDEMPOTENT_REPLAY` and appends an attempt; the same `execution_id` with different content fails.
- A failed child insert or V2 precondition rolls back the attempted graph.
- `private.fn_reconstruct_lf_p0_execution_v1(text)` rebuilds the normalized graph, including attempts, without granting direct table reads.

## V2 invariants

1. A `PASS` requires terminal `COMPLETE`, completion time, zero unresolved CRITICAL/HIGH/MEDIUM, and zero escaped mutations.
2. `acceptance_declared`, `autonomous_system_ready`, `p0_5_authorized`, and `production_authorized` remain constrained to `false` in this contract.
3. A PASS from an invalidated `loop_version` is rejected.
4. Every PASS element must have linked evidence.
5. Every evidence unit has exactly one element owner; duplicate ownership is rejected.
6. No persisted evidence unit may remain orphaned.
7. Parents, evidence, artifacts, records, and transitions must remain execution-scoped.
8. PASS requires non-empty dependency/config provenance.
9. PASS requires artifact roles `SOURCE`, `CONFIGURATION`, `RECEIPT`, `MANIFEST`, and `AUDIT`.
10. The `SOURCE` artifact SHA must equal `execution.source_sha256`.
11. The `CONFIGURATION` artifact SHA must equal `execution.configuration_sha256`.
12. RULE and VALIDATION records used by PASS must have `rule_version`.
13. Every VALIDATION record must have status `PASS` for a PASS execution.
14. A `PASS_RESULT` record with status `PASS` is mandatory.
15. Any unresolved `OMISSION`, `CONTAMINATION`, `RESIDUAL`, or `EXCEPTION` of severity CRITICAL/HIGH/MEDIUM blocks PASS.
16. The final ordered transition must end in `COMPLETE`.
17. Updates/deletes on v1 persistence relations are rejected by append-only triggers.
18. Supersession creates a new run referencing an existing run; it never mutates the prior row.
19. Private tables have RLS enabled, no API-role policies, and explicit ACL revocation. Only `service_role` executes the security-definer write/read functions; function `search_path` is empty.
20. Historical machine PASS or real packets bound to an older HEAD are evidence inputs, not current PASS authority.

## Verification

Canonical executable test: `supabase/tests/p0_execution_persistence_v2_contract.sql`.

It runs entirely inside a transaction and finishes with `ROLLBACK`. On 2026-08-12 it was executed directly against project `mhwmirqcgxxukpctffuv` and returned:

- suite: `P0_EXECUTION_PERSISTENCE_V2_CONTRACT`
- status: `PASS`
- checks: `20`
- committed rows: `0`

The 20 checks cover reconstruction, idempotency, conflicting retry, atomic rollback, exclusive ownership, incomplete false PASS, invalidated loop, cross-execution isolation, supersession, append-only mutation rejection, ACLs, element-without-evidence, failed validation, missing required artifact, final-transition integrity, dependency provenance, orphan evidence, source-hash binding, configuration-hash binding, and unresolved blocking records.

## Applied migrations

- `20260812090812_lf_p0_execution_persistence_v1.sql`
- `20260812090918_lf_p0_execution_supersession_v1.sql`
- `20260812091102_lf_p0_execution_fk_indexes_v1.sql`
- `20260812100613_lf_p0_execution_pass_integrity_v2.sql`

## EKB controls applied

- `EKB-P0-003` / `PRV-P0-003`: atomic 1:1 evidence ownership and no many-to-one PASS coverage.
- `EKB-P0-011` / `PRV-P0-011`: synthetic contract tests do not substitute real-source adversarial evidence.
- `AUD-008` / `PRV-AUD-008`: every required contract field must have a real producer and verifier.
- `ARC-006` / `PRV-ARC-006`: historical success cannot certify a newer HEAD.
- `AUD-009` / `PRV-AUD-009`: distinguish logical/canonical digests from persisted-byte/readback digests.

## Current governance result

`PASS_PERSISTENCE_CONTRACT_V2_TEST_SET` proves the persistence contract implementation. It does not prove autonomous visual acceptance. Current system gate remains `BLOCKED_REAL_EVIDENCE` until the same-HEAD real rerun, real corpus and holdout gates, and human adjudication requirements are satisfied.