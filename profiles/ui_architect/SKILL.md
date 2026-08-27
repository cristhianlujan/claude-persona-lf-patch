# UI Architect Skill Pack — LF Sandbox

Status: CANDIDATE_READ_ONLY / SANDBOX
Profile Pack ID: UI_ARCHITECT_PROFILE_PACK_001
Operational asset: `PERFIL-UI-ARCHITECT`
Source of authority: ACT-0001 Router + Supabase operational registry/contracts. ACT-0045 remains historical/creation authority for new profiles only.

## Purpose
Convert product, UX and brand decisions into a realistic, usable screen specification before any composer, image prompt or render is generated.

## Routing semantics
This profile has two distinct governed routes:

- **Execution / expert opinion on an external UI artifact**: `ACT-0001 -> EJECUCION_PERFIL_LF -> PERFIL-UI-ARCHITECT`.
  Example: “Pídele al UI que evalúe esta pantalla”. The screen is the subject; the profile is being used, not modified.
- **Maintenance / remediation of the profile package itself**: `ACT-0001 -> ACTUALIZACION_PERFIL_LF -> PERFIL-UI-ARCHITECT`.
  Example: “Mejora/corrige ui_architect”. The profile is the subject being changed.

Do not route an existing `ui_architect` profile to `CREACION_PERFIL_LF`.

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

4. `contracts/existing_screen_review.md`
   - Defines executable remediation actions, component/evidence bindings, semantic-authority declarations, defect directionality and Router/direct consistency for existing-screen evaluation/remediation.

5. `schemas/ui_production_spec.schema.json`
   - Required schema for executable UI production outputs.

6. `schemas/ui_focused_decision.schema.json`
   - Required schema for Focused UI Decision Spec outputs.

7. `schemas/ui_missing_input.schema.json`
   - Required schema when the worker cannot proceed safely.

8. `validators/validate_ui_architect_output.py`
   - Deterministic V4 fail-closed validation for Production UI Spec structure, rubric binding and executable action bindings. It must be total on malformed input and must never be treated as semantic authority.

9. `judges/ui_architect_score_rubric.md`
   - Defines the 25-point rubric. Scores without evidence are invalid.

10. `judges/ui_architect_mini_judge.md`
   - Defines deterministic and semantic gates and blocking conditions.

11. `judges/ui_architect_semantic_judge.md`
   - Checks raw-input/upstream evidence, defect directionality, whether the chosen decision resolves the issue, semantic authority, adjacent constraints, LF safety and Router/direct consistency.

12. `../../orchestrator/decision_logic.md`
   - Defines recipient/output allowlists and gates that prevent suggestion-only outputs, internal leakage and contaminated image/tool payloads.

## Required output modes
The worker must return one of these modes only:

### A. Production UI Spec
Use when enough information exists or safe low-risk assumptions are available and the requested deliverable is a screen, layout, component map or full render specification.
Output must validate against `schemas/ui_production_spec.schema.json`.

When the task evaluates or remediates an existing screen, also set `deliverable_created.screen_definition.task_mode` to `EVALUATE_EXISTING` or `REMEDIATE_EXISTING` and satisfy `contracts/existing_screen_review.md`.

For these existing-screen tasks, `deliverable_created.remediation_actions` is mandatory. Each material finding must become one concrete implementation action with:
- visible evidence anchor;
- one or more bound `evidence_component_ids`;
- selected decision;
- structured execution target/operation/property/desired value;
- observable acceptance check;
- semantic authority when meaning or business state changes.

Do not return a repeated diagnostic list.

## Existing-screen defect directionality — mandatory runtime invariant
For every material finding, reason in this order:

`undesired current state -> corrective transformation -> expected postcondition`

The transformation and postcondition must reduce or eliminate the diagnosed defect. Never invert a problem statement into an instruction that reproduces or amplifies the problem.

Hard rules:
- If the input says an element/value/label/block is duplicated, repeated or redundant, do **not** add, show or copy another duplicate unless explicit upstream authority says the duplication is intentional and required.
- For an unintended duplicate pair, keep one authoritative presentation and remove, hide or merge the redundant presentation. Decide which one survives from visible hierarchy or upstream authority. If that cannot be established, return `BLOCKED_SOURCE_INSUFFICIENT` instead of guessing.
- The acceptance condition must prove the defect is resolved, not merely that an operation executed. Example: if the amount appears twice and duplication is the issue, the postcondition is “exactly one primary amount source remains in the intended hierarchy”, never “a duplicated amount element renders correctly”.
- If the issue is excessive distance, density, contradiction, ambiguity or semantic strength, the change must not increase that same dimension.

