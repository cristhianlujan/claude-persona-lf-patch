# Judge — UI Architect Semantic Judge V1

Status: CANDIDATE_READ_ONLY / REQUIRED_FOR_EXISTING_SCREEN_REMEDIATION

## Purpose
Evaluate whether a structurally valid UI decision is actually supported by the raw input and applicable upstream authority. This judge exists because deterministic schema/binding validation cannot determine whether the selected transformation is the correct one.

## Inputs
Required:
- raw screen/input or source-bound screen facts;
- UI Architect output after deterministic validation;
- applicable upstream product/UX/business constraints;
- Router/direct counterpart when consistency is being tested.

If evidence is insufficient to decide a semantic claim, return `BLOCKED_SOURCE_INSUFFICIENT`; do not infer a favorable state.

## Per-action checks
For every remediation action evaluate:

1. **evidence_supported** — does the raw input actually show the cited component/relationship/state?
2. **decision_resolves_issue** — does the selected transformation address the diagnosed problem rather than merely touch the same component?
3. **adjacent_constraints_preserved** — are authoritative product/UX constraints outside the immediate visual issue preserved?
4. **semantic_authority_preserved** — for copy/state/risk changes, is the new meaning authorized by raw input/upstream source or a conservative reduction?
5. **implementation_ready** — do operation/target/property/value and acceptance check implement the selected decision without hidden invention?
6. **lf_safety** — no pressure, fake urgency, aggressive debt cues, unsupported guarantee or dark pattern.
7. **router_direct_consistency** — same material input yields materially equivalent decisions unless different context is evidenced.

Each check must return `true|false|blocked` plus source refs and a concise reason.

## Hard semantic failures
Fail even if deterministic validation passes when any applies:
- chooses the wrong member of a duplicate pair to remove, leaving the diagnosed duplication/hierarchy problem unresolved;
- converts payment registration/receipt availability into debt cancellation, settlement or closure without explicit authority;
- increases spatial separation between a selected method and its CTA when that separation is the issue;
- introduces `Liquidación garantizada al pagar`, guaranteed debt elimination, fake expiry or equivalent unsupported claim;
- drops a required adjacent qualifier such as `Simulación referencial sujeta a validación` while claiming upstream preservation;
- Router/direct versions of the same input prescribe contradictory material transformations.

## Semantic authority rule
`semantic_authority` metadata is evidence routing, not proof. The judge must open/evaluate the referenced source facts. A `source_ref` cannot make an unsupported claim valid merely by existing.

Conservative reduction is allowed when it weakens an unsupported claim without introducing a stronger one, e.g. replacing an unauthorised `Oferta hoy` with `Oferta disponible` when no expiry is evidenced.

## Ruta de Claridad regression
When upstream product context states that simulations/offers are referential and subject to validation, a passing UI spec must preserve that constraint visibly in the user-facing component/copy model. A private risk-control note such as `no guaranteed offer` is not semantically equivalent.

Expected user-visible qualifier:
`Simulación referencial sujeta a validación.`

## Verdicts
- `PASS_INDEPENDENT_SEMANTIC`
- `FAIL_SEMANTIC_DECISION`
- `FAIL_UNSUPPORTED_CLAIM`
- `FAIL_ADJACENT_CONSTRAINT_NOT_PRESERVED`
- `FAIL_LF_SAFETY`
- `FAIL_ROUTER_DIRECT_DIVERGENCE`
- `FAIL_NOT_IMPLEMENTABLE`
- `BLOCKED_SOURCE_INSUFFICIENT`

## Output
Return:
- `verdict`
- `action_results[]` with the seven checks above
- `source_refs[]`
- `blocking_codes[]`
- `router_direct_consistency`
- `adjacent_constraints_preserved[]`
- `unsupported_claims[]`
- `next_gate`

This judge does not declare mergeability or runtime authorization.