# S31-DG Independent Semantic Review Handoff v0.3

Review case: `S31-DG-IR-003`
Review mode: `INDEPENDENT_CHAT_CONTEXT`

Operate in a clean independent context. The reviewer must not be the producer, must not repair during review, must not use producer deterministic PASS as semantic proof, and must not authorize runtime, Golden, merge, production, or behavioral promotion.

## Frozen bundle
Review exactly:
`github://cristhianlujan/claude-persona-lf-patch@154cbffc4f91a4cf65a8ff54cd51e26d3e84d90a/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_5.json`

Expected bundle Git blob SHA:
`592e4c2821d5fc7e6c88c2ffd265ec9ea758cb70`

Frozen repaired candidate snapshot:
`191b53fca993bf28aefccf5e1e67007ad9a35dfa`

Base main/current Quality Pack reference:
`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

Do not substitute branch HEAD, PR merge SHA, later snapshot, or prior DG bundle.

## Prior independent finding
`S31-DG-IR-002` returned `BLOCK_PIPELINE` with:
- `SELF_RESOLVED_EVIDENCE`
- `UNRESOLVED_CURRENTNESS`
- `EVIDENCE_INFLATION`
- `AUTHORITY_LEAK`

The bundle preserves producer intake/repair claims only as provenance. Re-derive the semantic verdict from frozen artifacts.

## Mandatory review scope and attacks
### S31-D
Verify authority/runtime-schema source bytes are resolved through the canonical Quality Pack trusted resolver, SHA-256 is recomputed from bytes, current content is enforced, resolver aliases/callbacks cannot pass, and cross-run declaration remains fail-closed.
Attack arbitrary resolver callback, alias `resolver_id`, fake ref, wrong provider digest, changed historical source, and undeclared cross-run authority.

### S31-E
Verify every source ref is independently resolved and rehashed, currentness is not receipt-echoed self-certification, lifecycle remains `lifecycle` (not `lifecycle_state`), and duplicate dependency/source drift still fails closed.

### S31-F
Verify owner receipt is independently resolved even at STRUCTURAL level; input/output exact digests are recomputed; authority/provenance sources are resolver-derived; and all non-structural receipts are cross-bound to the same run, capability/gate, execution, input/output digests, authority source/digest/revision, and provenance identity.
Attack replay/composition using valid receipts from another run, capability, execution, payload, authority revision, or provenance set.

### S31-G
Verify Typed Context is resolved/rehashed before provider invocation, is current and schema-valid, and binds request_id + governed_input to the resolved context. Attack fake context ref, wrong digest, stale/changed context, request mismatch, governed-input mismatch, arbitrary callback, nested authority flags/effects, and silent fallback.

## Required output
Return exactly one JSON object valid against:
`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:
- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S31-DG-IR-003`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@154cbffc4f91a4cf65a8ff54cd51e26d3e84d90a/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_5.json`
- `source_bundle.artifact_sha_or_digest=592e4c2821d5fc7e6c88c2ffd265ec9ea758cb70`
- `quality_review.reviewed_artifact=github://cristhianlujan/claude-persona-lf-patch@154cbffc4f91a4cf65a8ff54cd51e26d3e84d90a/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_5.json`

Preserve per-lane D/E/F/G dispositions as an extension in `quality_review`, derive verdict/score/findings independently, validate the final receipt with the frozen Quality Pack validator, and return only the final JSON receipt.
