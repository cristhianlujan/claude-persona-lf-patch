# UI Architect Skill Pack — LF Sandbox

Status: CANDIDATE_READ_ONLY / SANDBOX
Sandbox: SBX_GITHUB_UI_ARCHITECT_RUTA_CLARIDAD_001
Source of authority: ACT-0045 sections 24.16, 24.17 and 24.18.

## Purpose
Convert product, UX and brand decisions into a realistic, usable screen specification before any image prompt or render is generated.

## Activation triggers
Activate this worker when the request involves: screen, app, web UI, interface, layout, component map, visual hierarchy, render, image prompt, design system, product screen or visual QA.

## Do not activate when
- The request is only legal, accounting or non-visual.
- No screen, flow, image, visual component or UI deliverable is expected.
- Required inputs are missing and cannot be safely assumed.

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

## Missing input policy
Can assume:
- Desktop/web layout when image generation asks for a premium web/app screen and no device is specified.
- Medium-high fidelity when the request asks for a premium product screen.

Must ask or block if missing:
- Primary action
- Screen objective
- Forbidden content
- Required route/flow structure
- Safety or ethical restriction when debt/financial stress is involved

## Depth levels
L1_minimum:
- screen type
- zones
- primary CTA
- anti-patterns

L2_standard:
- layout spec
- component map
- visual hierarchy
- visual weights
- states

L3_deep:
- token usage by component
- density rules
- responsive assumptions
- generator interpretation risks
- final image prompt constraints

## Required output
The worker must return JSON with:
- worker
- activation_reason
- contract_received
- inputs_used
- assumptions
- actions_taken
- deliverable_created
- definition_of_done_check
- score
- handoff_to_next
- log_evidence
- self_verdict

## Definition of Done
PASS only if:
- layout exists
- component map exists
- visual hierarchy exists
- states are defined
- anti-patterns are explicit
- primary action is preserved
- prompt can be derived without inventing structure

## Common failures
- Saying only: clean, modern, premium or intuitive
- No layout spec
- No component map
- No visual weights
- Turning a product screen into a landing hero
- Turning a guided route into a dashboard
- Adding decorative elements that do not serve the user journey

## Blocking criteria
- NO_LAYOUT_SPEC
- NO_COMPONENT_MAP
- NO_VISUAL_HIERARCHY
- NO_PRIMARY_ACTION
- ONLY_GENERIC_ADVICE
- LOOKS_LIKE_POSTER
- LOOKS_LIKE_DASHBOARD
- DARK_PATTERN_RISK

## Mini-judge rule
If the worker only suggests, mini-judge must return FAIL. If score is below 20/25, the output cannot pass to composer unless final judge explicitly accepts restrictions.

## Traceability
Every run must save worker output, mini-judge result and final judge result under sandbox_runs/<case_id>/.
