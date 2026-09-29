# PASE_CONTROL_SYSTEM_QUALIFICATION_AUTHORITY_V1

## Purpose
Extend the existing canonical `public.lf_qualification_receipts` ledger so `PASE_CONTROL_QUALIFICATION_V1` can durably represent exact-head `CONTROL_SYSTEM` candidates without creating a parallel authority.

## Authority model
- Existing canonical ledger: `public.lf_qualification_receipts`.
- New subject type: `CONTROL_SYSTEM`.
- Canonical qualification authority: `PASE_CONTROL_QUALIFICATION_V1`.
- Exact candidate revision: `sha256(head_sha)` via `lf_control_system_qualification_revision_sha256_v1`.
- Trusted readback: `lf_control_system_qualification_readback_v1(candidate_id, repository, base_sha, head_sha)`.
- The readback validates durable identity/cardinality and returns the stored packet/result. A trusted-base consumer MUST re-run the repository validator over those returned bytes before using the verdict.

## Boundary
This solution does not:
- create a second qualification table;
- change Changeset Governance applicability;
- qualify a candidate by itself;
- activate, cut over, rebind, deploy, retire legacy, or change GitHub rulesets;
- alter OPERATION or STRATEGY qualification semantics.

## Required negative behavior
- no exact receipt -> `status=MISSING`;
- malformed identity/payload -> fail closed;
- stale base/head -> fail closed;
- more than one current receipt -> fail closed;
- only `CANDIDATE_QUALIFIED` receipts may be materialized as current CONTROL_SYSTEM qualification.

## Sequence
`authority extension -> live readback -> independent exact-head qualification receipt -> PR #1239 consumes canonical readback -> PASS/BLOCK live-fire -> merge-gate enforcement restoration -> cutover`.
