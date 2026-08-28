# Judge — Quality Pack Mini-Judge

Status: CANDIDATE_READ_ONLY / SANDBOX

## Purpose
Determine whether an upstream artifact can proceed to the next gate without treating structure, score, narrative, provenance flags or candidate-declared hashes as semantic/evidentiary proof.

## Mandatory gate order
1. Structural validation.
2. Provenance validation when execution provenance is claimed.
3. Artifact existence/readback validation when an artifact is required.
4. Upstream validity/currentness validation when the output depends on another profile/artifact.
5. Independent semantic-quality judgment.
6. Final verdict reconciliation with `validators/validate_gate_bundle.py`.

Each gate has its own evidence. A PASS in one gate cannot substitute for another applicable gate.

## Resolver-backed evidence boundary — GOV-037
A candidate statement such as `observed=true`, `read=true`, `current=true`, `sha_match=true`, `receipt_valid=true`, or an equal pair of declared hashes is **not evidence**.

Before any applicable gate can PASS, every evidence object used by that PASS must be resolved by an independent trusted resolver. The default deterministic resolver is `validators/trusted_ref_resolver.py`; it accepts only immutable same-repository GitHub refs of the form `github://owner/repo@<40-hex-commit>/<path>`, reads the bytes with Git, recalculates SHA-256, and derives whether the revision is the current checked-out revision. Unsupported providers or unresolvable refs fail closed until an independently authorized resolver is supplied.

For provenance PASS, `receipt_ref` and `receipt_sha256` must resolve independently in addition to any declared `receipt_valid` flag. For upstream PASS, declared currentness cannot override resolver-derived non-current revision evidence.

## Required checks
1. Upstream worker contract was identified.
2. Expected schema was identified.
3. Output satisfies required structure.
4. Evidence exists for every PASS/true claim and is an observed evidence object with exact digest, not a token such as `PASS` or `ok`.
5. Every PASS evidence ref resolves independently and its declared SHA-256 equals the digest recomputed from resolved bytes.
6. Score breakdown follows rubric and every criterion has concrete resolver-backed evidence.
7. LF safety/governance controls pass.
8. Scope leakage controls pass.
9. Handoff is actionable.
10. Required repair actions are explicit when failing.
11. If provenance is claimed, receipt validity, `MODEL_RUNTIME` origin and exact RAW capture are claimed **and** the receipt ref/digest are resolver-bound.
12. If an artifact is required, it exists through resolver readback and remains parseable under its domain validator.
13. If an upstream is required, its exact SHA matches resolver bytes, its resolver-derived revision is current and its current validator status is compatible.
14. Semantic judgment is independent from the producer oracle; `UNCERTAIN` never becomes PASS.
15. Router/direct outputs that are materially equivalent inputs cannot diverge without an explicit governed reason.

## Automatic FAIL conditions
- Score exists without criterion evidence or evidence is nominal.
- Evidence ref cannot be resolved by the trusted resolver required for that provider.
- Declared evidence SHA does not equal the resolver-derived SHA-256.
- `observed/read/current/receipt_valid/sha_match=true` is used as a substitute for external readback.
- Required field claimed but not developed.
- Internal metadata can leak into final user artifact.
- Dark pattern, debt pressure, fake urgency, shame, guarantee or red alarm cue appears.
- Composer would need to invent major structure.
- Output says approved/ready without evidence map.
- Authentic execution receipt exists but the semantic decision is unsupported or wrong.
- Required upstream exists but is stale, hash-mismatched or rejected by its current validator.
- Required artifact is only a plan/spec and no artifact readback exists.
- Semantic judge reuses the producer oracle or self-certified evidence.
- Any applicable gate returns `FAIL`, `UNCERTAIN` or missing evidence while final verdict claims PASS.

## Verdict mapping
- `PASS_TO_COMPOSER`: every applicable gate is independently evidenced and PASS; no blocking code.
- `PASS_WITH_RESTRICTIONS`: every applicable gate is PASS and remaining non-blocking risk is explicit. It cannot mask FAIL/UNCERTAIN.
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`: input sufficient but worker output incomplete.
- `RETURN_TO_ORCHESTRATOR`: wrong/missing upstream context or source readback is required.
- `BLOCK_PIPELINE`: unsafe, invalid, contradictory, self-certified, semantically unsupported or otherwise blocked.

## Deterministic reconciliation
Before emitting `PASS_TO_COMPOSER` or `PASS_WITH_RESTRICTIONS`, materialize the five gate states in the bundle consumed by `validators/validate_gate_bundle.py`:
- `STRUCTURALLY_VALID`
- `PROVENANCE_VALID`
- `SEMANTICALLY_VALID`
- `ARTIFACT_VERIFIED`
- `UPSTREAM_VALID`

Run `evals/quality_gate_adversarial.py` as the permanent regression. It includes the GOV-037 exploit (nonexistent ref + 64-zero SHA + self-declared observed/receipt flags), real-ref/wrong-digest controls, score 25/25 with nominal evidence, authentic receipt with wrong semantics, missing provenance, stale upstream, plan-only artifact, Router/direct divergence, semantic uncertainty, self-certification, generic acceptance, correlated oracle, and an all-gates resolver-backed positive.

## Required output
Quality Pack must produce:
- `verdict`
- `score_breakdown`
- `evidence_map`
- `blocking_codes`
- `repair_actions`
- `remaining_risks`
- `next_gate`
- gate evidence sufficient to reconstruct the deterministic five-gate bundle when the output may proceed downstream.
