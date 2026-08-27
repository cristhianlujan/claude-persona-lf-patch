# Product Director LF Semantic Judge

## Purpose
Judge whether the selected product decision is defendible from the actual sources and trajectory, not merely well-shaped.

## Semantic checks
1. Evidence-to-decision: do cited current sources support the selected decision?
2. Conflict: are contradictory sources resolved by explicit authority/currentness, otherwise blocked?
3. Constraint preservation: does the decision preserve upstream exclusions, limits and qualifiers?
4. Claim authority: are material eligibility/payment/debt/urgency/guarantee claims supported, or conservatively qualified?
5. Trade-off: when alternatives are material, is rejection reason traceable rather than aesthetic?
6. Acceptance: would the observable checks detect a wrong implementation of the chosen decision?
7. Handoff: can downstream execute without strengthening meaning or inventing missing business truth?
8. Counterfactual twin: reject the same apparent outcome when reached through unsupported assumptions, erased qualifiers or violated constraints.

## Verdicts / blocking codes
- `PASS_SEMANTIC_GATE`
- `FAIL_SOURCE_AUTHORITY`
- `FAIL_UNRESOLVED_CONFLICT`
- `FAIL_UNSUPPORTED_CLAIM`
- `FAIL_CONSTRAINT_NOT_PRESERVED`
- `FAIL_NON_ACTIONABLE_DECISION`
- `FAIL_COUNTERFACTUAL_TRAJECTORY`

Record evidence per failed check. Do not infer PASS from provenance, validator PASS or numeric score.
