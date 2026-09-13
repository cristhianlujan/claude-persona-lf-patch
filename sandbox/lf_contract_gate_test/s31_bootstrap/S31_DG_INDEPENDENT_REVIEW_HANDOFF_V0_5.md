# S31-DG Independent Semantic Review Handoff v0.5

Review case: `S31-DG-IR-005`  
Review mode: `INDEPENDENT_CHAT_CONTEXT`

Operate in a clean independent context. Do not use producer conclusions, producer governance disposition, deterministic PASS results, prior conversation memory, PR merge refs, branch HEAD, later snapshots, or moving `main` as semantic proof.

The reviewer must not repair during review and must not authorize runtime, Golden, merge, production, scheduler activation, or behavioral promotion.

## Frozen bundle

Review exactly:

`github://cristhianlujan/claude-persona-lf-patch@43efdc3afe7da87d739e15e38d3238f8ac28cbbd/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_7.json`

Expected bundle Git blob SHA:

`7960553e4db4ce62523a028f8187b03b0798dc7f`

Frozen repaired candidate snapshot:

`7f7b844b878ad44c584c6aebcbf63e89d4b10b66`

Deterministic producer repair receipt:

`github://cristhianlujan/claude-persona-lf-patch@594783d2465d8216255f38da7a257935af5b9c5c/sandbox/lf_contract_gate_test/s31_bootstrap/s31_ir004_repair_receipt_v0_1.json`

Producer governance disposition recommendation:

`github://cristhianlujan/claude-persona-lf-patch@594783d2465d8216255f38da7a257935af5b9c5c/sandbox/lf_contract_gate_test/s31_bootstrap/s31_ir004_governance_disposition_v0_1.json`

Prior independent IR-004 receipt:

`github://cristhianlujan/claude-persona-lf-patch@3bc25ab79d9a971f3b745645f3b167aa76212f45/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_ir004_independent_receipt_v0_1.json`

Immutable comparison base:

`39da3d36384af49ed1dcfa0ba01514c269a90e55`

Frozen Quality Pack reference:

`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

Do not substitute PR #751 merge SHA, the current branch head, a later commit, a prior DG bundle, or a different Quality Pack revision.

## Review objective

Attempt to falsify the repaired D-G boundary after IR-004. Producer deterministic evidence and producer governance disposition are provenance only; independently derive the semantic verdict and restrictions.

### S31-D — no-regression
Verify trusted immutable authority/runtime-schema resolution remains enforced, provider bytes are rehashed, currentness cannot be caller-self-certified, resolver aliases/subclasses/callbacks cannot pass, and cross-run authority declaration remains fail-closed.

### S31-E — no-regression and pin completeness
Verify capability source bytes remain provider-resolved and rehashed, registry currentness remains non-self-certifiable, lifecycle/duplicate/source-drift protections remain intact, and every load-bearing D/E dependency actually used in the review is frozen by exact blob SHA.

The IR-004 review identified four previously unpinned load-bearing artifacts. Independently verify that bundle v0.7 pins them with the exact candidate bytes and check for any additional load-bearing artifact omitted by the new bundle.

### S31-F — claim-tier binding hardening
Verify all prior replay/composition protections remain intact and independently verify the IR-004 repair:
- non-structural receipts require `S31_F_CROSS_BINDING_V0_2`;
- the common semantic identity binds `evidence_level` and `claim_ceiling` in addition to run, capability, execution, input/output, authority and provenance identities;
- every resolved non-structural receipt carries resolver-bound `evidence_level` and `claim_ceiling` matching the envelope;
- an identical resolved receipt set cannot be recomposed at a higher claim tier under an unchanged binding;
- claim-tier receipt-field substitution cannot bypass the binding;
- same-content identity substitution remains fail-closed;
- historical immutable refs are not forced to equal repository HEAD merely because they are historical.

Mandatory attacks include:
`F_CLAIM_LEVEL_ESCALATION_UNDER_IDENTICAL_BINDING`,
`F_CLAIM_TIER_RECEIPT_FIELD_SUBSTITUTION`,
`F_OWNER_CAPABILITY_MISMATCH`,
`F_VALID_AUTHORITY_RECEIPT_REPLAY_WITHOUT_COMMON_BINDING`,
`F_VALID_PROVENANCE_RECEIPT_REPLAY_WITHOUT_COMMON_BINDING`,
`F_SAME_CONTENT_INPUT_IDENTITY_SUBSTITUTION`,
`F_SAME_CONTENT_AUTHORITY_IDENTITY_SUBSTITUTION`,
`F_SAME_CONTENT_PROVENANCE_IDENTITY_SUBSTITUTION`.

Independently rederive the expected common semantic digest from provider-resolved bytes and fields; do not trust the producer value.

### S31-G — governed Typed Context boundary
Verify the exact Typed Context artifact is resolved and rehashed before provider invocation and its governed internals are semantically revalidated before runtime admission. Re-run adversarial cases for invalid nested authority/currentness, untrusted resolver type, fake/stale refs or digests, request/governed-input mismatch, nested authority effects, weakened forbidden-authority set, and silent fallback.

### Currentness durability restriction
IR-004 observed that historical source refs can become unresolvable after lawful HEAD evolution or deletion. The candidate intentionally preserves the conservative fail-closed resolver behavior and does not implement an archival currentness mechanism in this repair. Independently determine whether this is an acceptable documented durability restriction for this candidate or whether it must block the next governance gate. Do not inherit the producer recommendation as your verdict, and do not weaken the resolver during review.

### Bundle integrity
Verify the bundle blob itself, all 32 declared frozen artifact pins, candidate lineage, the prior independent receipt pin, the repair receipt/disposition pins, and completeness of the dependency walk actually used by your review. A producer-declared 32/32 match is not semantic proof.

The unrelated shared migration-source parity failure is outside this exclusive S31 repair lane. Do not treat it as repair evidence, and do not import shared migrations into the frozen candidate.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:
- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S31-DG-IR-005`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@43efdc3afe7da87d739e15e38d3238f8ac28cbbd/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_7.json`
- `source_bundle.artifact_sha_or_digest=7960553e4db4ce62523a028f8187b03b0798dc7f`
- `quality_review.reviewed_artifact=github://cristhianlujan/claude-persona-lf-patch@43efdc3afe7da87d739e15e38d3238f8ac28cbbd/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_independent_review_bundle_v0_7.json`

Preserve per-lane D/E/F/G dispositions as an extension in `quality_review`, derive verdict/score/findings independently, explicitly disposition the currentness durability restriction and bundle completeness, validate the final receipt with the frozen Quality Pack validator, and return only the final JSON receipt.
