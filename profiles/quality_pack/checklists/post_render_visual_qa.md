# Checklist — Post-render Visual QA

Status: GENERIC_REUSABLE_CHECKLIST
Applies to: Quality Pack review after a UI mockup, image render or visual variation exists.

## Purpose
Evaluate the rendered artifact itself, not only the prompt or UI spec. This checklist is generic and must not contain project-specific brand, marketplace or business rules.

## Required checks

### 1. Structural fidelity
- Render matches the approved component tree.
- Main zones, proportions and layout rhythm are preserved.
- No extra dashboard, landing, catalog or decorative sections appear unless requested.

### 2. Hierarchy and focus
- Primary focal point is immediately clear.
- Primary action remains visible and dominant when required.
- Secondary elements do not compete with the main task.
- Visual weight matches the approved hierarchy.

### 3. Text and UI legibility
- Text is readable at target size.
- No invented, corrupted or nonsensical UI text.
- Labels, buttons and status text remain plausible.
- Icons do not replace required labels when meaning matters.

### 4. Artifact detection
Block or repair if the render contains:
- distorted UI controls;
- malformed icons;
- broken alignment;
- inconsistent repeated components;
- fake charts or metrics not in the spec;
- deformed hands, faces or human anatomy when people are present;
- visual noise that changes meaning.

### 5. Density and cognitive load
- Number of zones matches the screen objective.
- Cards are not repeated as lazy defaults.
- Spacing has rhythm and avoids equal-padding monotony.
- The user can identify the next step quickly.

### 6. Prompt compliance
- Positive prompt constraints are visible in the output.
- Negative prompt constraints were respected.
- Render did not drift into generic AI premium dashboard style.
- No internal worker, score, sandbox, GitHub, Supabase or pipeline metadata is visible.

## Verdicts
- `PASS_RENDER`: render is usable for downstream review.
- `PASS_WITH_RESTRICTIONS`: render is usable but needs minor manual review.
- `RETURN_TO_PROMPT_WORKER`: prompt must be repaired.
- `RETURN_TO_UI_ARCHITECT`: UI spec was insufficient.
- `BLOCK_RENDER`: unsafe, misleading or structurally invalid.

## Required output fields
- `verdict`
- `render_score`
- `structural_fidelity_findings`
- `artifact_findings`
- `legibility_findings`
- `prompt_compliance_findings`
- `repair_instruction`
- `next_gate`

## Blocking codes
- `RENDER_STRUCTURE_DRIFT`
- `PRIMARY_ACTION_LOST`
- `TEXT_ILLEGIBLE_OR_FAKE`
- `UI_CONTROL_DISTORTION`
- `UNSPECIFIED_FAKE_METRICS`
- `GENERIC_AI_DASHBOARD_DRIFT`
- `DENSITY_OVERLOAD`
- `NEGATIVE_PROMPT_VIOLATION`
