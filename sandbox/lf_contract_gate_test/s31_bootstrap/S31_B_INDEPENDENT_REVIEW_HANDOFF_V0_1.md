# S31-B Independent Semantic Review Handoff v0.1

Review case: `S31-B-IR-003`
Review mode: `INDEPENDENT_CHAT_CONTEXT`

Operate in a clean independent context. The reviewer must not be the producer, must not use producer conclusions as semantic proof, must not repair artifacts while reviewing, and must not authorize merge, Golden, runtime, production, or behavioral promotion.

## Frozen bundle
Review exactly:
`github://cristhianlujan/claude-persona-lf-patch@154cbffc4f91a4cf65a8ff54cd51e26d3e84d90a/sandbox/lf_contract_gate_test/s31_bootstrap/s31_b_independent_review_bundle_v0_1.json`

Expected bundle Git blob SHA:
`0fc29bc85469917bc13f3cbd25b7edbd201307a1`

Frozen repaired candidate snapshot:
`191b53fca993bf28aefccf5e1e67007ad9a35dfa`

Base main/current Quality Pack reference:
`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

Do not substitute branch HEAD, PR merge ref, later candidate, prior ABC bundle, or another scope. S31-A and S31-C already received independent PASS in IR-002 and are outside this review.

## Prior independent finding
`S31-ABC-IR-002` blocked only S31-B with:
- `S31_B_TRUSTED_RESOLVER_BOUNDARY_NOT_ENFORCED`
- `S31_B_SELF_RESOLVER_IDENTITY_SPOOFABLE`
- `S31_B_EKB_CURRENTNESS_EVIDENCE_REMAINS_SELF_CERTIFIABLE`

The frozen bundle includes a producer intake record and deterministic repair trace as provenance only. They are not semantic proof.

## Mandatory falsification
Attempt at minimum:
1. caller-supplied lambda/callback/local mapping as resolver;
2. fake resolver object with a trusted-looking `resolver_id` alias;
3. unsupported/fake immutable ref;
4. correct-format but wrong SHA-256 for provider bytes;
5. validation receipt from a different commit/revision;
6. currentness receipt whose ref is not exact executed branch HEAD;
7. EKB freshness/final readback minted by producer-controlled evidence;
8. anti-close regression: safe work/count/batch/frontier inconsistencies.

A PASS is allowed only if resolver authority is established outside candidate fields, refs are provider-bound immutable refs, SHA-256 is recomputed from provider bytes, currentness is resolver-derived, and producer-controlled callbacks cannot create governed PASS.

## Required output
Return exactly one JSON object valid against:
`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:
- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S31-B-IR-003`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `external_paid_model_used=false`
- `automated_semantic_judge_implemented=false`
- `review_completed=true` only after completion
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@154cbffc4f91a4cf65a8ff54cd51e26d3e84d90a/sandbox/lf_contract_gate_test/s31_bootstrap/s31_b_independent_review_bundle_v0_1.json`
- `source_bundle.artifact_sha_or_digest=0fc29bc85469917bc13f3cbd25b7edbd201307a1`
- `quality_review.reviewed_artifact=github://cristhianlujan/claude-persona-lf-patch@154cbffc4f91a4cf65a8ff54cd51e26d3e84d90a/sandbox/lf_contract_gate_test/s31_bootstrap/s31_b_independent_review_bundle_v0_1.json`

Populate Quality Pack refs from the frozen bundle, derive verdict/score/findings independently, validate the final receipt with the frozen Quality Pack validator, and return only the final JSON receipt.
