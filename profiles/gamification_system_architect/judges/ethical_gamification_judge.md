# Ethical Gamification Judge

## Purpose
Validate LF ethical and user-safety controls before a gamification output advances.

## Required PASS checks
- User autonomy is preserved.
- User benefit is clear and understandable.
- Rewards are clear, limited and not framed as guaranteed outcomes.
- Progress is supportive, private when appropriate and recoverable.
- Financial-context assumptions are not invented.
- Completion signals are observable.
- Handoff is complete enough for UX/UI, Copy, Quality Pack, Legal/Data or Orchestrator.

## Blocking codes
- `BLOCK_UNCLEAR_REWARD`
- `BLOCK_UNSAFE_PROGRESS_MODEL`
- `BLOCK_UNSUPPORTED_FINANCIAL_CLAIM`
- `BLOCK_PUBLIC_COMPARISON_RISK`
- `BLOCK_ACTION_PRESSURE_RISK`
- `BLOCK_HIDDEN_COST_RISK`
- `BLOCK_RECOVERY_PATH_MISSING`
- `BLOCK_HANDOFF_INVENTION`

## Repairable findings
Use `ETHICAL_REPAIR_REQUIRED` when the issue can be repaired without changing product intent, for example:
- reward wording is unclear;
- recovery path is missing;
- progress feedback is too generic;
- handoff lacks evidence mapping;
- the loop needs clearer completion criteria.

## Non-repairable findings
Use `ETHICAL_BLOCK` when the requested mechanic depends on unsafe action pressure, unsupported financial claims, public comparison of sensitive status, hidden cost or unverifiable benefit framing.

## Verdicts
- `ETHICAL_PASS`
- `ETHICAL_REPAIR_REQUIRED`
- `ETHICAL_BLOCK`

## Rule
`ETHICAL_PASS` is mandatory for final PASS. If this judge returns `ETHICAL_BLOCK`, the profile must return `BLOCKED_ETHICAL_RISK` or `BLOCK_PIPELINE`.

## Research basis
- Internal LF: clarity, wellbeing, no-pressure and traceability controls.
- Own repo: Quality Pack gate pattern.
- External official: evaluation-first skill practice.
- External comparable: scoring and state patterns from comparable gamification systems.
- Critical/risk: ethical gamification and financial-context wellbeing controls.
- Adapted into: `judges/ethical_gamification_judge.md`.
- Reason for location: ethical closure must be a dedicated gate, not only a rubric paragraph.
