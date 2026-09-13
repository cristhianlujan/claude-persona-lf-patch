# S31 A/B/C — Independent Review Handoff v0.2

Status: REVIEW-READY / NO SELF-CERTIFICATION
Strategy: S31 — LF Reusable Capability & Governed Development Platform
Review scope: S31-A, S31-B, S31-C only
Base main: `d4051d9c57fdfd09741da5ba2718c032eac56c92`
Source snapshot branch head: `3174366de353ee236991d3327c7bc6d9cf8d34a7`

## Reviewer isolation

The independent reviewer must not rely on producer conclusions as proof. Read the frozen source artifacts and deterministic receipts, reproduce or inspect the relevant assertions, and return a separate review receipt. Do not mutate S31, S30, S26, Learning Engine, runtime, Supabase or production.

The reviewer must not authorize Golden, merge or production. A PASS means only that the reviewed S31 candidate is semantically consistent with its stated contract and evidence ceiling.

## S31-A — Canonical Capability Model

Authoritative candidate for review: **v0.2**, not v0.1 lifecycle semantics.

Frozen assets:

- `canonical_capability_model_v0_2_candidate.schema.json`
  - Git blob: `ad549879dc5edfb32d040da3b0b0c4c6140614ad`
- `test_canonical_capability_model_v0_2_candidate.py`
  - Git blob: `f157fe93c443b0b691d229466f1ea9f0e6f60310`
- `canonical_capability_model_test_vectors_v0_1.json`
  - Git blob: `d243576af119d26a31ef71405f26100199f75166`
- `s31_a_lifecycle_erratum_v0_1.json`
- `s31_a_v0_2_execution_receipt_v0_1.json`

Mandatory review assertions:

1. Capability identity/version/owner/contracts/authority/currentness/dependencies/compatibility/execution/evidence/failure/source-of-truth are sufficiently generic for LF and do not move current owner implementations.
2. `lifecycle` does **not** invent a canonical ordered LF lifecycle.
3. Artifact maturity label, evidence level, runtime activation and promotion authority remain separate concepts.
4. `canonical_vocabulary_status` remains `UNRESOLVED` until a separate authority resolves it.
5. Self-certification remains forbidden.
6. Model/framework state cannot become authority or LF domain truth.
7. External frameworks remain replaceable implementations behind ports.
8. v0.1 lifecycle enum is treated as superseded evidence, not authority.

Deterministic producer evidence ceiling:

- schema valid;
- 6 legacy valid vectors upgrade successfully;
- 1 legacy framework-lock negative remains rejected;
- 4 lifecycle regressions pass;
- producer claim ceiling: `DETERMINISTIC_REGRESSION_ONLY`.

## S31-B — LF Work Package v0.2

Frozen assets:

- `validate_lf_work_package_v0_2_candidate.py`
  - Git blob: `e24405a1dce55257ed999733ba1bb22e9433b856`
- `test_lf_work_package_v0_2_candidate.py`
  - Git blob: `a8d0e4bf5f7f76a2139c529931fa14aa51b40a89`
- `lf_work_package_v0_2_candidate.schema.json`
- `s31_s30_execution_control_reuse_binding_v0_1.json`
- `s31_b_v0_2_execution_receipt_v0_1.json`

Mandatory review assertions:

1. Work Package remains an evolution of existing Task Packet/governance semantics, not an unrelated parallel contract.
2. Material sources require frozen revision/digest/authority receipt.
3. Exact-head claims reject PR merge refs and SHA mismatch.
4. EKB applicability must be fresh and mapped to actual controls.
5. Validator existence is not execution evidence.
6. Repairs/retries are bounded and equivalent-failure retry is forbidden.
7. `BLOCKED + independent safe scope` continues safe work instead of closing.
8. Close is denied while `next_safe_batch` exists or global remaining-work scan is absent.
9. Independent judge and no-self-certification requirements cannot be bypassed.
10. S30 implementation remains S30-owned; S31 consumes stable semantics by reference.

Deterministic producer evidence ceiling:

- exact Git blobs reproduced locally;
- self-test `11/11` PASS;
- producer claim ceiling: `DETERMINISTIC_REGRESSION_ONLY`.

## S31-C — Canonical Card/Fallback Semantics

Frozen assets:

- `canonical_card_resolution_v0_1.json`
  - Git blob: `3b232a0ec5b5cfc331c50d324491240add459f5e`
- `validate_canonical_card_resolution_v0_1.py`
  - Git blob: `c4401d80a62114c60c614cb0ac39bc6fa4c3acfb`
- `test_canonical_card_resolution_v0_1.py`
  - Git blob: `d162ba00c5cde780062a64f79dddea5f4b509f25`
- `s31_c_v0_1_execution_receipt_v0_1.json`

Mandatory review assertions:

1. Canonical states/modes remove semantic conflict without forcing a big-bang S26 migration.
2. Existing S26 vocabularies remain explicit boundary mappings.
3. `NO_DIRECT_CARD` never means immediate manual fallback.
4. Ambiguity fails closed.
5. Source authority has precedence over Card guidance.
6. Schema invention remains forbidden.
7. Safe fallback order is `CONTRACT_SCHEMA -> GENERIC_CAPABILITY -> SAFE_COMPOSITION -> MANUAL_REQUIRED`.
8. Each failed safe attempt requires typed attempt + reason + evidence.
9. Manual path is allowed only after safe alternatives are exhausted and no unresolved blocker remains.
10. S31 does not mutate S26 internals.

Deterministic producer evidence ceiling:

- exact Git blobs reproduced locally;
- self-test `12/12` PASS;
- producer claim ceiling: `DETERMINISTIC_REGRESSION_ONLY`.

## Required independent output

Return one JSON receipt with this minimum shape:

```json
{
  "receipt_version": "S31_ABC_INDEPENDENT_REVIEW_V0_2",
  "reviewer_independent_from_producer": true,
  "source_snapshot": {
    "main_base_sha": "d4051d9c57fdfd09741da5ba2718c032eac56c92",
    "s31_source_head": "3174366de353ee236991d3327c7bc6d9cf8d34a7"
  },
  "lanes": {
    "S31-A": {"verdict": "PASS|FAIL|BLOCKED", "findings": [], "claim_ceiling": "SEMANTIC_REVIEW"},
    "S31-B": {"verdict": "PASS|FAIL|BLOCKED", "findings": [], "claim_ceiling": "SEMANTIC_REVIEW"},
    "S31-C": {"verdict": "PASS|FAIL|BLOCKED", "findings": [], "claim_ceiling": "SEMANTIC_REVIEW"}
  },
  "overall_verdict": "PASS|FAIL|BLOCKED",
  "merge_authorized": false,
  "golden_authorized": false,
  "production_authorized": false
}
```

Any material source mismatch, stale source binding, missing required artifact, lifecycle overclaim, authority leak, evidence-level inflation or self-certification attempt is `FAIL` or `BLOCKED`, never silently repaired by the reviewer.
