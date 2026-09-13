# S26 Matrix v3 F10-O5 R2 — Independent Review Handoff

Execute this review in a **new clean chat/context** that did not produce the artifact. Do not use producer conversation, memory, prior F10 receipts, prior semantic verdicts, or expected outcomes as evidence.

Review exactly one frozen artifact:
- `review_case_id`: `S26V3-F10-O5-REAL-E2E-HOLDOUT-R2-CURRENTMAIN-3B39657F`
- `matrix_case_id`: `S26V3-F10-O5-REAL-E2E-HOLDOUT`
- `final_candidate_sha`: `3b39657fbf14f29c7839ecb26d715ed5c6fad59e`
- `artifact_canonical_sha256`: `1d5cf010068c667bd44f5a6c66ac13869c7042e2e70a271b005cec43e64b5c91`
- frozen bundle: `github://cristhianlujan/claude-persona-lf-patch@ff603d81d4e8e6ddca0cd5fe8035a862bab6a300/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_golden_currentmain_20260913/w3_repair/review_bundle_S26V3-F10-O5-REAL-E2E-HOLDOUT-R2`

Read only the five files inside that frozen bundle plus the exact immutable source references listed in `review_case.json`. Treat `producer_validation_receipt.json` only as producer-side provenance/execution evidence; it is **not** a semantic verdict and must not bias the review.

Apply the canonical independent-chat contract at:
`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md`

Validate the semantic artifact against the exact input requirement in `review_case.json` and the immutable Quality Pack contracts/rubric/schema referenced there. Do not repair or modify any artifact.

Return **only one JSON object** matching:
`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required execution metadata if the review truly ran independently:
- `receipt_version`: `v0.1`
- `execution_mode`: `INDEPENDENT_CHAT_CONTEXT`
- `semantic_status`: `EXECUTED_INDEPENDENT_CONTEXT`
- `review_case_id`: `S26V3-F10-O5-REAL-E2E-HOLDOUT-R2-CURRENTMAIN-3B39657F`
- `reviewer_is_producer`: `false`
- `producer_context_available`: `false`
- `external_paid_model_used`: `false`
- `automated_semantic_judge_implemented`: `false`
- `review_completed`: `true`

If independence conditions are not true, return `review_completed=false` and `semantic_status=NOT_EXECUTED`; do not fabricate independence.
