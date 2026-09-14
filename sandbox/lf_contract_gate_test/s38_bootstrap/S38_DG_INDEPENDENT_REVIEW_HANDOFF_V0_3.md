# S38-DG Independent Semantic Review Handoff v0.3

Review case: `S38-DG-IR-007`  
Review mode: `INDEPENDENT_CHAT_CONTEXT`

Operate in a clean independent context. Do not use producer conclusions, producer governance disposition, deterministic PASS results, prior conversation memory, PR merge refs, branch HEAD, later snapshots, moving `main`, or the superseded S38-DG-IR-005 package as semantic proof.

Do not repair during review. Do not authorize runtime, Golden, merge, scheduler activation, production, or behavioral promotion.

## Frozen bundle

Review exactly:

`github://cristhianlujan/claude-persona-lf-patch@c656f1b9707ed8990d99dca62acbbe1933d77950/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_3.json`

Expected bundle Git blob SHA:

`ba9e52314a88fe1abab4726c420f6465bcdb9302`

Frozen repaired candidate snapshot:

`63f5db552c10535cfc473e50d0706ab2f8ae4758`

Immutable comparison base:

`eac7c8ad4f0e9c8df09c22aa0a5a3f6b5071da66`

Prior independent S38-DG-IR-006 receipt:

`github://cristhianlujan/claude-persona-lf-patch@97b251b2f0e5170f7476184768e0cfcf8bb28267/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_ir006_independent_receipt_v0_1.json`

Expected receipt blob SHA: `f9a815d23544e00c7df27c7abe992b6131922376`  
Expected receipt SHA-256: `af11f4d353f9db7d1d846df5b21f6cdccc504ce64f07a65abbb6c0fe3a4ac978`

Producer repair receipt (provenance only):

`github://cristhianlujan/claude-persona-lf-patch@ee1d0173ac5c68565ae227e7b24ccd0d64b65086/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir007_repair_receipt_v0_1.json`

Producer governance disposition (recommendation only):

`github://cristhianlujan/claude-persona-lf-patch@ee1d0173ac5c68565ae227e7b24ccd0d64b65086/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir006_governance_disposition_v0_2.json`

Frozen Quality Pack reference:

`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

## Review objective

Attempt to falsify the S38 IR-006 restriction repair. The producer claims deterministic repair evidence only. Independently derive whether the three IR-006 blockers and the load-bearing historical-pin omission are actually closed.

### Trust anchor — highest priority

IR-006 falsified the prior resolver because repository identity came from the same caller-writable policy being verified. Independently test whether v0.6 actually breaks that circularity.

Mandatory attacks include:
- policy redirects canonical remote to an attacker-controlled repository;
- whole-checkout attack: mutate resolver constants and run from an attacker-controlled checkout/repository, not merely a one-file local tamper;
- local resolver-module tamper with the genuine candidate HEAD;
- local policy tamper before and after resolver construction;
- unpublished/noncanonical revision;
- foreign repository ref;
- Git `insteadOf` and other config redirection;
- `https_proxy`, `HTTPS_PROXY`, `ALL_PROXY`, `GIT_PROXY_COMMAND`, `GIT_SSL_NO_VERIFY`, `GIT_SSL_CAINFO`, `SSL_CERT_FILE`, and PATH/config environment attacks;
- independently determine whether fixed GitHub slug/remote/API/numeric repository ID plus exact-commit GitHub API attestation constitute a sufficient external trust root or remain self-referential when the whole validation checkout is attacker-controlled.

Do not inherit the producer's answer to that last question.

### Enforced contract surface

IR-006 demonstrated that a locally modified F schema could be executed while the resolver remained verified. Independently test:
- F schema tamper before and after resolver construction;
- D schema tamper;
- validator tamper;
- resolver/policy tamper;
- every load-bearing code/schema surface used for PASS is either canonical-byte loaded or byte-verified before use;
- unknown/undeclared envelope surface remains fail-closed.

### Claim tier

Verify that:
- without an independently allowlisted witness the earned maximum is `PROVENANCE_EXECUTION`;
- fresh self-authored SEMANTIC/BEHAVIORAL receipt sets fail closed;
- elevated claim ceiling fails closed;
- fake, malformed, historical, or unallowlisted witnesses cannot raise tier;
- policy authority cannot be relocated or changed by a later local mutation;
- independently disposition the still-empty real witness path. Do not infer SEMANTIC/BEHAVIORAL readiness from an empty allowlist.

### Archival currentness and historical pinning

Verify exact historical ref+digest survives lawful rename/move/delete while changed bytes, wrong refs, foreign material, and unregistered identities fail closed. Verify the bundle's `historical_frozen_artifacts` model independently, including:

revision `be6c0f8a320c5cdcfa242ee775ba769745eb82df`  
path `profiles/ui_architect/schemas/runtime_output.schema.json`  
blob `bd5508872ff19e9946ba8a8fe7d0eb94ffa7f5d2`  
SHA-256 `bed06e7a37a82a6e1baa9b1da4edb7969456ce64c4270fdd8e5db0f14845d425`

Do not treat a producer-declared match as proof. Recompute it.

### D/E/F/G no-regression

Independently re-run the applicable historical and current attack surface. At minimum cover owner capability mismatch; authority/provenance replay; same-content input/authority/provenance identity substitution; execution revision rebinding; producer-as-resolver; nested invalid authority behind a valid outer digest; untrusted resolver type/id; request/governed-input and request-id mismatch; silent fallback; weakened forbidden-authority set; and nested authority effects/grants.

Independently rederive the S38 common cross-binding digest from resolved bytes/fields. Do not trust the producer value.

### Bundle integrity

Verify the bundle blob, candidate lineage, source IR-006 receipt pin, repair/disposition pins, all declared current candidate pins, all declared historical pins, and the dependency walk actually exercised by your review. Report any additional load-bearing artifact not represented by either current or historical pin models.

The unrelated shared migration-source parity CI failure is outside this exclusive S38 lane. Do not use it as repair evidence and do not import shared migrations.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:
- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S38-DG-IR-007`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@c656f1b9707ed8990d99dca62acbbe1933d77950/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_3.json`
- `source_bundle.artifact_sha_or_digest=ba9e52314a88fe1abab4726c420f6465bcdb9302`
- `quality_review.reviewed_artifact` equal to that same exact bundle ref.

Preserve independent dispositions for trust anchor, contract surface, claim tier, archival currentness, D/E/F/G, current pins, historical pins and any new findings as extensions under `quality_review`; validate the final receipt with the frozen Quality Pack validator; return only the final JSON receipt.
