# RW1-06_C1 — Single-pass sealed review capture redesign V2

Status: **DESIGN CANDIDATE — NOT NORMATIVE / NOT C1 DONE**. Owner-requested redesign following two admitted GAP diagnostics. No source freeze, production, Router authority, Train, ACL, or checkpoint transition is changed by this artifact.

## Root cause

The V1 handoff starts generating the secret corpus before confirming durable private custody, a stable execution identity, an independent reviewer channel and immutable precommit transport. It also requires `reviewer_reference` to be a ChatGPT-provided conversation ID, which the model may not possess; using a second GPT Native prompt cannot create provider attestation. The two 13/26/2 corpus commitments remain historical/unadmitted and must not silently become independent.

This is a **workflow/capture problem**, not evidence that the Router has failed.

## Proposed architecture (reuse existing carriers)

```text
ACT-0001 / Engineering plan authority (unchanged)
    |
    v
P0 Coordinator admission PRE-FLIGHT (GitHub + local verifier)
    |-- source refs & scope verified?
    |-- unique Git attempt reference created?
    |-- owner-witnessed clean reviewer channel documented?
    |-- private durable storage, ACL and readback channel tested?
    |        NO -> GAP; DO NOT GENERATE HOLDOUT
    v
P1 Separate GPT Native reviewer receives only whitelisted frozen sources
    |-- 12+ valid, 24+ invalid, 2+ novel falsifiers
    |-- preregister expected outcomes; do not see producer RAW
    v
P2 Private custodian stores corpus + manifest / proves recovery
    |-- compute real SHA-256 bytes, confirm after retrieve
    |-- owner/provider attestation distinguished
    v
P3 Public Git commitment (hashes + attempted evidence refs ONLY)
    |-- read back immutable Git blob/commit and bind attempt_ref
    |-- commit MUST precede producer RAW and C2 evaluation
    v
P4 C1 evidence admission under canonical governance
    |-- structural pass + custody/readback + chronology + separation
    |-- if a material gate absent: typed GAP, do not retry the corpus
    v
C2 (separate lifecycle) -> C3 FULL (separate judgement)
```

### P0. One-time capacity check BEFORE authoring

Coordinator creates an immutable Git `attempt_ref` (e.g. SHA + path of a uniquely named public attempt request, not a fabricated ChatGPT ID), pinned to source policy Git blob and full frozen SHA. Confirm a distinct reviewer context outside the LF project, without project history or producer keys. The accountable operator supplies a **non-public** attestation reference documenting the environment and participant separation; it is **not** provider cryptographic attestation.

Verify private durable custody **before running the reviewer**: configurable already-available owner-controlled storage (e.g. access-controlled Drive folder or encrypted local vault with durable independent storage), a test upload/retrieve, ACL denying producer access, custodian readback receipt. A bare path under `/mnt/data`, a ChatGPT claim, or GitHub public repo is not evidence of sealed storage. If no such storage is available, return `CUSTODY_PREFLIGHT_GAP` without generating any cases.

Operational identity = Git `attempt_ref` + custodian/owner attestations. A private ChatGPT chat URL can be supplemental evidence but is not an automatic ChatGPT-model-supplied mandatory field. **An attempt_ref is not evidence of reviewer independence.** Reviewer separation must be checked through a distinct accountable evidence gate.

### P1/P2. Create once; seal immediately

The reviewer receives only an allowlist of normative source paths and Git blobs. Never provide producer chat, old secret cases/keys, expected outputs or earlier invalid holdout content. It generates a new corpus (minimum 12/24/2 across F01–F13) and pre-registers oracles before observing producer RAW. Write canonical UTF-8 bytes to private durable storage, compute content and manifest SHA-256 on those bytes, and independently retrieve and hash again in the custodian context. Keep plaintext path, seed, nonce, case bodies and oracles out of the public repository and all producer contexts. If retrieval or ACL proof fails, stop as `CUSTODY_READBACK_GAP`; never tell the model simply to repeat its prompt.

### P3. Atomic public commitment

Public record must include `attempt_ref`, source SHA, source policy blob, explicit 12/24/2 counts, content/manifest digests, private custody receipt **opaque ID or digest (not secret URL)**, reviewer separation evidence ref, claim/limits, `provider_attested=false`, `independent_review=false`, and `checkpoint_done=false`. Publish through existing GitHub commit carrier, then retrieve exactly that Git blob and commit. Do not treat claimed timestamps as trustworthy precommit order.

