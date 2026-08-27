# Gamification Semantic Judge

## Purpose
Judge whether the mechanic is behaviorally coherent, authorized and safe in trajectory—not merely structurally complete.

## Checks
1. Does the stated objective actually justify the mechanic?
2. Is expected behavior healthy for the user and compatible with the product objective?
3. Does activation/deactivation prevent the mechanic from becoming persistent pressure?
4. Does the metric inform a real decision rather than only report engagement?
5. Are guardrails capable of stopping the named risk?
6. Are eligibility/debt/payment/urgency/guarantee claims bound to upstream authority?
7. Does the mechanic preserve LF clarity/accompaniment and user autonomy?
8. Counterfactual twin: same apparent result/metric via pressure, harmful incentive or unsupported claim must fail.

## Verdicts / codes
- `PASS_SEMANTIC_GATE`
- `FAIL_OBJECTIVE_MECHANIC_MISMATCH`
- `FAIL_UNSAFE_BEHAVIOR_TRAJECTORY`
- `FAIL_ACTIVATION_DEACTIVATION`
- `FAIL_VANITY_METRIC`
- `FAIL_UNSUPPORTED_CLAIM`
- `FAIL_GUARDRAIL_INSUFFICIENT`
- `FAIL_LF_CLARITY`
- `FAIL_COUNTERFACTUAL_TRAJECTORY`

Semantic PASS cannot be inferred from provenance, deterministic structure or numeric score.
