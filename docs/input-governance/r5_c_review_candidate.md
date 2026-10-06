# R5-C review candidate — logical evidence + STORAGE_COMPACTION

Status: **DRAFT / DO NOT APPLY** until Claude review and explicit Cristhian approval.

## Scope

R5-C is atomic because new compact writers (R5-D) and historical compaction (R5-E) are unsafe unless all six assertion-complete readers already consume the **logical** evidence returned by `fn_input_validator_evidence_rehydrate_v1`.

The candidate changes:

1. `fn_guard_input_family_assessment_update`
2. `fn_guard_input_family_execution_update`
3. `fn_guard_input_validator_semantic_coherence_v512`
4. `fn_input_auth006_build_assertions`
5. `fn_input_owner_decision_assertions`
6. `fn_input_v58_build_assertions`
7. `fn_guard_input_governance_continuation_currentness_v1` only to admit the representation-only STORAGE_COMPACTION transition on terminal assessment receipts.

All current definitions are protected by exact MD5 preflight. Any drift stops the migration.

## STORAGE_COMPACTION contract

A terminal assessment update is admitted only when all five owner conditions hold:

1. No persisted column except `validator_evidence` changes. `validator_sha256` is checked separately for an independent negative test.
2. OLD has non-empty inline `assertions`; NEW has a valid `assertion_set_sha256` and has no inline `assertions`.
3. `rehydrate(NEW.validator_evidence) = OLD.validator_evidence` by exact jsonb equality.
4. The assertion set exists and its canonical `fn_v09_sha256_jsonb(assertions)` equals the reference.
5. `NEW.validator_sha256 = OLD.validator_sha256`.

Any rejected candidate transition raises `VALIDATOR_RECEIPT_IMMUTABLE` from the guards. No trigger is disabled.

The migration contains one positive self-test and negative self-tests for each clause. Clause 4 also retains a dedicated content-hash mismatch fail-closed path even though the R5-A table CHECK prevents ordinary corrupt inserts.

## Contract 5.13.x review

**Yes: a contract review is required before R5-C may be applied, and certainly before R5-D/E.**

Current INPUT_READINESS_CONTRACT 5.13 explicitly declares:

- `validator_evidence_required_fields` includes physical field `assertions`;
- assertion receipts are governed by `ASSERTION_RECEIPT_V2_RESULT_BOUND`;
- terminal evidence is treated as immutable by current guards.

R5 does **not** change the logical assertion receipt, its result/source hashes, or any existing `validator_sha256`. However, it changes two observable storage-contract facts:

- `assertions` may be represented physically by `assertion_set_sha256` and recovered through governed rehydration;
- a terminal receipt gains exactly one permitted representation-only transition, `STORAGE_COMPACTION`.

Recommended disposition: a **5.13.x patch revision** (not a new semantic family) that defines logical evidence as canonical, defines the compact physical representation, and names STORAGE_COMPACTION as hash-preserving/semantics-preserving. The owner/Cristhian must decide whether that patch is included in R5-C or landed as a prerequisite. Until then this PR stays Draft.

## Rollback

Before R5-D/E, rollback is straightforward: restore the seven exact pre-R5-C function definitions (the MD5-pinned bases) and drop `fn_input_validator_storage_compaction_check_v1`. No row conversion is needed because A/B leave all assessments inline.

After any compact receipts exist, rollback of C alone is forbidden; compact rows must first be re-expanded to inline evidence and verified.


## Claude review follow-up — static definitions

The original Draft used a guarded runtime transformation pattern
(`pg_get_functiondef + replace + EXECUTE`) for six readers. That pattern has been removed.

The migration now contains complete, static `CREATE OR REPLACE FUNCTION` definitions for all six assertion-complete readers. The continuation-currentness guard was already static and remains static. `pg_get_functiondef` is used only for fail-closed preflight/postcheck identity verification, never to synthesize executable function bodies.

Expected final MD5 values after the candidate:

| Function | final MD5 |
|---|---|
| `fn_guard_input_family_assessment_update()` | `3992ea214300ed7a4c444667d9927f1e` |
| `fn_guard_input_family_execution_update()` | `19760955ab8271b6edbfb4c8a3b2380d` |
| `fn_guard_input_governance_continuation_currentness_v1()` | `4f2352389ca15561c6693f1e9a82867b` |
| `fn_guard_input_validator_semantic_coherence_v512()` | `5f47ef6f1e0a8d5ee8ccd830ef9ba297` |
| `fn_input_auth006_build_assertions(bigint,bigint,text)` | `fcbe577977533315efa654e37f6fedaf` |
| `fn_input_owner_decision_assertions(bigint,bigint,text)` | `faaf7a7e0b6da0ac40eb740ecfda064a` |
| `fn_input_v58_build_assertions(bigint,bigint,text)` | `af95bfa42f649250c3585db9a6cb35fb` |

The migration fails closed if any post-apply function definition differs from these values.

## Live UPDATE rollback probes

See `docs/input-governance/r5_c_live_rollback_probe_2026-10-06.md`.

All requested paths passed inside `BEGIN/ROLLBACK`, including:
- terminal invalidated compaction;
- terminal current compaction;
- wrong assertion set rejection;
- validator hash mutation rejection;
- synthetic R5-D PENDING→terminal compact transition with exact inline-equivalent validator hash.

The live table has six physical BEFORE UPDATE triggers, not seven. Every probe traversed all six. Seven functions are MD5-governed by R5-C; that count is distinct from the physical trigger count.


## Claude blocker resolution — currentness shared trigger

The shared currentness trigger function is attached to three tables. The STORAGE_COMPACTION exception is now table-gated with nested IFs so assessment-only fields are never referenced until `TG_TABLE_NAME='input_family_assessments'` is already established.

Live pg_trigger inventory is documented in the rollback-probe evidence file. The two additional non-assessment tables were explicitly tested against the live baseline and corrected candidate:

- `input_gap_proposals`: same terminal-update rejection as today;
- `input_validator_chunk_timings`: same insert acceptance as today.

The corrected final MD5 for
`fn_guard_input_governance_continuation_currentness_v1()` is
`4f2352389ca15561c6693f1e9a82867b`.