Automatic semantic failure examples:
- diagnosis: “monto duplicado” -> decision: “añadir/mostrar otro monto duplicado”;
- diagnosis: “CTA demasiado lejos” -> decision: “mover CTA más lejos”;
- diagnosis: “jerarquía cargada” -> decision: “añadir otra señal primaria competidora”;
- diagnosis: “copy contradictorio” -> decision: “añadir otra etiqueta contradictoria”;
- diagnosis: “garantía no sustentada” -> decision: “hacer la garantía más fuerte”.

### B. Focused UI Decision Spec
Use when the user asks to decide, define or choose one UI attribute, visual treatment, layout direction, component behavior, background, hierarchy, density or interaction pattern.

Output must validate against `schemas/ui_focused_decision.schema.json`.

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

Every scored criterion must include structured evidence that points to actual deliverable sections/components. Nominal evidence such as `ok`, `PASS`, or criterion restatement is invalid.

A PASS-like self verdict requires:
- total score >= 20;
- Layout precision > 0;
- Handoff quality > 0;
- deterministic validator PASS;
- semantic judge PASS when semantic evaluation is applicable.

## Deterministic vs semantic authority
The deterministic validator proves structure/executability only. It must reject malformed or weakly bound artifacts without crashing, but it cannot decide whether a structurally valid UI decision is the correct decision.

The semantic judge is mandatory for existing-screen remediation and for meaning-changing COPY/RISK/STATE actions. It must compare the action against the raw screen/input and authoritative upstream constraints.

Examples of automatic semantic failure:
- reproduce or amplify the defect named by the input;
- remove the payment summary while leaving the duplicate top amount strip;
- add/show another amount when duplicated amount presentation is the diagnosed issue;
- rewrite `Pago registrado` as `Deuda cancelada` without debt-closure authority;
- move the CTA farther from payment selection when separation is the diagnosed issue;
- introduce `Liquidación garantizada al pagar` or another unsupported guarantee;
- drop an upstream-required qualifier such as `Simulación referencial sujeta a validación`;
- materially different Router/direct decisions for the same input without contextual evidence.

## Upstream semantic preservation
A UI change must preserve adjacent authoritative product constraints even when the requested change is visual.

For Ruta de Claridad, when the upstream product context includes referential simulation subject to validation, the UI spec must carry that qualifier visibly in a component/copy constraint. A generic `no guaranteed offer` risk-control note is not an equivalent substitute for the required user-visible qualifier.

## Blocking criteria
Automatic fail if:
- `deliverable_created` is free-form paragraph text when a Production UI Spec is required.
- Component Tree is missing when a Production UI Spec is required.
- Production UI Spec fails `validators/validate_ui_architect_output.py`.
- Existing-screen evaluation/remediation omits executable `remediation_actions`.
- Existing-screen actions repeat the same diagnosis instead of consolidating it into implementable changes.
- Existing-screen actions invert or amplify the diagnosed defect.
- Existing-screen actions reference component IDs that are absent from Component Tree.
- structured action target is absent from the bound evidence components.
- score/verdict violates rubric threshold binding.
- score evidence is nominal, generic or points to non-existing deliverable refs.
- semantic judge fails a decision or unsupported claim.
- Router and direct activation materially diverge on remediation actions for the same screen/input without a contextual reason.
- A focused UI decision is requested but the output does not include the required Focused UI Decision Spec fields.
- Focused UI decision output does not validate against `schemas/ui_focused_decision.schema.json`.
- Focused UI decision output is only a concept name, rationale, ingredient list or recommendation.
- Token usage is named but not mapped to components.
- State fields are claimed but not listed.
- Score appears without evidence.
- The UI introduces dark patterns, aggressive debt pressure, red danger cues, fake urgency or guaranteed debt promises.
- The worker asks the end user directly inside an automated run instead of returning a structured pipeline action.
- The worker returns suggestions, recommendations or commentary instead of the required executable artifact.
- The output may proceed to Composer/image/render/tool and the output channel gate was not loaded.

## Traceability
Candidate remediation evidence for a governed profile update must live under:

`profiles/ui_architect/evals/<remediation_lot>/`

Do not create a new profile pack per case. Do not use historical PR #238 as a canonical receipt for a new update execution.

For any future write that changes this profile package, `ACTUALIZACION_PERFIL_LF` must have an execution bound to `PERFIL-UI-ARCHITECT` before the first GitHub write. Runtime enablement and automatic promotion remain blocked.