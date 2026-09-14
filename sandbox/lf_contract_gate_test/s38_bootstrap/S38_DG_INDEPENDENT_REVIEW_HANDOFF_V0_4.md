# S38-DG Independent Semantic Review Handoff v0.4

Review case: `S38-DG-IR-008`  
Review mode: `INDEPENDENT_CHAT_CONTEXT`

Operate in a clean independent context. Do not use producer conclusions, producer governance disposition, deterministic PASS counts, prior conversation memory, PR merge refs, branch HEAD, moving `main`, or later snapshots as semantic proof.

Do not repair during review. Do not authorize merge, Golden, runtime, scheduler activation, semantic/behavioral promotion, production, Supabase mutation, secret provisioning, or key provisioning.

## Frozen review bundle

Review exactly:

`github://cristhianlujan/claude-persona-lf-patch@0f818e7c301adf0c7ab0d4b5283e14dfa9c435cf/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_4.json`

Expected bundle Git blob SHA:

`8b5d3169a8c06cf7c2166f66cffbc3814aa3740c`

Expected bundle SHA-256:

`219b2c812832d999b78123b1a674fe94c4d0d57d7d154bb0565ff09d9f8c0374`

Frozen repaired candidate snapshot:

`aeeac1b30713bc67421f212854c94595b6f6d975`

Immutable comparison base:

`41b47f8ac6da3f83d164ecc8aa46852dd64fdbf0`

The candidate is intentionally earlier than the evidence/package commits. Review the exact candidate, not the packaging HEAD.

## Out-of-band trust input — mandatory

The independent reviewer must treat the following signer digest as supplied out-of-band by the review request, not as chosen by the candidate, bundle, subject, resolver, policy, branch, or PR:

`b464326ed6c6db0e93959588b952a74e5fc2fe30`

Immutable signer workflow:

`github://cristhianlujan/claude-persona-lf-patch@b464326ed6c6db0e93959588b952a74e5fc2fe30/.github/workflows/lf-trusted-attestation-reusable-v1.yml`

The reviewer must independently verify that the Sigstore/GitHub attestation was signed by this exact signer workflow digest and that changing the candidate checkout cannot mint an attestation satisfying this out-of-band signer identity.

## Exact external attestation evidence

Signed subject manifest:

`github://cristhianlujan/claude-persona-lf-patch@76e8bac9d60f2ad3e9a022e4192e7c0fe9c4bd16/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir008_signed_subject_manifest_v0_1.json`

Expected subject Git blob SHA: `b0a71773e2a373b938ded56b768907e5bb79be18`  
Expected subject SHA-256: `789c155987731dcf616dfe691d27e5d352eb2621a496b3f9be65cb698ad36f25`

Frozen Sigstore bundle:

`github://cristhianlujan/claude-persona-lf-patch@76e8bac9d60f2ad3e9a022e4192e7c0fe9c4bd16/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir008_sigstore_attestation_bundle_v0_1.json`

Expected Sigstore bundle Git blob SHA: `1bc409c7fe0b7f5a51e8ccc50263b171651f608e`  
Expected Sigstore bundle SHA-256: `b4bce7ae2cddeb1567d1bb126dc86ab30a9a2420d57d40e5412580880665d334`

External caller commit used to request signing:

`95e0b57e6cb944d61f80b99819967c1bb9402272`

External attestation workflow run:

`34843395522`

The reviewer must independently verify the cryptographic bundle and its certificate/provenance claims. Producer-reported verification results are provenance only.

## Source independent review and producer repair evidence

Prior independent S38-DG-IR-007 receipt:

`github://cristhianlujan/claude-persona-lf-patch@76e8bac9d60f2ad3e9a022e4192e7c0fe9c4bd16/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_ir007_independent_receipt_v0_1.json`

Expected receipt Git blob SHA: `f209ab9f06f2d950b274b20013ab9186f3e6eb4b`  
Expected receipt SHA-256: `ac149cc2d710daeb1d3da571694ea3e02a317c4cd4e548af1404692e43e3ceaa`

Producer governance disposition, recommendation only:

`github://cristhianlujan/claude-persona-lf-patch@76e8bac9d60f2ad3e9a022e4192e7c0fe9c4bd16/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir007_governance_disposition_v0_1.json`

Producer repair receipt, provenance only:

`github://cristhianlujan/claude-persona-lf-patch@76e8bac9d60f2ad3e9a022e4192e7c0fe9c4bd16/sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir008_repair_receipt_v0_1.json`

Frozen Quality Pack reference:

`3b39657fbf14f29c7839ecb26d715ed5c6fad59e`

## Review objective

Attempt to falsify the IR-008 repair. IR-007 returned the candidate to the producer with four explicit blockers and additional reproducibility/pinning findings. The producer claims only deterministic/provenance repair evidence.

### A. External trust anchor — highest priority

Independently determine whether the externally signed subject plus the out-of-band immutable signer digest actually breaks the whole-checkout bootstrap circularity found in IR-007.

