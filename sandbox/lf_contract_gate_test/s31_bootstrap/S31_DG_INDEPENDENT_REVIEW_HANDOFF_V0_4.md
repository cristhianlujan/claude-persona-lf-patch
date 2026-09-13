# S31-DG Independent Semantic Review Handoff v0.4

Review case: `S31-DG-IR-004`  
Review mode: `INDEPENDENT_CHAT_CONTEXT`

Operate in a clean independent context. Do not use producer conclusions, deterministic PASS results, prior conversation memory, PR merge refs, branch HEAD, later snapshots, or moving `main` as semantic proof.

The reviewer must not repair during review and must not authorize runtime, Golden, merge, production, scheduler activation, or behavioral promotion.

## Frozen bundle

Review exactly:

`github://cristhianlujan/claude-persona-lf-patch@761b7da0cbea0de983d66334216055b09b015bd9/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_6.json`

Expected bundle Git blob SHA:

`5ff1802766f550565e384b0728a1b9b62f9e3172`

Frozen repaired candidate snapshot:

`3e5e542f2109e64ba319d2686278b1036bf69771`

Deterministic producer receipt:

`github://cristhianlujan/claude-persona-lf-patch@028169c5d6617723f9eda196ce5a756e5ef962d0/sandbox/lf_contract_gate_test/s31_bootstrap/s31_ir003_repair_receipt_v0_1.json`

Immutable comparison base:

`e75cab6e71c0f880f72726439e952de78ea4931f`

Frozen Quality Pack reference:

`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

Do not substitute PR #749 merge SHA, the current branch head, a later commit, prior DG bundle, or a different Quality Pack revision.

## Review objective

Attempt to falsify the repaired D-G boundary. Producer deterministic evidence is provenance only; independently derive the semantic verdict.

### S31-D — no-regression
Verify trusted immutable authority/runtime-schema resolution remains enforced, provider bytes are rehashed, currentness cannot be caller-self-certified, resolver aliases/callbacks cannot pass, and cross-run authority declaration remains fail-closed.

### S31-E — no-regression
Verify capability source bytes remain provider-resolved and rehashed, registry currentness remains non-self-certifiable, lifecycle remains canonical, and duplicate/source drift remains fail-closed.

### S31-F — replay/composition hardening
Verify:
- STRUCTURAL owner receipt binds to the envelope capability;
- execution receipt remains bound to `executed_sha`;
- every non-structural execution/authority/provenance receipt requires `S31_F_CROSS_BINDING_V0_1`;
- the common semantic digest binds run, capability, execution, input/output digests, authority identity and provenance identity;
- valid but unbound receipts cannot be replayed or composed;
- same-content historical source identity substitution cannot bypass the common binding;
- immutable historical source refs are not incorrectly rejected merely because repository HEAD moved.

Mandatory attacks:
`F_OWNER_CAPABILITY_MISMATCH`,
`F_VALID_AUTHORITY_RECEIPT_REPLAY_WITHOUT_COMMON_BINDING`,
`F_VALID_PROVENANCE_RECEIPT_REPLAY_WITHOUT_COMMON_BINDING`,
`F_SAME_CONTENT_INPUT_IDENTITY_SUBSTITUTION`,
`F_SAME_CONTENT_AUTHORITY_IDENTITY_SUBSTITUTION`,
`F_SAME_CONTENT_PROVENANCE_IDENTITY_SUBSTITUTION`.

### S31-G — governed Typed Context boundary
Verify the exact Typed Context artifact is resolved and rehashed before provider invocation and its governed internals are semantically revalidated before runtime admission.

Mandatory attacks:
- a correct outer Typed Context hash containing invalid nested authority/currentness evidence;
- untrusted resolver type;
- fake/stale Typed Context reference or digest;
- request/governed-input mismatch;
- nested authority effect;
- silent fallback.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:
- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S31-DG-IR-004`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@761b7da0cbea0de983d66334216055b09b015bd9/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_6.json`
- `source_bundle.artifact_sha_or_digest=5ff1802766f550565e384b0728a1b9b62f9e3172`
- `quality_review.reviewed_artifact=github://cristhianlujan/claude-persona-lf-patch@761b7da0cbea0de983d66334216055b09b015bd9/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_6.json`

Preserve per-lane D/E/F/G dispositions as an extension in `quality_review`, derive verdict/score/findings independently, validate the final receipt with the frozen Quality Pack validator, and return only the final JSON receipt.
