# Judge — UI Architect Mini-Judge

Status: CANDIDATE_READ_ONLY / SANDBOX

## Purpose
Validate that UI Architect produced an executable UI artifact, not advice.

## Required checks
1. Required JSON fields are present for the selected output mode.
2. If output mode is `Production UI Spec`, `deliverable_created` follows Component Tree format.
3. If output mode is `Focused UI Decision Spec`, output validates against `schemas/ui_focused_decision.schema.json`.
4. If output mode is `Missing Input State`, output validates against `schemas/ui_missing_input.schema.json`.
5. 25-point rubric is calculated with evidence when scoring is used.
6. No criterion receives points without evidence.
7. Missing-input policy was followed when needed.
8. LF visual governance was respected.
9. Handoff can be used by composer without inventing.
10. If image prompt or UI mockup rendering is requested, `prompt_constraints`, `visual_output_requirements`, or `short_generator_prompt` protect layout, hierarchy, legibility, states and visual drift according to the selected output mode.

## Output mode validation

### Production UI Spec
Validate against:
- `schemas/ui_production_spec.schema.json`

Automatic fail if:
- component tree missing;
- `deliverable_created` is free-form paragraph text;
- token usage named but not mapped to components;
- state fields claimed true but not listed;
- no prompt constraints when image/render is requested.

### Focused UI Decision Spec
Validate against:
- `schemas/ui_focused_decision.schema.json`

Automatic fail if:
- required focused decision fields are missing;
- output is returned as prose instead of structured fields;
- output is only a concept name;
- output is only a rationale;
- output is only an ingredient list such as “use layers, lines, gradients, points, shadows”;
- output uses vague recommendation wording such as “could use”, “should consider”, “recommended to use” without concrete values;
- `base_color_or_surface`, `size_or_coverage`, `density_limits`, `depth_style`, `visual_weight`, `relationship_to_main_element`, `implementation_format`, or `hard_exclusions` are empty or generic;
- image/render may follow and `short_generator_prompt` is missing or still contains audit/worker/QA language.

Required blocking code:
- `FOCUSED_UI_DECISION_NOT_EXECUTABLE`

### Missing Input State
Validate against:
- `schemas/ui_missing_input.schema.json`

Automatic fail if:
- worker asks the end user directly inside automated run instead of returning pipeline action;
- missing critical input is ignored;
- worker invents high-risk product decisions.

## General automatic FAIL conditions
- `only_suggested = true`
- score present without evidence
- prompt constraints rely only on vague adjectives such as clean, modern, premium, beautiful, intuitive or professional
- dark pattern or aggressive debt/collection cue
- image/render requested but the next worker would need to invent composition, focal point, spacing or acceptance criteria

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
