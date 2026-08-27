# Product Director LF Semantic Judge V2

Status: REQUIRED_FOR_PRODUCT_DIRECTION_PASS

## Purpose
Evaluate whether a structurally valid product decision is actually supported by the raw request and authoritative upstream sources. Deterministic validation proves shape/cross-reference quality only; it cannot prove the chosen product decision is correct.

## Inputs
Required:
- literal/raw product request or source-bound facts;
- Product Director output after deterministic validation;
- actual current upstream sources referenced by the output;
- applicable constraints/forbidden scope;
- Router/direct counterpart when consistency is tested.

If evidence is insufficient to decide a material product truth, return `BLOCKED_SOURCE_INSUFFICIENT`; do not infer a favorable decision.

## Decision-level checks
Evaluate the material selected decision against all checks:

1. **evidence_supported** — do the opened/current sources actually support the stated problem and selected decision?
2. **decision_resolves_objective** — does the selected decision solve the requested product decision rather than merely restating context?
3. **authority_resolution_valid** — are conflicting/current sources resolved by explicit authority/currentness rather than convenience?
4. **constraints_preserved** — are exclusions, limits and semantic qualifiers preserved even when they reduce commercial attractiveness?
5. **claims_authorized** — are eligibility/payment/debt/urgency/guarantee and other material claims supported by authoritative source facts or conservatively weakened?
6. **tradeoff_defensible** — when an alternative is rejected, is the reason connected to objective/risk/constraint rather than taste?
7. **acceptance_detects_wrong_implementation** — would the observable acceptance checks fail if downstream implemented a materially different product decision?
8. **handoff_implementation_ready** — can the next profile execute without inventing business truth or strengthening meaning?
9. **router_direct_consistency** — same material request produces materially equivalent normalized product decisions unless contextual authority differs and is evidenced.
10. **counterfactual_trajectory** — reject an apparently identical selected outcome when the path depends on unsupported assumptions, erased qualifiers or violated constraints.

Each check returns `true|false|blocked`, source refs and a concise reason.

## Hard semantic failures
Fail even when schema/validator pass if any applies:
- selects an attractive option that violates an explicit upstream exclusion;
- treats missing business data as permission to assume a value;
- resolves contradictory current sources without an authority/currentness basis;
- converts a referential/conditional offer into guaranteed eligibility, guaranteed debt closure or equivalent stronger claim;
- keeps the same selected decision text but changes its trajectory so required qualifiers/constraints are erased;
- acceptance criteria would still pass a materially wrong implementation;
- downstream handoff omits a qualifier needed to preserve product truth;
- direct and Router paths prescribe contradictory material scope/decision for the same input without contextual evidence.

## Source authority rule
A `source_ref` is evidence routing, not proof. The judge must evaluate the referenced source facts. Existing provenance or a non-empty URI cannot make an unsupported claim true.

A conservative reduction is allowed when it weakens an unsupported claim without inventing a stronger one.

## Verdicts
- `PASS_INDEPENDENT_SEMANTIC`
- `FAIL_SEMANTIC_DECISION`
- `FAIL_SOURCE_AUTHORITY`
- `FAIL_UNRESOLVED_CONFLICT`
- `FAIL_UNSUPPORTED_CLAIM`
- `FAIL_CONSTRAINT_NOT_PRESERVED`
- `FAIL_NON_ACTIONABLE_DECISION`
- `FAIL_ACCEPTANCE_WEAK`
- `FAIL_HANDOFF_SEMANTICS`
- `FAIL_COUNTERFACTUAL_TRAJECTORY`
- `FAIL_ROUTER_DIRECT_DIVERGENCE`
- `BLOCKED_SOURCE_INSUFFICIENT`

## Output
Return:
- `verdict`;
- `decision_checks` containing the ten checks above;
- `source_refs[]` actually inspected;
- `blocking_codes[]`;
- `unsupported_claims[]`;
- `preserved_constraints[]`;
- `router_direct_consistency`;
- `counterfactual_result`;
- `next_gate`.

This judge does not declare mergeability, runtime authorization or canonical promotion. A valid runtime receipt proves execution only, not this semantic verdict.
