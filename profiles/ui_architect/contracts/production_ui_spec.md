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
- `supported_visual_decisions`
- `unsupported_visual_additions`
- `blocking_handoff`

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
10. Supported visual decisions: every major visual decision that may appear in the final output, with its source from the user request, upstream product decision, brand system, UX requirement or approved assumption.
11. Unsupported visual additions: visual ideas, metaphors, objects, scenery, claims, metrics or decorative elements that are not supported by the contract and must not be introduced downstream.
12. Blocking handoff: if a visual risk can contaminate the final output, UI Architect must mark it as blocking and route it to Composer and Quality Pack. It cannot be left as a passive observation.

## Supported vs unsupported visual translation
UI Architect must translate abstract product intent into concrete UI components. The translation must stay inside the product-interface layer unless the upstream contract explicitly authorizes a literal illustration, scene, mascot, landscape, chart, metric or external object.

For each high-risk visual concept, define:
- `source_concept`: the word or intent received.
- `approved_ui_translation`: the component, layout, state or interaction that represents it.
- `unsupported_visual_additions`: what must not be added because it is not in the contract.
- `composer_instruction`: what Composer must preserve.
- `judge_block_if_seen`: what Quality Pack must block if it appears later.

This is a generic abstraction-control requirement. It must not be written for one case or one screen.

## Visual output requirements
Use this only when the next output is an image prompt or rendered UI mockup. Do not create a separate visual layer for this requirement.

`visual_output_requirements` must define:
- `layout_preservation`: canvas, zones, proportions, spacing and component order that must not change.
- `hierarchy_preservation`: primary focal point, secondary elements and visual priority order.
- `legibility_preservation`: text size, contrast, maximum density and prohibition of unreadable or invented UI text.
- `state_preservation`: active, disabled, loading, empty, error or success states that must remain visible when relevant.
- `composition_constraints`: alignment, whitespace, balance, focal area and elements that must not compete with the primary action.
- `artifact_constraints`: no distorted UI controls, malformed icons, invented metrics, fake charts, random glyphs, unsupported visual additions or generic dashboard drift.
- `acceptance_criteria`: conditions that make the prompt/render acceptable or rejected.

`prompt_constraints` must reference these requirements when image generation or rendering is requested.

## Hard fail
The output fails if `deliverable_created` is a paragraph, if component tree is missing, or if a field is marked true without evidence.

When image generation or rendering is requested, the output also fails if `prompt_constraints` do not protect layout, hierarchy, legibility, states, visual drift and unsupported visual additions.

If `unsupported_visual_additions` or `blocking_handoff` is empty while the request contains ambiguous visual concepts, the output must return `RETURN_TO_ORCHESTRATOR` or `BLOCK_PIPELINE`, not PASS.
