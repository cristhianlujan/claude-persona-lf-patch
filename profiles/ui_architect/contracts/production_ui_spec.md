# Contract — Production UI Spec V2

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
6. Spacing and typography: approximate size, padding, gap, radius and shadow rules.
7. Density rules: max CTAs, max zones, max cards, max text per card and saturation controls.
8. Risk controls: how to avoid landing page, dashboard, catalog, dark pattern or decorative drift.
9. Prompt constraints: exact constraints that composer must preserve.

## Precision-source rule
Implementation precision must be as exact as the available authority allows, without manufacturing authority that does not exist.

For material values such as spacing, component size, state behavior or layout constraints:
- when a canonical DS/token is available, use the exact token and bind it to the component/action;
- when an upstream/user value is available, preserve the exact value and source;
- when no canonical value exists and the task is exploratory, a concrete value may be proposed but must be labeled `PROPOSED_NOT_CANONICAL`;
- when exact units would imply false precision, use an explicit relative rule such as `increase one spacing level` and label it `RELATIVE_GUIDANCE`;
- do not block exploration solely because a token is absent;
- do not downgrade a known token/value into vague language such as `dar más aire`, `subir levemente` or `ajustar spacing`.

`token_map`, `spacing_typography`, relevant component `spacing`/`state`, and existing-screen `remediation_actions.precision_basis` must agree.

## Compact user-facing report
The internal Production UI Spec may remain structured and complete, but the user-facing evaluation report should be concise.

For each material finding expose only what is needed to act:
1. observation;
2. selected correction;
3. exact token/value/source when canonical or upstream;
4. `propuesta`/relative guidance label when not canonical;
5. material unresolved input only when it genuinely changes the decision.

Do not emit a super-report just because more context was loaded. Do not dump unused design tokens, internal EKB, judge data or governance metadata into the user-facing report.

Example with authority:
`Monto muy cerca del divisor → payment_amount → divider = space_24 (DS)`.

Example without authority in exploration:
`Monto muy cerca del divisor → aumentar un nivel la separación; 24px como propuesta inicial, no token canónico`.

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

## Hard fail
The output fails if `deliverable_created` is a paragraph, if component tree is missing, or if a field is marked true without evidence.

It also fails when:
- a canonical token/value is available to the run but the material handoff replaces it with vague non-executable wording;
- an exploratory proposal is presented as canonical/upstream authority;
- the profile asks the user for a value already recoverable from supplied canonical context;
- an exploratory screen is blocked only because no design token exists.

When image generation or rendering is requested, the output also fails if `prompt_constraints` do not protect layout, hierarchy, legibility, states and visual drift.
