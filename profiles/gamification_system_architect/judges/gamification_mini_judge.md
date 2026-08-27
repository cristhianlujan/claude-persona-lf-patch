# Gamification Mini Judge

## Evaluation order
1. Deterministic validator must pass.
2. `gamification_semantic_judge.md` must pass.
3. `ethical_gamification_judge.md` must return `ETHICAL_PASS`.
4. Apply numeric rubric only after the three gates above.

## Required checks
- observable target behavior;
- complete objective→mechanic→behavior→risk→metric→guardrail chain;
- activation, deactivation and acceptance per material mechanic;
- metric tied to a business/user objective and decision use, not vanity alone;
- healthy reward action;
- claim authority for financial states/urgency/guarantees;
- LF clarity/no-pressure preserved;
- actionable handoff and traceability;
- concrete evidence per score criterion.

## Automatic FAIL
Unsupported claim, harmful financial reward, pressure/dark pattern, punitive/public financial ranking, missing off-condition, vanity-only metric, ambiguous mechanic, contradictory LF clarity, nominal score evidence, or counterfactual twin that reaches the same metric through an unsafe trajectory.

## Verdicts
- `PASS_TO_QUALITY_PACK`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

Validator PASS or high score is necessary but insufficient.
