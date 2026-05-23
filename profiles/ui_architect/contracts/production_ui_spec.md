# Contract — Production UI Spec

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: profiles/ui_architect/SKILL.md

## Purpose
UI Architect must produce a production-grade UI specification before any composer, prompt generator or image render can proceed.

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

## Hard fail
The output fails if `deliverable_created` is a paragraph, if component tree is missing, or if a field is marked true without evidence.
