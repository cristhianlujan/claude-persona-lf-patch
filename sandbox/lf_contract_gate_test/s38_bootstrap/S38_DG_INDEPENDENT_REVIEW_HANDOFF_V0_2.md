# S38 D–G Independent Semantic Review Handoff v0.2

Review case: `S38-DG-IR-006`  
Review mode: `INDEPENDENT_CHAT_CONTEXT`

This review follows the completed historical `S31-DG-IR-005` review and the controlled strategy identity transition from historical S31 to active S38. The previously published `S38-DG-IR-005` package was superseded before execution and must not be used.

Operate in a clean independent context. Do not use producer conclusions, producer governance disposition, deterministic PASS results, prior conversation memory, PR merge refs, branch HEAD, later snapshots, moving `main`, or the superseded S38 IR-005 package as semantic proof.

Do not repair or modify any artifact during review. Do not authorize runtime, Golden, merge, production, scheduler activation, or behavioral promotion.

## Frozen bundle

Review exactly:

`github://cristhianlujan/claude-persona-lf-patch@21094d2b4ad4781ea80f79ac43c3c7b043ddf760/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_2.json`

Expected bundle Git blob SHA:

`3991ba4b335305da3d4e2f96f231d5346c5c0bdb`

Frozen repaired candidate snapshot:

`e7565583c57b8c5d6abfa7c36a8307d4eedb1bee`

Immutable comparison base:

`01f53ca5fb3d4d060e482fce64bddaeb1c383eae`

Historical independent review receipt that triggered this repair:

`github://cristhianlujan/claude-persona-lf-patch@007d4f43176f1b5b5fe17401eb531856d2ae2537/sandbox/lf_contract_gate_test/s31_bootstrap/s31_dg_ir005_independent_receipt_v0_1.json`

Expected historical receipt Git blob SHA:

`92d18d5eefbc108668c64bccd16ad21203a45265`

Producer repair evidence, provenance only:

`github://cristhianlujan/claude-persona-lf-patch@488c9cc48316e901e3f699a71cf9c4c7db657341/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir006_repair_receipt_v0_2.json`

Expected repair receipt Git blob SHA:

`64869cde84778e312b6314ae5c4d46c935f9b0fa`

Producer governance disposition, provenance only:

`github://cristhianlujan/claude-persona-lf-patch@488c9cc48316e901e3f699a71cf9c4c7db657341/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir005_governance_disposition_v0_2.json`

Expected disposition Git blob SHA:

`6e7fb3a9fbf1d5753e3d430cd4cac05ec64d46a9`

Frozen Quality Pack reference:

