# S31 A/B/C — Independent Review Handoff v0.6

Status: REVIEW-READY / QUALITY-PACK-BOUND / PRIOR BLOCKERS REPAIRED / NO SELF-CERTIFICATION
Strategy: S31 — LF Reusable Capability & Governed Development Platform
Review scope: S31-A, S31-B, S31-C only
Review case: S31-ABC-IR-002

## Execution boundary

Execute only in a clean reviewer context that did not produce S31. The reviewer must use `INDEPENDENT_CHAT_CONTEXT`, must not repair artifacts while reviewing, and must not authorize Golden, merge or production.

The producer provides no semantic target verdict. Deterministic producer receipts may be inspected only as evidence of executed deterministic checks; they are not semantic proof.

Required metadata remains:

- reviewer_is_producer = false
- producer_context_available = false
- external_paid_model_used = false
- automated_semantic_judge_implemented = false

## Frozen review artifact

Review exactly this immutable bundle:

- `artifact_ref`: `github://cristhianlujan/claude-persona-lf-patch@48ef393011740c2e253e719d4e786b724e2d8183/sandbox/lf_contract_gate_test/s31_bootstrap/s31_abc_independent_review_bundle_v0_6.json`
- `artifact_sha_or_digest`: `b93837676f085aa36da250cb5dc17e9bef65bd8f`
- candidate snapshot inside the bundle: `6878c1443d4d53e87d2d6bd3c0fbeba3d7163c0e`
- base main: `d4051d9c57fdfd09741da5ba2718c032eac56c92`

This is a new scope-specific ABC freeze. It does not invalidate or replace the independently frozen D-G scope.

## Prior independent finding

IR-001 returned `BLOCK_PIPELINE` for three codes:

1. `S31_B_EXECUTED_VALIDATION_SHA_BINDING_MISSING`
2. `S31_B_EKB_CURRENTNESS_EVIDENCE_SELF_ASSERTED`
3. `S31_C_FALLBACK_ENTRY_STATUS_GUARD_MISSING`

The exact prior receipt and the producer repair receipt are immutable refs inside the new bundle. Treat them as provenance and repair claims only; independently verify the repaired artifacts themselves.

## What changed in the repaired candidate

S31-B now requires resolver-backed evidence instead of trusting producer booleans alone:

- executed validation SHA must equal the governed execution identity;
- validation receipt is resolved independently, SHA-256 checked, and content-bound to SHA/runner/exit status;
- EKB freshness is backed by a resolved `EKB_FRESHNESS_RECEIPT` matching run id, time, codes and control mapping;
- currentness is backed by a resolved `CURRENTNESS_RECEIPT` matching base/head/executed SHA and ref kind;
- successful close also resolves final EKB readback evidence;
- the execution worker cannot act as its own evidence resolver.

Producer deterministic result: `S31-B PASS 26/26`.

S31-C now requires canonical `resolution_status` as executable input to `fallback_decision` and fails closed unless it is exactly `NO_DIRECT_CARD`. `RESOLVED`, `AMBIGUOUS`, `BLOCKED`, and unknown statuses cannot enter fallback.

Producer deterministic result: `S31-C PASS 28/28`.

S31-A artifacts are unchanged from the prior review, where S31-A was independently marked PASS; nevertheless derive the new bundle verdict from the exact frozen bundle and current Quality Pack rules.

## Canonical Quality Pack refs

Use the exact refs embedded in the bundle, frozen to `main@d4051d9c57fdfd09741da5ba2718c032eac56c92`.

## Review obligations

Evaluate every acceptance and blocking criterion in the frozen bundle. In particular, attempt to falsify the three prior repairs:

- supply/misbind evidence for a different executed SHA;
- bypass the resolver/digest boundary for EKB or currentness;
- let the worker self-resolve governed evidence;
- enter fallback from `RESOLVED`, `AMBIGUOUS`, `BLOCKED`, or unknown status.

Preserve per-lane disposition as an extension inside `quality_review`:

```json
"s31_lane_reviews": {
  "S31-A": {"verdict": "PASS|FAIL|BLOCKED", "findings": []},
  "S31-B": {"verdict": "PASS|FAIL|BLOCKED", "findings": []},
  "S31-C": {"verdict": "PASS|FAIL|BLOCKED", "findings": []}
}
```

This extension does not replace the canonical Quality Pack verdict, score, evidence map, blocking codes, repair actions, remaining risks or next gate.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@d4051d9c57fdfd09741da5ba2718c032eac56c92/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required execution metadata:

- `receipt_version = v0.1`
- `execution_mode = INDEPENDENT_CHAT_CONTEXT`
- `semantic_status = EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id = S31-ABC-IR-002`
- `reviewer_is_producer = false`
- `producer_context_available = false`
- `external_paid_model_used = false`
- `automated_semantic_judge_implemented = false`
- `review_completed = true` only after completing the review

`source_bundle.artifact_ref` and `source_bundle.artifact_sha_or_digest` must equal the frozen bundle ref and SHA above. Populate the remaining source bundle fields from the exact Quality Pack refs embedded in the bundle. Set `quality_review.reviewed_artifact` to the frozen bundle ref and derive `quality_review.next_gate` from the actual findings; do not assume PASS.

After receipt generation, validate it with the frozen Quality Pack validator. A valid wrapper proves only that the independent semantic review was executed in the required boundary; it does not authorize runtime, Golden, merge, production or behavioral promotion.