Mandatory attacks include:
- alter the complete candidate checkout, including resolver constants, policy, validator and schemas, while preserving local self-consistency;
- alter the signed subject bytes;
- substitute a subject signed for a different candidate SHA;
- substitute a different signer digest;
- substitute a different caller/source digest;
- use a foreign repository or repository id;
- attempt a self-hosted-runner or non-GitHub-OIDC signing path;
- mutate the signer workflow at another commit while retaining the same filename;
- verify the immutable signer workflow bytes at `b464326e...` independently;
- verify the Sigstore certificate/provenance binds the exact signer workflow digest, GitHub-hosted runner, repository identity, caller/source digest, and signed subject digest.

Do not infer closure merely because GitHub or Sigstore accepted an attestation. The question is whether an attacker controlling the candidate checkout can still manufacture a trust object accepted under the out-of-band signer identity.

### B. Offline reproducibility and liveness

IR-007 found a material dependency on unauthenticated GitHub REST quota. Independently verify that:
- resolver construction and evidence resolution for the frozen candidate perform no GitHub REST/API/network calls;
- after a one-time trust-root/bootstrap step, the frozen attestation bundle and signed subject can be verified repeatedly without GitHub API availability;
- network denial causes no byte substitution or trust fallback;
- any unavailable external bootstrap fails closed rather than silently trusting local bytes.

Producer reported 50 offline verifications in 4 seconds. Reproduce independently; do not use the count as proof.

### C. Contract surface completeness

Verify every current runtime/evidence TCB pin in the signed subject. Independently test tamper of:
- resolver;
- trust policy;
- validator;
- F schema;
- D schema;
- E capability manifest schema;
- strict S38 G request schema;
- strict S38 G output schema;
- deterministic producer harness;
- historical pin inventory;
- legacy S31 resolver boundary.

Confirm strict E/G schema validation is load-bearing. Unknown/undeclared surface must fail closed at F, E, G request and G output boundaries where applicable.

### D. Historical identity completeness

The signed subject declares 16 explicit historical revision+path+blob+SHA-256 identities. Recompute all 16 independently. Test changed bytes, wrong revisions, same-content identity substitution, foreign repository material, and unregistered identity. A lawful rename/move/delete may remain current only when exact governed historical identity is present.

### E. Claim tier and archival authority

Verify that the policy bytes used for claim tier and archival currentness are covered by the externally signed runtime TCB. Verify the maximum tier without a valid independently allowlisted witness remains `PROVENANCE_EXECUTION`. Fresh producer-authored SEMANTIC/BEHAVIORAL sets, elevated ceiling, fake witness, malformed witness, historical witness and unallowlisted witness must fail closed.

An empty witness allowlist is a safe fail-closed state, not evidence that SEMANTIC or BEHAVIORAL promotion is ready.

### F. D/E/F/G no-regression

Independently re-run the relevant historical and current attacks, including owner-capability mismatch; authority/provenance replay; same-content input/authority/provenance identity substitution; execution revision rebinding; producer-as-resolver; nested invalid authority behind a valid outer digest; untrusted resolver type/id; request-id and governed-input mismatch; silent fallback; weakened forbidden-authority set; nested authority effects/grants; and strict unknown-surface rejection.

Independently rederive any common cross-binding digest actually used. Do not trust a producer value.

### G. Bundle and package integrity

Recompute:
- bundle blob and SHA-256;
- candidate lineage;
- all 11 signed current candidate pins;
- all 16 signed historical pins;
- both frozen Quality Pack pins;
- all 5 evidence-package pins;
- immutable signer workflow pin;
- external caller workflow pin;
- signed subject digest;
- Sigstore bundle digest;
- prior independent receipt pin.

Report any load-bearing artifact absent from the signed or frozen pin models.

The unrelated shared migration-source parity CI failure remains outside this exclusive S38 lane. Do not import shared migrations and do not use that failure as semantic repair evidence.

## Required output

Return exactly one JSON object valid against:

`github://cristhianlujan/claude-persona-lf-patch@3b39657fbf14f29c7839ecb26d715ed5c6fad59e/profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`

Required metadata:
- `receipt_version=v0.1`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT` only after actual completion
- `review_case_id=S38-DG-IR-008`
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `source_bundle.artifact_ref=github://cristhianlujan/claude-persona-lf-patch@0f818e7c301adf0c7ab0d4b5283e14dfa9c435cf/sandbox/lf_contract_gate_test/s38_bootstrap/s38_dg_independent_review_bundle_v0_4.json`
- `source_bundle.artifact_sha_or_digest=8b5d3169a8c06cf7c2166f66cffbc3814aa3740c`
- `quality_review.reviewed_artifact` equal to that exact same bundle ref.

Preserve independent dispositions for trust anchor, offline reproducibility, contract surface, historical pinning, claim tier, archival currentness, D/E/F/G no-regression, current pins, signer/caller pins, Sigstore cryptographic verification, and any new findings as extensions under `quality_review`.

Validate the final receipt with the frozen Quality Pack validator. Return only the final JSON receipt, with no explanation outside the JSON.