C2 RAW producer artifact must reference the exact public Git commitment SHA. Check graph ancestry or other verified monotonic external ordering; if C2 RAW preceded commitment, reject even if the timestamp in JSON says otherwise. Reveal secret tests only after producer RAW commitment and only to authorized checker; verify the private plaintext bytes against earlier public SHA-256 before evaluation. Failure -> `HOLDOUT_INTEGRITY_GAP`.

### P4. Evidence admission and decision semantics

**Separately report**:
- `STRUCTURE_VALID`: format, sources, minima and JSON.
- `CUSTODY_VERIFIED`: real private readback, producer access denied and hashes match.
- `CHRONOLOGY_VERIFIED`: external public commit precedes producer RAW.
- `REVIEWER_SEPARATION_OWNER_ATTESTED`: supporting owner/custodian declaration of distinct environment and no shared producer context. This is *not* `independent_review=true` or `provider_attested=true`.
- `PROVIDER_ATTESTED`: **never inferred** from a native chat, Git IDs, custody checks or owner declaration.

Existing C1 assertion `separate_reviewer_evidence=true` must remain blocked until the authorized governance contract explicitly defines which lower-level owner-evidenced separation tier, if any, is sufficient. The V1 validator requiring a true ChatGPT chat ID must **not** be silently bypassed; revise it by governed change before admitting a Git attempt_ref in its place. RW1-06_C3 remains FULL; no downgrade of hard-fail cases, 3 negative controls, benchmark/overhead GAP handling or Router authority.

## Minimal contract proposal (versioned, no hard-coded provider)

`RW106_C1_REVIEW_CAPTURE_V2` has four independently evidenced objects:
- `attempt`: `attempt_ref`, `source_snapshot_commit`, `source_policy_git_blob`, `issued_by`, `git_readback_ref`.
- `separation`: `reviewer_channel`, `owner_attestation_ref`, `no_shared_project_context`, `producer_context_access` (must be false), `provider_attested` (false unless real).
- `custody`: `store_type`, `private_receipt_digest`, `producer_access_denied_evidence_ref`, `durable_readback_evidence_ref`, `holdout_manifest_sha256`, `holdout_content_sha256`.
- `ordering`: `public_commit_git_sha`, `producer_raw_git_sha` (null before C2), `ordered_by_git_ancestry` (null before C2).

All fields are keyed to existing canonical source and evidence refs; vault choice is not hard-coded. No new Supabase service, router, API or runtime is required. Metadata can be stored in existing engineering plan source pack/evidence; database changes only via LF Migration Merge Train.

## Acceptance tests (must precede operational use)

1. Preflight rejects missing attempt ref / wrong source / mismatched policy.
2. Preflight rejects shared-project or producer-accessible reviewer channel.
3. Preflight rejects absent durable readback or missing ACL evidence, and bare session-local filesystem custody.
4. Public receipt rejects missing content/manifest hash, insufficient 12/24/2, secrets in public JSON and unsupported provider-attested claims.
5. C2 admission rejects no public commit, public commit after producer RAW, content hash mismatch or case exposure before producer RAW.
6. C1 does not close merely from local selftests, owner claims or passing PASE. C3 FULL remains unchanged.

## Rollout and invariant-preserving transition

A. Keep V1 source freeze blob `138efc3285ee5226c107827c66f84ced6be4afcb` and two historical commitments unchanged.
B. Author P0 verifier as advisory-only; use it with synthetic fixtures and negative tests. No real reviewer run before storage/identity readiness.
C. Obtain a **separate explicit governance acceptance** for V2 attempt-identity/separation evidence in place of the V1 mandatory chat URL; change assertion spec/validator through normal review and Train, never via implicit exception.
D. Only after P0 capacity and C1 admissibility are verified create a new independent holdout once; publish Git-bound precommit; then C2/C3.
E. If no supported clean context or private custody can be verified, stop with a **single actionable GAP**. Do not keep requesting new corpus generations.

## Outside scope

No disclosure of confidential holdouts, no merged PR or DB mutation, no C1 PASS, no provider isolation guarantee, no runtime/production changes, no bypass of direct SQL/Train, no invented overhead SLO and no material effect authorization from semantic PASS.
