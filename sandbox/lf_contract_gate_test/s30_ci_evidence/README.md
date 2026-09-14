# S30 CI_EVIDENCE_LF

Source-only S30 candidate for transversal CI evidence aggregation. It does not create another CI system, does not rerun provider semantics and does not authorize merge, runtime, production, Golden, qualification, semantic review or E2E closure.

## Problem

LF already has strong CI producers and evidence mechanisms, but consumers currently carry workflow run IDs and proof fragments directly inside operation receipts. That makes exact-head evidence repetitive and easy to overclaim. `CI_EVIDENCE_LF` normalizes the envelope while preserving each provider's authority.

## Providers reused

- `Validate LF Packs` — direct exact-head workflow evidence.
- `lf-contract-check` — requires a real successful DEEP job plus the non-expired `r8-continuous-audit-{run_id}` artifact and its SHA-256 digest. Workflow-level success alone is insufficient.
- `LF Bootstrap Reproducibility Probe` — direct exact-head workflow evidence.
- S31 `CURRENTNESS_AUTHORITY` — optional profile requiring both `LF_CURRENTNESS_AUTHORITY_RECEIPT_V1` and `LF_SOURCE_ATTESTATION_RECEIPT_V1`, plus a durable successful `LF Currentness Authority` workflow anchor. It binds the moving base/current authority, not the candidate HEAD.
- `record_external_ci_verification_v7` — retained only for its actual post-merge `LF_SKILL_ARTIFACT` scope. It is not relabeled as generic CI authority.

Existing `programacion.provenance_receipts` / `evidence_verifications` are also preserved. Their registered channels are domain-specific, so this candidate does not silently promote them to LF-wide authority.

## Offline aggregation

The aggregator receives already-produced provider receipts and performs deterministic local verification only. It contains no GitHub REST, HTTP client, subprocess or remote-currentness call. Provider verification remains upstream.

For `lf-contract-check`, v1 accepts only `DEEP_RUN`. The workflow's exact-context reuse optimization is intentionally not accepted until the producer exposes a reusable receipt that cryptographically and semantically binds the reused DEEP evidence.

## First real case

`first_real_case_pr788_20260914.json` freezes the exact evidence from S30 EKB preflight PR #788:

- candidate head `7e15e27e1427715b078e2ce95ecb277db71496b7`
- base `b533f7f4e721d04822359a75f19a82949e799faf`
- Validate LF Packs run `34869397407`
- lf-contract-check run `34869397411`, DEEP job `104061311340`
- audit artifact `10357429771`, digest `sha256:914291e27e315d7255e61aa2307d7bbb011e690afef71a644f78cafab88828ba`
- Bootstrap run `34869397287`

Expected result is `PASS_CI_EVIDENCE_AGGREGATED`, with every non-CI closure field remaining `false`.

## Claim ceiling

`CI_EVIDENCE_ONLY_NOT_DOMAIN_CLOSURE`.

No Supabase mutation, workflow deployment, provider rewrite, cross-owner change or `main` merge is performed by this candidate.
