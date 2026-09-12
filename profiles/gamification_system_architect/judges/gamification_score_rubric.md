# Gamification Score Rubric

Total: 25 points. Minimum PASS: 22/25 plus `ETHICAL_PASS`.

## 1. Behavioral clarity — 5
- 5: target behavior is observable, useful and tied to a clear completion signal.
- 3: behavior is useful but needs minor clarification.
- 1: behavior is vague.
- 0: behavior is absent.

## 2. Ethical financial safety — 5
- 5: autonomy, clarity, emotional safety, financial-context sensitivity and LF no-pressure controls are explicit.
- 3: controls exist but one control needs tightening.
- 1: controls are present but too generic to validate.
- 0: critical LF safety control fails.

## 3. Mission and loop quality — 5
- 5: trigger, action, feedback, progress, reward and next action form a coherent loop.
- 3: loop works but has gaps.
- 1: mostly decorative mechanics.
- 0: no real loop.

## 4. Reward and scoring integrity — 5
- 5: rewards are earned by observable useful actions, limited, clear and recoverable.
- 3: reward exists but needs more limits or recovery controls.
- 1: reward is vague, mostly decorative or weakly tied to behavior.
- 0: reward fails LF integrity checks.

## 5. Handoff and traceability — 5
- 5: next worker can continue without inventing, and source-to-decision traceability is present.
- 3: useful but needs interpretation.
- 1: weak handoff.
- 0: no usable handoff.

## Blocking rules
- Any 0 in Ethical financial safety blocks the pipeline.
- Critical LF control findings block even if numeric score is high.
- Scores without evidence are invalid.
- A final PASS requires schema compliance, judge pass, traceability and handoff readiness.

## Evidence rule
Each score must cite the output field or example that supports it. A claimed control with no field evidence scores 0 for that criterion.

## Research basis
- Internal LF: clarity, wellbeing, no-pressure and traceability rules.
- Own repo: UI Architect and Quality Pack 25-point rubric pattern.
- External official: evaluated skill outputs.
- External comparable: scoring/state mechanics from comparable systems.
- Critical/risk: user wellbeing and financial-context controls.
- Adapted into: `judges/gamification_score_rubric.md`.
- Reason for location: scoring criteria must be auditable separately from the mini judge.
