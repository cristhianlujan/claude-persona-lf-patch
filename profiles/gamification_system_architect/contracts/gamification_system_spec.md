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

This materializes `objective -> mechanic -> behavior -> risk -> metric -> guardrail`; no link may be inferred by the next worker. `mechanic_id` and `metric_id` values must be unique and cross-referenced.

## Source authority contract
`system_lineage.source_refs[]` is the observed upstream source set for the system. Every material mechanic `authority_refs[]` and every claim `authority_ref` must bind to that set. A non-empty invented URI is not authority.

Eligibility, debt status, payment status, urgency and guarantee claims require an observed upstream authority reference; absence or mismatch blocks the system.

## Metric contract
Each metric requires `metric_id`, `name`, `business_objective`, `decision_use` and `target_signal`. `VANITY_ONLY` cannot justify a material mechanic.

## Claim contract
Every material financial claim declares `claim_type`, `claim_text`, `status`, and where relevant `authority_ref`. Eligibility, debt, payment, urgency and guarantee claims without observed upstream authority are blocked.

## Reward contract
`reward_policy.healthy_action` must name the observable healthy action earning the reward. `harmful_financial_incentive` must be explicitly false for a PASS candidate.

## Activation/deactivation contract
Both conditions are mandatory for every material mechanic. They cannot be the same ambiguous condition. Deactivation must provide an observable exit/recovery path without punitive loss or pressure.

## Handoff contract
`handoff_to_next` must include:
- `target`;
- `input_contract`;
- `mechanic_refs[]` covering every material mechanic;
- `guardrails_to_preserve[]` covering every material guardrail;
- `claim_authority_refs[]` carrying the authority refs required by risky financial claims.

The next worker may simplify presentation but must not drop mechanics, safety guardrails or claim authority needed to keep the system semantically safe.

## Deterministic vs semantic authority
`validators/validate_gamification_output.py` proves structure, reference integrity and deterministic safety checks only. It cannot prove that a mechanic actually resolves the objective or that a guardrail is semantically sufficient.

`judges/gamification_semantic_judge.md` and `judges/ethical_gamification_judge.md` remain separate required behavioral gates. The structural suite is not a profile execution; behavioral evidence follows `evals/remediation_20260827/behavioral_eval_protocol.md`.

## Hard fail
Narrative-only output, missing target behavior, missing/ambiguous activation/deactivation, unknown metric/source refs, invented financial authority, vanity-only decision basis, harmful reward, pressure/dark-pattern trajectory, missing guardrails, handoff loss/invention, or structural fixtures reported as RAW profile behavior.
