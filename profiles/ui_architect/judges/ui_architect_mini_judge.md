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
6. Required project contracts or adapters were respected when loaded.
7. Handoff can be used by composer without inventing.
8. If the next step is visual prompt, image render or UI mockup generation, render-readiness fields are sufficient.

## Render-readiness checks
When applicable, verify:
- `visual_reference_spec` exists or the handoff explicitly says render is not requested;
- `negative_prompt_constraints` exist and are concrete;
- `render_acceptance_criteria` define acceptance/rejection checks;
- prompt constraints do not rely on vague adjectives only;
- the render worker would not need to invent layout, focal point, hierarchy or composition;
- post-render QA route is explicit when a rendered artifact will be reviewed.

## Automatic FAIL conditions
- `only_suggested = true`
- component tree missing
- score present without evidence
- state fields claimed true but not listed
- token usage named but not mapped to components
- no prompt constraints
- render requested but no render acceptance criteria
- visual prompt requested but no negative prompt constraints
- output is mostly generic adjectives without component-level evidence
- project-specific safety contract or adapter violation
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

## Generic blocking codes
- `COMPONENT_TREE_MISSING`
- `SCORE_WITHOUT_EVIDENCE`
- `STATE_MAPPING_MISSING`
- `TOKEN_MAPPING_MISSING`
- `PROMPT_CONSTRAINTS_MISSING`
- `RENDER_ACCEPTANCE_CRITERIA_MISSING`
- `VISUAL_REFERENCE_SPEC_MISSING`
- `NEGATIVE_PROMPT_CONSTRAINTS_MISSING`
- `GENERIC_AI_STYLE_LANGUAGE_ONLY`
