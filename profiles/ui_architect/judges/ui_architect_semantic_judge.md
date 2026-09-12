# Judge — UI Architect Semantic Judge V2

Status: CANDIDATE_READ_ONLY / REQUIRED_FOR_EXISTING_SCREEN_REMEDIATION

## Purpose
Evaluate whether a structurally valid UI decision is actually supported by the raw input and applicable upstream authority. This judge exists because deterministic schema/binding validation cannot determine whether the selected transformation is the correct one.

It also verifies that the profile used the strongest available implementation context without inventing authority: canonical values must be used when available, while exploratory work must remain possible when no canonical token/value exists.

## Inputs
Required:
- raw screen/input or source-bound screen facts;
- UI Architect output after deterministic validation;
- applicable upstream product/UX/business constraints;
- supplied/resolved design-system, token, interaction and state context when applicable;
- Router/direct counterpart when consistency is being tested.

If evidence is insufficient to decide a material semantic claim, return `BLOCKED_SOURCE_INSUFFICIENT`; do not infer a favorable state.

Absence of a token/value alone is not source insufficiency when the task is exploratory and the choice is low-risk.

## Per-action checks
For every remediation action evaluate:

1. **evidence_supported** — does the raw input actually show the cited component/relationship/state?
2. **defect_direction_preserved** — does the proposed transformation reduce/eliminate the diagnosed defect rather than reproduce, invert or amplify it?
3. **decision_resolves_issue** — does the selected transformation address the diagnosed problem rather than merely touch the same component?
4. **adjacent_constraints_preserved** — are authoritative product/UX constraints outside the immediate visual issue preserved?
5. **semantic_authority_preserved** — for copy/state/risk changes, is the new meaning authorized by raw input/upstream source or a conservative reduction?
6. **implementation_ready** — do operation/target/property/value and acceptance check implement the selected decision without hidden invention?
7. **context_source_used** — when a canonical token, state rule or upstream value was supplied/resolved and materially applies, did the action use it explicitly rather than degrade to vague wording?
8. **precision_honest** — is the implementation value truthfully classified as canonical/upstream/proposal/relative guidance? A proposal cannot masquerade as authority.
9. **materiality_routed_correctly** — are unresolved material inputs returned to the orchestrator, while non-material exploratory gaps continue without unnecessary blocking?
10. **lf_safety** — no pressure, fake urgency, aggressive debt cues, unsupported guarantee or dark pattern.
11. **router_direct_consistency** — same material input yields materially equivalent decisions unless different context is evidenced.

Each check must return `true|false|blocked` plus source refs and a concise reason.

## Defect-direction gate
Before judging preference or polish, normalize each finding into:

`undesired current state -> corrective transformation -> expected postcondition`

Then verify monotonic improvement on the diagnosed dimension.

Fail `FAIL_DEFECT_DIRECTION_INVERTED` when the proposal reproduces or increases the defect. This includes, but is not limited to:
- diagnosis says duplicated/repeated/redundant and proposal adds, shows, copies or creates another duplicate without explicit authority;
- diagnosis says elements are too far apart and proposal increases separation;
- diagnosis says hierarchy is overloaded/dense and proposal adds competing primary emphasis;
- diagnosis says labels or states contradict and proposal adds another contradiction;
- diagnosis says a claim is unsupported and proposal strengthens that claim.

For a duplicate pair, identify the intended survivor from visible hierarchy or upstream authority. If the evidence cannot establish which copy is authoritative, return `BLOCKED_SOURCE_INSUFFICIENT`; do not guess. A passing acceptance check must demonstrate that the duplication is resolved, not merely that an operation executed.

## Context/precision semantics
Use the following interpretation:

- `CANONICAL_TOKEN`: exact DS/token exists in supplied/resolved authority. The selected value must match it and cite its source.
- `UPSTREAM_VALUE`: exact value/rule is supplied by user/upstream contract but is not necessarily a DS token. Preserve it exactly.
- `EXPLORATORY_PROPOSAL`: no canonical value exists and a concrete proposal is useful. It must be labeled `PROPOSED_NOT_CANONICAL`.
- `RELATIVE_GUIDANCE`: no canonical value exists and exact units would create false precision. A clear relational rule is acceptable.

Do not penalize an exploratory proposal merely because it lacks a canonical token. Penalize false authority, unnecessary blocking, or vagueness when stronger context was actually available.

