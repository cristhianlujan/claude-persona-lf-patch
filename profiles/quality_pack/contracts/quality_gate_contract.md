# Contract — Quality Gate Contract

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: profiles/quality_pack/SKILL.md

## Purpose
Quality Pack validates that an upstream output can safely proceed to Composer, final prompt, render, image generation or document impact.

## Required review areas
1. Contract compliance: Did the worker follow the correct contract?
2. Schema compliance: Does the output match the expected schema or required structure?
3. Evidence integrity: Are claims supported by independently resolved evidence?
4. Score integrity: Was score calculated with a rubric and resolver-backed criterion evidence?
5. Handoff quality: Can the next worker continue without inventing?
6. Safety/governance: Does it respect LF rules and avoid dark patterns?
7. Prompt/render readiness: Can it be converted into a clean output without internal leakage?

## Evidence rule — GOV-037
A field marked true must have corresponding evidence, and an evidence object is not proven merely because the candidate supplies `observed=true`, `current=true`, `sha_match=true`, `receipt_valid=true`, a non-empty ref, or a syntactically valid hash.

For any gate that may contribute to `PASS_TO_COMPOSER` or `PASS_WITH_RESTRICTIONS`:
- resolve the evidence reference through an independently trusted resolver;
- read the referenced bytes/data from the provider boundary;
- recompute SHA-256 from the resolved representation;
- require the declared digest to match the resolver-derived digest;
- derive currentness from the resolved revision, not from the candidate flag;
- when provenance is required, resolve the receipt independently as a separate evidence object.

The deterministic same-repository GitHub resolver is `validators/trusted_ref_resolver.py`. Unsupported providers remain unresolved until an independently authorized resolver exists; they cannot be converted to PASS from payload flags.

If evidence is absent, unresolvable, self-certified, digest-mismatched, stale, or receipt-unverified, Quality Pack must not mark the applicable gate PASS.

## Repair routing
- Use `RETURN_TO_WORKER_FOR_SELF_REPAIR` when the input is sufficient but the worker output is incomplete.
- Use `RETURN_TO_ORCHESTRATOR` when upstream context/source readback is insufficient or wrong profile was activated.
- Use `BLOCK_PIPELINE` when the artifact is unsafe, contradictory, self-certified or violates hard constraints.
- Use `PASS_WITH_RESTRICTIONS` only when every applicable gate is independently evidenced and PASS and remaining risks are explicit and non-blocking.

## Required repair action format
Each repair action must include:
- `target_worker`
- `missing_or_failed_item`
- `why_it_fails`
- `required_fix`
- `blocking_code`

## Hard fail
Quality Pack fails if it only says "approved", "looks good" or "ready" without an independently resolvable evidence map, score breakdown and next gate.
