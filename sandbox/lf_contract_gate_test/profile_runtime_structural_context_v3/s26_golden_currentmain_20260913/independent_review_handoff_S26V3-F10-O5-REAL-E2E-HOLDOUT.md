# S26 Matrix v3 W3 — Independent Review Handoff

Execute this review in a **new clean chat/context** that did not produce the artifact. Do not use this producer conversation, any previous semantic verdict, or any expected outcome as evidence.

Review exactly one frozen artifact:
- `review_case_id`: `S26V3-F10-O5-REAL-E2E-HOLDOUT-CURRENTMAIN-3B39657F`
- `matrix_case_id`: `S26V3-F10-O5-REAL-E2E-HOLDOUT`
- `final_candidate_sha`: `3b39657fbf14f29c7839ecb26d715ed5c6fad59e`
- `artifact_canonical_sha256`: `4ded363a85f7edc890c62e3373aba1353d3d9012cebbe83dd3c94c4e9d5b39a5`
- frozen bundle: `github://cristhianlujan/claude-persona-lf-patch@5d6145be846f0c10faa2f4c887f4555be5cce787/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_golden_currentmain_20260913/w3_producer/review_bundle_S26V3-F10-O5-REAL-E2E-HOLDOUT`

Read only the five files inside that frozen bundle plus the exact immutable source references listed in `review_case.json`. Treat `producer_validation_receipt.json` only as producer-side execution evidence; it is **not** a semantic verdict and must not bias the review.

Apply the canonical independent-chat contract at:
`github://cristhianlujan/claude-persona-lf-patch@5d6145be846f0c10faa2f4c887f4555be5cce787/profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md`

Validate the semantic artifact using the immutable Quality Pack contracts/rubric/schema referenced by `review_case.json`. Do not repair or modify the artifact.

Return **only one JSON object** matching:
`github://cristhianlujan/claude-persona-lf-patch@5d6145be846f0c10faa2f4c887f4555be5cce787/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required execution metadata if the review truly ran independently:
- `receipt_version`: `v0.1`
- `execution_mode`: `INDEPENDENT_CHAT_CONTEXT`
- `semantic_status`: `EXECUTED_INDEPENDENT_CONTEXT`
- `review_case_id`: `S26V3-F10-O5-REAL-E2E-HOLDOUT-CURRENTMAIN-3B39657F`
- `reviewer_is_producer`: `false`
- `producer_context_available`: `false`
- `external_paid_model_used`: `false`
- `automated_semantic_judge_implemented`: `false`
- `review_completed`: `true`

If the independence conditions are not true, return `review_completed=false` and `semantic_status=NOT_EXECUTED`; do not fabricate independence.
