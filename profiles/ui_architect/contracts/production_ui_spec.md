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

Optional key when image prompt or rendered UI mockup is requested:
- `visual_output_requirements`

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
6. Spacing and typography: size/padding/gap/radius/shadow values or rules with honest precision provenance.
7. Density rules: max CTAs, max zones, max cards, max text per card and saturation controls.
8. Risk controls: how to avoid landing page, dashboard, catalog, dark pattern or decorative drift.
9. Prompt constraints: exact constraints that composer must preserve.

## Precision provenance
When specifying a material implementation value, distinguish the strongest available basis instead of converting all values into arbitrary pixel precision.

Allowed precision modes:
- `CANONICAL_TOKEN`: exact design-system/token value is supplied or resolved. Use the exact token/value and source reference.
- `UPSTREAM_VALUE`: exact user/upstream product value is supplied but is not necessarily a design-system token. Preserve it exactly and source-bind it.
- `EXPLORATORY_PROPOSAL`: no canonical value exists and a concrete value helps execution. Label it `PROPOSED_NOT_CANONICAL`.
- `RELATIVE_GUIDANCE`: no canonical value exists and exact units would create false precision; use a clear relational rule such as `increase one spacing level`.

Rules:
- canonical/upstream values override exploratory proposals for the same property;
- never present a proposed pixel value as a design-system token;
- missing a token alone does not block exploratory visual work;
- unresolved values that materially change interaction/business semantics must be routed through `contracts/missing_input_policy.md` instead of guessed;
- user-facing output should expose only the precision basis needed to implement the decision, not internal governance metadata.

## Visual direction note
For fintech product screens, UI Architect must prefer product-interface patterns over decorative scenes. Progress, guidance and achievement should be represented through layout, hierarchy, states, cards, rails, modules, badges and interaction cues. Literal scenery or narrative objects should only be used when explicitly required by the source brief and when they do not reduce product maturity.

## Visual output requirements
Use this only when the next output is an image prompt or rendered UI mockup. Do not create a separate visual layer for this requirement.

`visual_output_requirements` must define:
- `layout_preservation`: canvas, zones, proportions, spacing and component order that must not change.
- `hierarchy_preservation`: primary focal point, secondary elements and visual priority order.
- `legibility_preservation`: text size, contrast, maximum density and prohibition of unreadable or invented UI text.
- `state_preservation`: active, disabled, loading, empty, error or success states that must remain visible when relevant.
- `composition_constraints`: alignment, whitespace, balance, focal area and elements that must not compete with the primary action.
- `artifact_constraints`: no distorted UI controls, malformed icons, invented metrics, fake charts, random glyphs or generic dashboard drift.
- `acceptance_criteria`: conditions that make the prompt/render acceptable or rejected.

`prompt_constraints` must reference these requirements when image generation or rendering is requested.

When canonical/upstream precision materially constrains a render, `prompt_constraints` must preserve the applicable token/value or relational rule. Exploratory proposals must remain labeled as proposals in the spec even if the downstream prompt only receives the concrete rendering instruction.

## Hard fail
The output fails if `deliverable_created` is a paragraph, if component tree is missing, or if a field is marked true without evidence.

When image generation or rendering is requested, the output also fails if `prompt_constraints` do not protect layout, hierarchy, legibility, states and visual drift.

It also fails when:
- a supplied/resolved canonical value materially applies but is replaced by vague guidance;
- an invented or proposed value is represented as canonical/upstream authority;
- exploratory work is blocked solely because no canonical token exists;
- a materially unresolved interaction/business value is silently invented.