`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

Do not substitute PR #757 merge refs, current branch HEAD, another bundle, a later commit, the superseded S38 IR-005 package, or a different Quality Pack revision.

## Review objective

Attempt to falsify the S38 repair of the three blocking restrictions found by historical `S31-DG-IR-005`, while independently checking D/E/F/G no-regression and the declared/enforced F contract surface.

Producer evidence is provenance only. Independently derive every semantic verdict, restriction, score and next-gate disposition.

### A. Governed repository trust anchor

The historical IR-005 falsified the old resolver because a caller could supply a genuine resolver class rooted in an attacker-controlled clone and obtain PASS over forged bytes.

Independently determine whether `S38_GOVERNED_REF_RESOLVER_V2` closes that boundary. In particular verify that:

- the caller cannot select the authoritative repository root;
- the resolver's artifact checkout HEAD must be fetchable from the canonical governed GitHub repository;
- the resolver module and trust-policy bytes are independently compared with canonical remote bytes at that artifact HEAD;
- evidence revisions and bytes come from the canonical remote rather than a caller-controlled clone;
- global/system Git configuration or URL rewrite tricks cannot silently redirect canonical fetches;
- a legacy resolver rooted at an attacker clone with forged evidence fails closed;
- local tampering of the new S38 resolver module fails closed;
- an unpublished or non-canonical evidence revision fails closed.

Mandatory attacks include:
`RESOLVER_ROOT_ATTACKER_CLONE_FORGED_BYTES`,
`RESOLVER_MODULE_LOCAL_TAMPER_WITH_CANONICAL_HEAD`,
`RESOLVER_CANONICAL_REMOTE_REVISION_NOT_PUBLISHED`.

Do not accept type identity alone, origin-slug strings alone, or producer statements as proof of repository identity.

### B. Earned claim tier

Historical IR-005 established that the previous binding prevented recomposition of an existing receipt set but did not prevent a producer from authoring a fresh internally consistent SEMANTIC or BEHAVIORAL set.

Independently verify that the S38 candidate derives the admissible tier from policy rather than trusting producer-authored tier fields. Specifically verify:

- without an allowlisted independent witness, the maximum earned tier is `PROVENANCE_EXECUTION`;
- fresh self-consistent `SEMANTIC` receipts cannot elevate the earned tier;
- fresh self-consistent `BEHAVIORAL` receipts cannot elevate the earned tier;
- fake, producer-authored, malformed or unallowlisted witness material cannot raise the tier;
- if an allowlisted witness path is exercised, independence and witness ceiling are enforced from provider-resolved evidence rather than caller strings;
- prior F replay, substitution, owner-capability, execution-revision and common-binding protections remain fail-closed.

Mandatory attacks include:
`CLAIM_TIER_FRESH_SELF_AUTHORED_SEMANTIC`,
`CLAIM_TIER_FRESH_SELF_AUTHORED_BEHAVIORAL`,
`CLAIM_TIER_FAKE_UNALLOWLISTED_WITNESS`,
`F_OWNER_CAPABILITY_MISMATCH`,
`F_VALID_AUTHORITY_RECEIPT_REPLAY_WITHOUT_COMMON_BINDING`,
`F_VALID_PROVENANCE_RECEIPT_REPLAY_WITHOUT_COMMON_BINDING`,
`F_SAME_CONTENT_INPUT_IDENTITY_SUBSTITUTION`,
`F_SAME_CONTENT_AUTHORITY_IDENTITY_SUBSTITUTION`,
`F_SAME_CONTENT_PROVENANCE_IDENTITY_SUBSTITUTION`.

Independently rederive any common-binding digest you rely on. Do not trust the producer-declared digest.

### C. Archival currentness

Historical IR-005 found that lawful path evolution could invalidate unchanged historical evidence even while failing closed.

Independently verify that the S38 candidate distinguishes identity/currentness from a moving pathname without weakening safety:

- unchanged bytes at the same governed path remain current;
- lawful rename, move or deletion can remain current only when an exact historical ref + digest is governed as CURRENT by the archival registry;
- registry entries cannot authorize changed bytes, wrong refs or foreign repository material;
- unregistered historical identity remains fail-closed;
- the mechanism does not allow caller self-certification of currentness.

Mandatory attacks include:
`ARCHIVAL_CURRENTNESS_LAWFUL_PATH_RENAME_MOVE_DELETE`,
`ARCHIVAL_CURRENTNESS_UNREGISTERED_IDENTITY`.

### D. Declared vs enforced F contract surface

Historical IR-005 found that the prior v0.4 schema was pinned as a contract surface but not actually executed by the validator.

Independently verify that the S38 v0.5 evidence schema is load-bearing and executed before F semantic admission. At minimum, undeclared envelope surface must fail closed with schema validation rather than be silently ignored.

Mandatory attack:
`DECLARED_SCHEMA_UNKNOWN_SURFACE`.

### E. D/E/F/G no-regression

Re-run the relevant historical boundaries independently. Verify source-byte/provider resolution, non-self-certifiable currentness, owner binding, F cross-binding/replay protection, exact Typed Context resolution, nested Typed Context semantic governance, request/input binding, silent-fallback prohibition and forbidden-authority controls.

Mandatory G attacks include:
`G_INVALID_NESTED_AUTHORITY_WITH_VALID_OUTER_DIGEST`,
`G_UNTRUSTED_RESOLVER_TYPE`,
`G_REQUEST_GOVERNED_INPUT_MISMATCH`,
`G_SILENT_FALLBACK_OR_WEAKENED_FORBIDDEN_AUTHORITY_SET`.

### F. Bundle integrity

Verify independently:

- bundle blob SHA exactly matches `3991ba4b335305da3d4e2f96f231d5346c5c0bdb`;
- candidate lineage is exact and does not use a merge ref;
- all **43 declared frozen artifact pins** match the exact candidate bytes;
- historical S31 IR-005 receipt pin is exact and remains historical S31 evidence;
- producer repair/disposition pins match but are treated only as provenance;
- every load-bearing repository artifact actually exercised by your review is pinned; identify any omission;
- `producer_semantic_verdict` remains null in the frozen bundle.

A producer-declared 43/43 match is not proof. Recompute it independently.

The unrelated shared LF migration-source parity failure is outside this exclusive S38 lane. Do not use it as repair evidence and do not import shared migrations into the frozen candidate.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:

- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S38-DG-IR-006`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@21094d2b4ad4781ea80f79ac43c3c7b043ddf760/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_2.json`
- `source_bundle.artifact_sha_or_digest=3991ba4b335305da3d4e2f96f231d5346c5c0bdb`
- `quality_review.reviewed_artifact=github://cristhianlujan/claude-persona-lf-patch@21094d2b4ad4781ea80f79ac43c3c7b043ddf760/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_2.json`

Preserve per-lane and per-blocker dispositions as extensions in `quality_review`. Independently determine whether each historical blocking code is actually closed, whether any new blocking code exists, whether the trust-anchor design is sufficient for the next governance gate, and what claim ceiling remains justified.

Validate the final receipt with the frozen Quality Pack validator before returning it.

Return only the final JSON receipt, with no explanation before or after it.
