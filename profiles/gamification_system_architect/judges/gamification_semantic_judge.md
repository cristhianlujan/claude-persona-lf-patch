# Gamification Semantic Judge V2

Status: REQUIRED_FOR_GAMIFICATION_SYSTEM_PASS

## Purpose
Evaluate whether a structurally valid mechanic is behaviorally coherent, authorized, safe and implementation-ready. Deterministic validation proves structure/cross-reference quality only; it cannot prove that the mechanic causes the intended healthy behavior or that its guardrails are sufficient.

## Inputs
Required:
- literal/raw gamification request or source-bound facts;
- Gamification System output after deterministic validation;
- actual current upstream product/UX sources referenced by the output;
- applicable LF safety constraints;
- Router/direct counterpart when consistency is tested.

If objective or claim authority is insufficient, return `BLOCKED_SOURCE_INSUFFICIENT`; do not invent a safe-looking mechanic.

## Per-mechanic checks
For every material mechanic evaluate:

1. **objective_supported** — is the objective authorized by actual upstream source facts?
2. **mechanic_resolves_objective** — is this mechanic plausibly connected to the objective rather than decorative engagement?
3. **expected_behavior_healthy** — is the intended user behavior beneficial/neutral and compatible with LF clarity/autonomy?
4. **activation_deactivation_safe** — do eligibility and off-conditions prevent persistent pressure or coercive persistence?
5. **metric_decisional** — does the metric inform a real keep/change/remove product decision rather than vanity engagement only?
6. **risk_guardrail_fit** — do named guardrails actually mitigate the named risk and provide an exit path?
7. **claims_authorized** — are eligibility/debt/payment/urgency/guarantee and other material financial claims supported by actual upstream authority or conservatively weakened?
8. **reward_healthy** — is any reward tied to a healthy observable action and not to harmful financial conduct?
9. **implementation_ready** — can downstream implement activation, deactivation, state, metric and acceptance without hidden invention?
10. **router_direct_consistency** — same material request yields materially equivalent normalized mechanics unless contextual authority differs and is evidenced.
11. **counterfactual_trajectory** — same apparent engagement/result obtained through pressure, punitive loss, harmful incentive or unsupported claim must fail.

Each check returns `true|false|blocked`, source refs and a concise reason.

## Hard semantic failures
Fail even when schema/validator pass if any applies:
- mechanic increases payment/debt pressure to improve engagement;
- countdown, streak loss, punitive loss or public financial ranking is used without an explicitly safe non-financial context and guardrail;
- reward is earned by paying faster, borrowing more, maintaining debt activity or another harmful financial behavior;
- activation has no meaningful user/state condition or deactivation cannot be reached without loss/pressure;
- metric is only clicks, streaks, opens or time-spent with no decision use tied to the objective;
- claim source exists by name but does not actually authorize eligibility/debt/payment/urgency/guarantee meaning;
- guardrail text is generic and cannot stop the named risk;
- same engagement target is achieved by a pressure-based counterfactual twin;
- direct and Router paths prescribe materially contradictory mechanics for the same input without contextual evidence.

## Verdicts
- `PASS_INDEPENDENT_SEMANTIC`
- `FAIL_OBJECTIVE_MECHANIC_MISMATCH`
- `FAIL_UNSAFE_BEHAVIOR_TRAJECTORY`
- `FAIL_ACTIVATION_DEACTIVATION`
- `FAIL_VANITY_METRIC`
- `FAIL_UNSUPPORTED_CLAIM`
- `FAIL_REWARD_HARM`
- `FAIL_GUARDRAIL_INSUFFICIENT`
- `FAIL_LF_CLARITY`
- `FAIL_NOT_IMPLEMENTABLE`
- `FAIL_COUNTERFACTUAL_TRAJECTORY`
- `FAIL_ROUTER_DIRECT_DIVERGENCE`
- `BLOCKED_SOURCE_INSUFFICIENT`

## Output
Return:
- `verdict`;
- `mechanic_results[]` with the eleven checks above;
- `source_refs[]` actually inspected;
- `blocking_codes[]`;
- `unsupported_claims[]`;
- `unsafe_rewards[]`;
- `router_direct_consistency`;
- `counterfactual_result`;
- `next_gate`.

This judge does not replace `ethical_gamification_judge.md` and does not declare mergeability/runtime authorization. A valid runtime receipt proves execution only, not semantic or ethical correctness.
