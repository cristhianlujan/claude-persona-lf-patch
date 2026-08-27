# Gamification System Spec Contract

## Required output
Return `GAMIFICATION_SYSTEM_SPEC` only when safe, source-authorized inputs exist.

Preserve the existing system fields and require additionally:
- `material_mechanics[]`;
- `claims[]`;
- `system_lineage`.

## Material mechanic contract
Every material mechanic requires:
- `mechanic_id`;
- `objective`;
- `mechanic`;
- `expected_behavior`;
- `activation_condition`;
- `deactivation_condition`;
- `acceptance_check`;
- `risk` and `risk_flags`;
- `metric_id`;
- `guardrails`;
- `authority_refs`.

This materializes `objective -> mechanic -> behavior -> risk -> metric -> guardrail`; no link may be inferred by the next worker.

## Metric contract
Each metric requires `metric_id`, `name`, `business_objective`, `decision_use` and `target_signal`. `VANITY_ONLY` cannot justify a material mechanic.

## Claim contract
Every material financial claim declares `claim_type`, `claim_text`, `status`, and where relevant `authority_ref`. Eligibility, debt, payment, urgency and guarantee claims without authority are blocked.

## Reward contract
`reward_policy.healthy_action` must name the observable healthy action earning the reward. `harmful_financial_incentive` must be explicitly false for a PASS candidate.

## Hard fail
Narrative-only output, missing target behavior, missing activation/deactivation, ambiguous metric use, unsupported financial claim, harmful reward, pressure/dark-pattern trajectory, missing guardrails, or handoff invention.
