# S31 A/B/C — Independent Review Handoff v0.3

Status: REVIEW-READY / QUALITY-PACK-BOUND / NO SELF-CERTIFICATION
Strategy: S31 — LF Reusable Capability & Governed Development Platform
Review scope: S31-A, S31-B, S31-C only

## Execution boundary

Execute only in a clean reviewer context that did not produce S31. The reviewer must use `INDEPENDENT_CHAT_CONTEXT`, must not repair artifacts while reviewing, and must not authorize Golden, merge or production.

The producer provides no semantic target verdict. Deterministic producer receipts may be inspected only as evidence of executed deterministic checks; they are not semantic proof.

## Frozen review artifact

Review exactly this immutable bundle:

- `artifact_ref`: `github://cristhianlujan/claude-persona-lf-patch@50b343b8b56e1c7f5ac5497151f9ab11cd7e26a0/sandbox/lf_contract_gate_test/s31_bootstrap/s31_abc_independent_review_bundle_v0_3.json`
- `artifact_sha_or_digest`: `3042fb6fcc14fea7d2223d91af18c211ada6a94f`
- candidate snapshot inside the bundle: `0a6bc06dfb83958730b2d659d26098686d873f9b`
- base main: `d4051d9c57fdfd09741da5ba2718c032eac56c92`

The bundle contains the frozen S31-A/B/C artifact refs, deterministic evidence refs, acceptance criteria, blocking criteria and governance constraints.

## Canonical Quality Pack refs

Use the refs embedded in the bundle. They are frozen to `main@d4051d9c57fdfd09741da5ba2718c032eac56c92`, including:

- `profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md`
- `profiles/quality_pack/contracts/quality_gate_contract.md`
- `profiles/quality_pack/contracts/lf_quality_controls.md`
- `profiles/quality_pack/judges/quality_pack_score_rubric.md`
- `profiles/quality_pack/judges/quality_pack_mini_judge.md`
- `profiles/quality_pack/schemas/quality_review.schema.json`
- `profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`
- `profiles/quality_pack/validators/validate_independent_semantic_review.py`

## Review obligations

Evaluate every acceptance and blocking criterion in the frozen bundle. In addition to the canonical Quality Pack evidence map, preserve per-lane disposition in an extension field inside `quality_review`:

```json
"s31_lane_reviews": {
  "S31-A": {"verdict": "PASS|FAIL|BLOCKED", "findings": []},
  "S31-B": {"verdict": "PASS|FAIL|BLOCKED", "findings": []},
  "S31-C": {"verdict": "PASS|FAIL|BLOCKED", "findings": []}
}
```

This extension does not replace the canonical Quality Pack `verdict`, score, evidence map, blocking codes, repair actions, remaining risks or next gate.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@d4051d9c57fdfd09741da5ba2718c032eac56c92/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required execution metadata includes:

- `receipt_version = v0.1`
- `execution_mode = INDEPENDENT_CHAT_CONTEXT`
- `semantic_status = EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id = S31-ABC-IR-001`
- `reviewer_is_producer = false`
- `producer_context_available = false`
- `external_paid_model_used = false`
- `automated_semantic_judge_implemented = false`
- `review_completed = true` only after completing the review

`source_bundle.artifact_ref` and `source_bundle.artifact_sha_or_digest` must equal the frozen bundle ref and SHA above. Populate the remaining `source_bundle` fields from the exact Quality Pack refs embedded in the bundle.

Set `quality_review.reviewed_artifact` to the frozen bundle ref. `quality_review.next_gate` must describe the actual next gate produced by the review; do not assume PASS.

After receipt generation, validate it deterministically with the frozen Quality Pack validator. A valid wrapper proves only that the independent semantic review was executed in the required boundary; it does not authorize runtime, Golden, merge, production or behavioral promotion.
