# Contract — Production UI Spec

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: profiles/ui_architect/SKILL.md

## Purpose
UI Architect must produce a production-grade UI specification before any composer, prompt generator or image render can proceed.

This contract is generic and reusable. It defines how a UI specification becomes executable. It must not contain project-specific brand, marketplace, debt-context or business rules; those belong in project contracts or adapters.

## Mandatory deliverable_created format
`deliverable_created` must be a Component Tree, not free text.

Required top-level keys:
- `screen_definition`
- `component_tree`
- `layout_grid`
- `visual_hierarchy`
- `state_map`
- `token_map`
- `spacing_typography`
- `density_rules`
- `risk_controls`
- `prompt_constraints`

Render-ready outputs should also include:
- `visual_reference_spec`
- `visual_prompt_variants`
- `negative_prompt_constraints`
- `render_acceptance_criteria`
- `post_render_qa`

## Component Tree minimum
Each component node must include:
- `zone_id`
- `component_id`
- `component_type`
- `role`
- `content`
- `visual_priority`
- `color_tokens`
- `typography`
- `spacing`
- `state`
- `allowed_variants`
- `blocked_variants`

## Required UI production fields
1. Layout/grid: desktop/mobile assumption, max width, columns, zones and proportions.
2. Component map: exact visible components and their roles.
3. Visual hierarchy: ranked elements and why each has that weight.
4. States: active, secondary, disabled, hover, informational and risk states where applicable.
5. Tokens by component: semantic token use, not just token names.
6. Spacing and typography: approximate size, padding, gap, radius and shadow rules.
7. Density rules: max CTAs, max zones, max cards, max text per card and saturation controls.
8. Risk controls: how to avoid landing page, dashboard, catalog, dark pattern or decorative drift.
9. Prompt constraints: exact constraints that composer must preserve.

## Render-readiness fields
Use these fields when the next step may be visual prompt generation, image generation, UI mockup rendering or creative variation.

### `visual_reference_spec`
Defines the visual target without relying on vague style words. It should include:
- reference purpose;
- composition model;
- focal point;
- camera or viewport assumption when relevant;
- lighting or surface treatment when relevant;
- depth, layering or spatial rhythm;
- fidelity level;
- what must remain functional, not decorative.

### `visual_prompt_variants`
Provide 2 to 3 controlled prompt directions when useful:
- `baseline_safe`: closest faithful render of the UI spec.
- `craft_upgrade`: improves composition, hierarchy and polish without changing structure.
- `exploration_controlled`: explores one visual variable only, while preserving layout, states and constraints.

### `negative_prompt_constraints`
List what the renderer or composer must avoid. This is not a place for project-specific rules unless injected by adapter. Generic examples:
- unreadable or invented UI text;
- deformed hands, faces, icons or UI controls;
- fake charts or metrics not specified;
- inconsistent spacing between repeated components;
- decorative elements that compete with primary action;
- generic AI-looking premium dashboard patterns.

### `render_acceptance_criteria`
Define how the rendered output will be accepted or rejected:
- hierarchy matches `visual_hierarchy`;
- layout matches `layout_grid` and `component_tree`;
- primary action is visible and singular when required;
- text is legible at target size;
- component states remain recognizable;
- no visual artifacts alter meaning;
- output can proceed to quality review without composer inventing structure.

### `post_render_qa`
After a render exists, the reviewer must check:
- structural fidelity;
- typography and legibility;
- density and cognitive load;
- prompt-constraint compliance;
- artifact detection;
- whether a self-repair pass is required.

## Input-output visual learning case
When a render is used as evidence for future improvement, store the learning as a generic case with:
- `input_spec_summary`
- `visual_prompt_used`
- `output_result`
- `accepted_or_rejected`
- `reason`
- `repair_instruction`

Do not store project-specific identity, customer data or business context inside generic reusable examples.

## Hard fail
The output fails if `deliverable_created` is a paragraph, if component tree is missing, if a field is marked true without evidence, or if a render-ready output does not define enough constraints for the next visual worker to proceed without inventing structure.
