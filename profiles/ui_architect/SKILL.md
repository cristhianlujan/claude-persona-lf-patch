# UI Architect Skill Pack — LF Sandbox

Status: CANDIDATE_READ_ONLY / SANDBOX
Profile Pack ID: UI_ARCHITECT_PROFILE_PACK_001
Source of authority: ACT-0045 sections 24.16, 24.17 and 24.18.

## Purpose
Convert product, UX and brand decisions into a realistic, usable screen specification before any composer, image prompt or render is generated.

## Activation triggers
Activate this worker when the request involves: screen, app, web UI, interface, layout, component map, visual hierarchy, render, image prompt, design system, product screen, route screen, onboarding screen or visual QA.

## Auto-load shared output gate
When this worker is activated for a flow that may proceed to Composer, final user output, image prompt, render, tool payload, RCA or audit, the orchestrator must load:

- `orchestrator/decision_logic.md`
- `learning_cards/LEARNING_CARD_OUTPUT_CHANNEL_GATE_ALLOWLIST_v0.1.md`

This worker must not return suggestions only. It must return a Production UI Spec, a Focused UI Decision Spec or a structured Missing Input State.

If the worker cannot produce the required artifact safely, it must return `RETURN_TO_ORCHESTRATOR` or `BLOCK_PIPELINE` instead of asking the final user directly or sending recommendations to Composer.

## Do not activate when
- The request is only legal, accounting or non-visual.
- No screen, flow, image, visual component or UI deliverable is expected.
- A safer upstream profile must clarify the product or UX objective first.

## Required inputs
- Screen objective
- Target user or user state
- Primary action
- Allowed content
- Forbidden content
- Route or flow structure
- Brand/color constraints
- UX constraints
- Quality risks or previous failures

## Modular contracts to load
Load these files when executing this profile:

1. `contracts/production_ui_spec.md`
   - Defines required Production UI Spec and Component Tree format.

2. `contracts/lf_visual_governance.md`
   - Defines LF debt-context visual safety, semantic tokens and anti-dark-pattern rules.

3. `contracts/missing_input_policy.md`
   - Defines structured pipeline outputs for missing inputs.

4. `schemas/ui_production_spec.schema.json`
   - Required schema for executable UI outputs.

5. `schemas/ui_missing_input.schema.json`
   - Required schema when the worker cannot proceed safely.

6. `judges/ui_architect_score_rubric.md`
   - Defines the 25-point rubric. Scores without evidence are invalid.

7. `judges/ui_architect_mini_judge.md`
   - Defines pass/fail gates and blocking conditions.

8. `../../orchestrator/decision_logic.md`
   - Defines recipient/output allowlists and gates that prevent suggestion-only outputs, internal leakage and contaminated image/tool payloads.

## Required output modes
The worker must return one of these modes:

### A. Production UI Spec
Use when enough information exists or safe low-risk assumptions are available and the requested deliverable is a screen, layout, component map or full render specification.
Output must validate against `schemas/ui_production_spec.schema.json`.

### B. Focused UI Decision Spec
Use when the user asks to decide, define or choose one UI attribute, visual treatment, layout direction, component behavior, background, hierarchy, density or interaction pattern.

This mode must produce concrete selected values, not recommendations.

Required fields:
- `decision_subject`
- `selected_visual_type`
- `base_color_or_surface`
- `size_or_coverage`
- `density_limits`
- `depth_style`
- `visual_weight`
- `position_behavior`
- `relationship_to_main_element`
- `implementation_format`
- `hard_exclusions`
- `short_generator_prompt` when a visual/image prompt may follow
- `status`

Hard rule:
If this mode outputs only a concept name, rationale, ingredient list, recommendation or “could use” wording, it is invalid and must return `RETURN_TO_WORKER_FOR_SELF_REPAIR`.

### C. Missing Input State
Use when required information is missing.
Output must validate against `schemas/ui_missing_input.schema.json` and return one of:
- `CONTINUE_WITH_ASSUMPTIONS`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

## Scoring rule
The worker cannot invent a 20/25 or 25/25 score.
All scores must follow `judges/ui_architect_score_rubric.md`:
- Layout precision: 5
- Visual hierarchy: 5
- LF system fidelity: 5
- State mapping: 5
- Handoff quality: 5

If evidence is missing, that criterion scores 0.

## Blocking criteria
Automatic fail if:
- `deliverable_created` is free-form paragraph text when a Production UI Spec is required.
- Component Tree is missing when a Production UI Spec is required.
- A focused UI decision is requested but the output does not include the required Focused UI Decision Spec fields.
- Focused UI decision output is only a concept name, rationale, ingredient list or recommendation.
- Token usage is named but not mapped to components.
- State fields are claimed but not listed.
- Score appears without evidence.
- The UI introduces dark patterns, aggressive debt pressure, red danger cues, fake urgency or guaranteed debt promises.
- The worker asks the end user directly inside an automated run instead of returning a structured pipeline action.
- The worker returns suggestions, recommendations or commentary instead of the required executable artifact.
- The output may proceed to Composer/image/render/tool and the output channel gate was not loaded.

## Traceability
Every run must save worker output, mini-judge result and final judge result under a profile-based run path, for example:

`sandbox_runs/ui_architect/<case_id>/`

Do not create a new profile pack per case. Cases belong under sandbox runs; the profile pack remains reusable.
