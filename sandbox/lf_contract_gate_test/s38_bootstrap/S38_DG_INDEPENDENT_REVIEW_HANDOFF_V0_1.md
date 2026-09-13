# S38-DG Independent Semantic Review Handoff v0.1

Review case: `S38-DG-IR-005`  
Review mode: `INDEPENDENT_CHAT_CONTEXT`

## Identity and lineage

The active strategy identifier is **S38**. This work was historically created under S31 before a strategy-id collision was discovered. The earlier S31 keeps its identifier; this later strategy was renumbered to S38.

Historical S31 receipts, bundles, handoffs, branch names, paths, SHAs and protocol version identifiers are immutable lineage evidence and MUST NOT be rewritten. In particular, identifiers such as `S31_F_CROSS_BINDING_V0_2` are protocol-version names, not the active strategy id.

The prepared pre-rename `S31-DG-IR-005` package was superseded before independent execution. Review iteration continuity is preserved: this review remains iteration **IR-005**, now under S38.

Operate in a clean independent context. Do not use producer conclusions, producer governance disposition, deterministic PASS results, prior conversation memory, PR merge refs, branch HEAD, later snapshots, or moving `main` as semantic proof.

The reviewer must not repair during review and must not authorize runtime, Golden, merge, production, scheduler activation, or behavioral promotion.

## Frozen S38 bundle

Review exactly:

`github://cristhianlujan/claude-persona-lf-patch@daa80cba61f7af5d12757c092bdb058fd35eb69f/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_1.json`

Expected bundle Git blob SHA:

`b20d30ca2649bb613f621d735c28b3109db08ca5`

Frozen S38 candidate snapshot:

`ff9b17153f57b65612419d28514041965abaaf2d`

Implementation ancestor carrying the S31-DG IR-004 semantic repair:

`7f7b844b878ad44c584c6aebcbf63e89d4b10b66`

Historical S31 packaging head before renumbering:

`f323727a45d8d9697fcf6e63f71876e5ef4fff70`

Immutable comparison base:

`39da3d36384af49ed1dcfa0ba01514c269a90e55`

Frozen Quality Pack reference:

`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

Do not substitute the current branch head, any PR merge SHA, moving `main`, the superseded S31 IR-005 package, or a different Quality Pack revision.

## Review objective

Attempt to falsify the repaired D-G boundary and the identity-transition integrity. Producer evidence is provenance only; independently derive the semantic verdict and restrictions.

### S38-IDENTITY — rename integrity

Verify that:
- active forward strategy identity is S38;
- historical strategy identity S31 is preserved only as immutable lineage;
- the renumbering did not rewrite historical frozen artifacts;
- the pre-rename S31-DG-IR-005 package is treated as superseded-before-execution, not as an independent review result;
- review iteration continuity remains IR-005;
- no semantic, runtime, authority, Golden or production change was introduced by the rename itself.

### S38-D — no-regression

Verify trusted immutable authority/runtime-schema resolution remains enforced, provider bytes are rehashed, currentness cannot be caller-self-certified, resolver aliases/subclasses/callbacks cannot pass, and cross-run authority declaration remains fail-closed.

### S38-E — no-regression and pin completeness

Verify capability source bytes remain provider-resolved and rehashed, registry currentness remains non-self-certifiable, lifecycle/duplicate/source-drift protections remain intact, and every load-bearing D/E dependency used in the review is frozen by exact blob SHA.

### S38-F — claim-tier binding hardening

Verify all prior replay/composition protections and the IR-004 repair:
- non-structural receipts require immutable protocol version `S31_F_CROSS_BINDING_V0_2`;
- common semantic identity binds `evidence_level` and `claim_ceiling` plus run, capability, execution, input/output, authority and provenance identities;
- every resolved non-structural receipt carries resolver-bound evidence/claim tier matching the envelope;
- identical resolved receipts cannot be recomposed at a higher claim tier under an unchanged binding;
- receipt-field substitution cannot bypass the binding;
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

Independently rederive the common semantic digest from provider-resolved bytes and fields; do not trust the producer value.

### S38-G — governed Typed Context boundary

Verify the exact Typed Context artifact is resolved and rehashed before provider invocation and governed internals are semantically revalidated before runtime admission. Re-run adversarial cases for invalid nested authority/currentness, untrusted resolver type, fake/stale refs or digests, request/governed-input mismatch, nested authority effects, weakened forbidden-authority set, and silent fallback.

### Currentness durability restriction

The historical lineage observed that lawful HEAD evolution/deletion can make historical source refs unresolvable. The candidate preserves conservative fail-closed behavior and does not add archival currentness in this rename. Independently determine whether this documented durability restriction is acceptable or must block the next governance gate. Do not weaken the resolver during review.

### Bundle integrity

Verify the bundle blob itself, all **34** frozen artifact pins, S38 identity-transition pins, candidate lineage, prior independent receipt pin, repair receipt/disposition pins, and completeness of the dependency walk actually used by the review.

The unrelated shared migration-source parity failure is outside this exclusive S38 lane. Do not import shared migrations into the frozen candidate.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:
- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S38-DG-IR-005`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@daa80cba61f7af5d12757c092bdb058fd35eb69f/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_1.json`
- `source_bundle.artifact_sha_or_digest=b20d30ca2649bb613f621d735c28b3109db08ca5`
- `quality_review.reviewed_artifact=github://cristhianlujan/claude-persona-lf-patch@daa80cba61f7af5d12757c092bdb058fd35eb69f/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_1.json`

Preserve per-lane S38-D/E/F/G and S38-IDENTITY dispositions as extensions in `quality_review`, derive verdict/score/findings independently, explicitly disposition currentness durability and bundle completeness, validate the final receipt with the frozen Quality Pack validator, and return only the final JSON receipt.
