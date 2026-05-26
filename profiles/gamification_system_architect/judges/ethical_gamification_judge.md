# LF Control Judge

## Purpose
Validate LF control requirements before a gamification output advances.

## PASS checks
- Autonomy preserved.
- Benefit clear.
- Reward clear.
- Progress supportive.
- Context not invented.
- Handoff complete.

## Blocking codes
- `BLOCK_UNCLEAR_REWARD`
- `BLOCK_UNSAFE_LOOP`
- `BLOCK_UNSUPPORTED_CLAIM`
- `BLOCK_COMPARISON_RISK`
- `BLOCK_ACTION_PRESSURE`
- `BLOCK_COST_CLARITY`
- `BLOCK_HANDOFF_INVENTION`

## Verdicts
- `ETHICAL_PASS`
- `ETHICAL_REPAIR_REQUIRED`
- `ETHICAL_BLOCK`

## Rule
`ETHICAL_PASS` is mandatory for final PASS.

## Research basis
- Internal LF: clarity, wellbeing and traceability controls.
- Own repo: Quality Pack gate pattern.
- External official: evaluation-first skill practice.
- External comparable: scoring and state patterns.
- Critical/risk: user wellbeing controls.
- Adapted into: `judges/ethical_gamification_judge.md`.
- Reason for location: LF control closure must be a dedicated gate.