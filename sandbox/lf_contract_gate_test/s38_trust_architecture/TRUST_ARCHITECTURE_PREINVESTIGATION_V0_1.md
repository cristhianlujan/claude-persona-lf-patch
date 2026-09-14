# S38 / LF — Trust Architecture Pre-Investigation v0.1

Status: RESEARCH_ONLY. This artifact does not modify S38 candidate #758 and grants no merge, Golden, runtime, scheduler, promotion or production authority.

## Trigger

Independent S38-DG-IR-007 exposed two separate issues:

1. the repo trust root remained self-referential under whole-checkout tamper;
2. the live verifier made two unauthenticated GitHub REST calls per resolver construction, so a 30-construction review can consume the 60 requests/hour/IP primary unauthenticated quota before accounting for secondary throttling.

The design target is therefore not merely a higher REST quota. It is **one external attestation per candidate/run, followed by offline verification for all attack cases**.

## Existing LF capabilities observed

The repository already contains GitHub Actions OIDC call patterns and governed Supabase Edge callers. This makes an LF-owned external attestor feasible without inventing an identity protocol. GitHub Actions workflows also already use `GITHUB_TOKEN` in governed lanes.

## External research facts

- GitHub REST unauthenticated requests are limited to 60/hour per source IP; authenticated user requests are generally 5,000/hour; GitHub App installation tokens have a minimum of 5,000/hour, with higher/scaled limits in some cases. Secondary limits also exist.
- GitHub Artifact Attestations are available for public repositories on current plans and are signed with Sigstore-backed short-lived certificates.
- `gh attestation verify` validates artifact digest plus actor identity and can additionally enforce signer workflow, signer digest, source digest/ref and repository identity.
- GitHub supports offline attestation verification with a downloaded bundle plus `trusted_root.jsonl`.
- GitHub documentation explicitly recommends a trusted builder/reusable workflow when caller-controlled workflow inputs must not be able to falsify provenance.

References:
- https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
- https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-attestations-offline
- https://cli.github.com/manual/gh_attestation_verify
- https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating

## Candidate architectures

| Option | Whole-checkout tamper | Review-time network | Rate-limit exposure | Operational burden | Disposition |
|---|---|---:|---:|---:|---|
| A. Authenticated GitHub REST + per-run cache | **NOT sufficient by itself**: if verifier lives in checkout, attacker can alter verifier logic | one online bootstrap | low | low | Availability fix only |
| B. GitHub Artifact Attestation + external `gh` verifier + offline bundle/root | **Strong** when repo, signer workflow/digest and source digest are enforced outside candidate checkout | generation/download once; attacks offline | very low | medium | **Preferred pilot** |
| C. LF external attestor: GitHub OIDC -> governed service -> asymmetric signed manifest | **Strong** if private key/service and verification root are outside checkout | one online bootstrap | independent of GitHub REST per test | medium/high | Preferred fallback/control-plane option |
| D. Raw signed Git commit only | Helps bind a commit to a signer but does not by itself attest LF TCB, workflow, policy or evidence manifest | low | low | medium | Supporting signal only |

## Why authenticated REST is not the final answer

Moving from anonymous REST to a GitHub App/token fixes the accidental 60/hour bottleneck, but does not close the IR-007 security defect. If the candidate checkout controls the verifier, it can ignore the API response or change the expected repo identity. Authentication and caching are useful transport improvements, not an external root of trust.

## Preferred architecture: Artifact Attestation Gate

The candidate produces a deterministic **LF Trust Subject Manifest** containing only immutable identities/digests. A trusted reusable workflow, pinned by immutable signer digest and preferably isolated from candidate-controlled logic, attests that manifest once. The independent reviewer uses a system-installed `gh` binary and trusted Sigstore root outside the candidate checkout.

Required verification policy:

1. exact manifest SHA-256 matches the reviewed file;
2. `--repo cristhianlujan/claude-persona-lf-patch`;
3. exact trusted `--signer-workflow`;
4. exact trusted `--signer-digest` supplied by governance outside the candidate;
5. exact `--source-digest` equals candidate SHA;
6. offline `--bundle` + `--custom-trusted-root` for the adversarial battery;
7. no candidate-local verifier result can substitute for external `gh attestation verify` output.

The manifest should bind:

- repository identity;
- candidate commit SHA;
- S38 strategy/review case;
- policy digest;
- resolver digest;
- validator digest;
- D/E/F/G runtime schema digests;
- all explicitly used historical revision+path+blob+sha256 identities;
- claim ceiling;
- authorization = NONE for merge/Golden/runtime/scheduler/production.

## Trusted builder rule

The signing workflow itself is part of the external trust boundary. Candidate code must not be able to replace the signer and still satisfy verification. Preferred order:

1. reusable workflow in a separately governed trust repository, pinned by immutable commit/digest;
2. if kept in this repository, a previously frozen immutable signer commit plus out-of-band signer digest;
3. never trust a signer workflow/digest declared only by the candidate manifest.

## LF external attestor fallback

LF can reuse the existing GitHub OIDC -> Supabase Edge pattern. A governed attestation service would:

- validate GitHub OIDC claims (`repository`, workflow, ref/SHA, audience);
- independently read exact Git blobs/trees with service-held credentials;
- construct the LF Trust Subject Manifest itself or verify an exact submitted digest;
- sign it with an asymmetric key whose private key is held only by the control plane;
- persist an append-only attestation record;
- return a signed bundle suitable for offline review.

This is more controllable but creates LF-owned key rotation, verifier distribution and service lifecycle obligations. It is therefore second choice unless GitHub Artifact Attestations cannot satisfy the required LF policy.

## Review availability model

Current IR-007 pattern:

`REST calls = 2 * resolver constructions`

At 30 constructions, that reaches 60 unauthenticated REST calls/hour/IP. Secondary throttling can fail even earlier.

Target pattern:

`online attestation/bootstrap calls = O(1) per candidate`

Then every tamper/replay/currentness/schema test operates against downloaded immutable Git objects + attestation bundle + trusted root with zero GitHub REST calls per case.

## Decision gates before IR-008

IR-008 must not start until one of these is demonstrated outside #758:

- **Gate T1:** whole-checkout tamper cannot mint or verify an attestation for the genuine LF repository/signer identity;
- **Gate T2:** 100 resolver/test constructions consume zero GitHub REST attestation calls after bootstrap;
- **Gate T3:** verifier binary/trust root and expected signer identity are outside candidate-controlled checkout;
- **Gate T4:** offline verification works from frozen manifest + bundle + trusted root;
- **Gate T5:** signer workflow cannot be changed by the candidate without verification failure;
- **Gate T6:** no merge/Golden/runtime authority follows from attestation alone.

## Recommendation

Run a bounded pilot of **GitHub Artifact Attestations** first. Do not implement another repo-local trust anchor. If the pilot cannot meet T1-T5, move to the LF OIDC external attestor design. Authenticated REST + caching may be used only as a transport optimization, never as the security root.
