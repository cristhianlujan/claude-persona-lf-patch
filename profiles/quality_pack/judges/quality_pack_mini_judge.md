# Judge — Quality Pack Mini-Judge

Status: CANDIDATE_READ_ONLY / SANDBOX

## Purpose
Determine whether an upstream artifact can proceed to the next gate without treating structure, score, narrative or provenance as semantic proof.

## Mandatory gate order
1. Structural validation.
2. Provenance validation when execution provenance is claimed.
3. Artifact existence/readback validation when an artifact is required.
4. Upstream validity/currentness validation when the output depends on another profile/artifact.
5. Independent semantic-quality judgment.
6. Final verdict reconciliation with `validators/validate_gate_bundle.py`.

Each gate has its own evidence. A PASS in one gate cannot substitute for another applicable gate.

## Required checks
1. Upstream worker contract was identified.
2. Expected schema was identified.
3. Output satisfies required structure.
4. Evidence exists for every PASS/true claim and is an observed evidence object with exact digest, not a token such as `PASS` or `ok`.
5. Score breakdown follows rubric and every criterion has concrete evidence.
6. LF safety/governance controls pass.
7. Scope leakage controls pass.
8. Handoff is actionable.
9. Required repair actions are explicit when failing.
10. If provenance is claimed, receipt validity, `MODEL_RUNTIME` origin and exact RAW capture are proven.
11. If an artifact is required, it exists, has direct readback and is parseable.
12. If an upstream is required, its exact SHA matches, it is current and its current validator status is compatible.
13. Semantic judgment is independent from the producer oracle; `UNCERTAIN` never becomes PASS.
14. Router/direct outputs that are materially equivalent inputs cannot diverge without an explicit governed reason.

## Automatic FAIL conditions
- Score exists without criterion evidence or evidence is nominal.
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

Run `evals/quality_gate_adversarial.py` as the permanent regression. It includes score 25/25 with nominal evidence, authentic receipt with wrong semantics, missing provenance, stale upstream, plan-only artifact, Router/direct divergence, semantic uncertainty, self-certification, generic acceptance, correlated oracle, and an all-gates positive.

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