## Hard semantic failures
Fail even if deterministic validation passes when any applies:
- reproduces, inverts or amplifies the diagnosed defect;
- chooses the wrong member of a duplicate pair to remove, leaving the diagnosed duplication/hierarchy problem unresolved;
- adds or shows another duplicate when duplication is the diagnosed issue and no explicit source requires it;
- converts payment registration/receipt availability into debt cancellation, settlement or closure without explicit authority;
- increases spatial separation between a selected method and its CTA when that separation is the issue;
- introduces `Liquidación garantizada al pagar`, guaranteed debt elimination, fake expiry or equivalent unsupported claim;
- drops a required adjacent qualifier such as `Simulación referencial sujeta a validación` while claiming upstream preservation;
- Router/direct versions of the same input prescribe contradictory material transformations;
- a supplied/resolved canonical value such as `space_24` materially applies, but the report only says `dar más aire`/`subir levemente`/equivalent without binding the exact value;
- an invented token or pixel value is represented as canonical/upstream authority;
- the worker asks the end user for information already recoverable from supplied canonical context;
- an exploratory case is blocked solely because no design token exists;
- a materially unresolved interaction/business-state ambiguity is silently invented instead of returned to the orchestrator.

## Semantic authority rule
`semantic_authority` metadata is evidence routing, not proof. The judge must open/evaluate the referenced source facts. A `source_ref` cannot make an unsupported claim valid merely by existing.

`precision_basis` follows the same rule. A label `CANONICAL_TOKEN` is invalid unless the referenced context actually supplies that token/value.

Conservative reduction is allowed when it weakens an unsupported claim without introducing a stronger one, e.g. replacing an unauthorised `Oferta hoy` with `Oferta disponible` when no expiry is evidenced.

## Ruta de Claridad regression
When upstream product context states that simulations/offers are referential and subject to validation, a passing UI spec must preserve that constraint visibly in the user-facing component/copy model. A private risk-control note such as `no guaranteed offer` is not semantically equivalent.

Expected user-visible qualifier:
`Simulación referencial sujeta a validación.`

## Context-resolution regressions
Required behavioral expectations:

1. Known token:
   - source supplies `space_24` for amount-to-divider separation;
   - report/action must use `space_24` explicitly;
   - generic `dar más aire` alone => `FAIL_CONTEXT_NOT_USED`.

2. Exploratory no-token:
   - no DS/token source exists;
   - `24px` may be proposed only as `EXPLORATORY_PROPOSAL / PROPOSED_NOT_CANONICAL`;
   - or use `increase one spacing level` as `RELATIVE_GUIDANCE`;
   - blocking only because token is missing => `FAIL_UNNECESSARY_BLOCK`.

3. Material interaction ambiguity:
   - whether CTA is active/disabled materially changes behavior and no source resolves it;
   - return to orchestrator with preferred interaction/product source;
   - silently choosing either state as canonical => `FAIL_UNSUPPORTED_STATE_DECISION`.

4. Partial context holdout:
   - use known spacing token exactly;
   - keep unknown low-risk visual tuning as proposal;
   - escalate only the unresolved material interaction rule.

## Verdicts
- `PASS_INDEPENDENT_SEMANTIC`
- `FAIL_DEFECT_DIRECTION_INVERTED`
- `FAIL_SEMANTIC_DECISION`
- `FAIL_UNSUPPORTED_CLAIM`
- `FAIL_ADJACENT_CONSTRAINT_NOT_PRESERVED`
- `FAIL_CONTEXT_NOT_USED`
- `FAIL_FALSE_CANONICAL_AUTHORITY`
- `FAIL_UNNECESSARY_BLOCK`
- `FAIL_UNSUPPORTED_STATE_DECISION`
- `FAIL_LF_SAFETY`
- `FAIL_ROUTER_DIRECT_DIVERGENCE`
- `FAIL_NOT_IMPLEMENTABLE`
- `BLOCKED_SOURCE_INSUFFICIENT`

## Output
Return:
- `verdict`
- `action_results[]` with the eleven checks above
- `source_refs[]`
- `blocking_codes[]`
- `router_direct_consistency`
- `adjacent_constraints_preserved[]`
- `unsupported_claims[]`
- `directionality_failures[]`
- `context_precision_findings[]`
- `next_gate`

This judge does not declare mergeability or runtime authorization.
