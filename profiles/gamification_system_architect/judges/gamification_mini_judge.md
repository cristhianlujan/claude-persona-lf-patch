# Gamification Mini Judge

## Purpose
Validate that Gamification System Architect produced an executable, safe and handoff-ready artifact.

## Required checks
1. Output validates against the expected schema.
2. Target behavior is observable.
3. Mission loop is actionable.
4. Reward is connected to a healthy user-helpful action.
5. Ethical controls are explicit.
6. Score includes rubric evidence.
7. Handoff can be used without inventing.
8. Traceability exists.

## Automatic FAIL conditions
- Output is only narrative advice.
- Target behavior is missing.
- Reward/scoring is unclear or disconnected from action.
- Ethical controls are missing.
- Score appears without evidence.
- Handoff requires invention by UX/UI, Copy, Quality Pack or Orchestrator.
- The system uses unsafe urgency, pressure, public comparison or unclear financial meaning.

## Verdicts
- `PASS_TO_QUALITY_PACK`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

## Research basis
- Internal LF: ACT-0045 closure and handoff rules.
- Own repo: Quality Pack and UI Architect judge pattern.
- External official: skill evaluation gates.
- External comparable: gamification needs rules, state and scoring.
- Critical/risk: ethical gamification controls.
- Adapted into: `judges/gamification_mini_judge.md`.
- Reason for location: pass/fail logic belongs in the judge layer.