# Judge — UI Architect Mini-Judge

Status: CANDIDATE_READ_ONLY / SANDBOX

## Purpose
Validate that UI Architect produced an executable UI spec, not advice.

## Required checks
1. Required JSON fields are present.
2. `deliverable_created` follows Component Tree format.
3. 25-point rubric is calculated with evidence.
4. No criterion receives points without evidence.
5. Missing-input policy was followed when needed.
6. LF visual governance was respected.
7. Handoff can be used by composer without inventing.
8. If image prompt or UI mockup rendering is requested, `prompt_constraints` include enough visual acceptance criteria to preserve layout, hierarchy, legibility and states.

## Automatic FAIL conditions
- `only_suggested = true`
- component tree missing
- score present without evidence
- state fields claimed true but not listed
- token usage named but not mapped to components
- no prompt constraints
- image/render requested but prompt constraints do not protect layout, hierarchy, legibility or state fidelity
- dark pattern or aggressive debt/collection cue
- asks end user directly inside automated run instead of returning pipeline action

## Verdicts
- `PASS`: complete, safe and usable.
- `PASS_WITH_RESTRICTIONS`: usable but requires quality review before prompt/render.
- `NEEDS_INPUT`: orchestrator must supply missing input.
- `NEEDS_ADJUSTMENT`: worker must self-repair using existing input.
- `BLOCKED`: unsafe or not executable.

## Output
Mini-judge must return:
- `verdict`
- `score_breakdown`
- `evidence_by_criterion`
- `missing_outputs`
- `blocking_codes`
- `next_gate`
