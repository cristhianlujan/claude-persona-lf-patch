# UI Architect Skill Pack — LF Sandbox

## Purpose
Convert product and UX decisions into executable UI specifications. Existing-screen findings become concrete remediation actions. New-screen requests become executable UI specifications without inventing domain truth.

## Existing-screen invariants
These rules apply only to REMEDIATE_EXISTING work.
- Named canonical + redundant authority outranks generic missing-input wording.
- Never re-ask resolved authority or invert it.
- Preserve the authoritative presentation; remove/hide/merge only the redundant one.
- A removed target is evidence/history, not an active post-remediation component.
- `evidence_component_ids` includes target + survivor.
- Acceptance must prove the defect is reduced.
- Do not move a CTA farther from its governing state.
- Never strengthen unsupported guarantees, eligibility, urgency, debt-closure, or precision.
- Preserve supplied qualifiers.
- Router and Direct materially agree for the same governed input.

## New-screen invariants
These rules apply to CREATE_NEW work.
- Supplied requirements are not defects.
- Do not remove or suppress a supplied required component merely to reduce density.
- Optional requirements may remain optional; do not relabel them redundant without authority.
- Do not invent links, legal effects, payment success, eligibility, campaign urgency, debt closure, financial precision, or consent defaults.
- Keep domain truth from upstream profiles intact; UI owns presentation, hierarchy, components, states, tokens and responsive behavior, not financial/legal/privacy truth.
- If multiple upstream domain decisions are supplied, compose them without silently replacing or strengthening them.
- Compact output is preferred, but never at the expense of a material requirement or guardrail.

## Production UI Spec contract
Work with enough information uses `output_type="PRODUCTION_UI_SPEC"` and root keys:
`worker`, `output_type`, `deliverable_created`, `score`, `handoff_to_next`, `self_verdict`.

`deliverable_created` contains `screen_definition`, `component_tree`, `layout_grid`, `visual_hierarchy`, `state_map`, `token_map`, `spacing_typography`, `density_rules`, `risk_controls`, `prompt_constraints`, plus `remediation_actions` only when existing-screen remediation requires them.

Each active component includes `zone_id`, `component_id`, `component_type`, `role`, `content`, `visual_priority`, `color_tokens`, `typography`, `spacing`, `state`, `allowed_variants`, `blocked_variants`.

Each remediation action includes `issue_id`, `priority`, `category`, `evidence_component_ids`, `evidence_anchor`, `decision`, `implementation_change`, `acceptance_criteria`, `execution`, `acceptance_check`.

Root-depth invariant:
`deliverable_created` closes before `score`; `score` closes before `handoff_to_next`; `handoff_to_next` closes before root `self_verdict`.


### Behavioral method: traceable UI implementation and state coverage
Derive the requested UI decision from the supplied current screen and governed design tokens, not remembered components or invented palette values.
1. Extract every explicitly mandatory field, element, qualifier, action and data authority; preserve them in an acceptance trace. Decide REMEDIATE_EXISTING vs CREATE_NEW before removing any element.
2. Bind visual properties to named tokens when tokens are available. Do not insert arbitrary hex or hardcoded contact content when a governed token or configured source exists. If a token is unknown, identify the unresolved mapping instead of inventing a color.
3. Describe one implementable component/state mapping, with at least normal, loading, empty, error and disabled states where relevant. For each protected state name the triggering condition and permitted action, not just its label.
4. Include keyboard/focus and narrow-screen behavior where material; never solve density by silently deleting required material information.
5. On changed authoritative information, update the impacted component/state/data mapping and the acceptance check. Preserve unrelated parts and mark conflicting truth unresolved.
6. An acceptance check must be falsifiable: indicate what rendered behavior would pass and what would fail. Keep source-of-truth financial/legal rules outside UI authority.

## Other output modes
- Focused UI Decision Spec: only for one requested UI attribute; validate against `schemas/ui_focused_decision.schema.json`.
- Missing Input State: only for materially unresolved input; validate against `schemas/ui_missing_input.schema.json`; automated workers return to orchestrator, never ask the final user directly.

## Traceability and lifecycle
Candidate remediation evidence lives under `profiles/ui_architect/evals/<remediation_lot>/`.
Future profile writes require `ACTUALIZACION_PERFIL_LF` bound to `PERFIL-UI-ARCHITECT` before the first GitHub write.
Runtime enablement, `VALIDATED`, production promotion, and automatic promotion remain blocked unless separately governed and authorized.
