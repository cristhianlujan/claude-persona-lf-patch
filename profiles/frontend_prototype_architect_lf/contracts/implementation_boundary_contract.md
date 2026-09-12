# Contract — Implementation Boundary

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/frontend_prototype_architect_lf/SKILL.md`

## Purpose
Keep Frontend Prototype Architect inside the sandbox frontend prototype boundary.

## Allowed
- Static HTML.
- Static CSS.
- Inline SVG if needed for visual structure.
- Minimal vanilla JavaScript only for non-data UI behavior if explicitly required.
- Local browser preview instructions.
- Accessibility baseline such as landmarks, headings, focus states, contrast intent and reduced-motion handling.

## LF Shell adapter boundary
For an LF screen, load and apply:

`adapters/lf_shell_profile_adapter/ADAPTER.md`

Before materializing the prototype:
- consume the resolved `shell_binding` or resolve it through the adapter when canonical context is available;
- implement only `SCREEN_SLOT` and `SCREEN_COMPONENT` targets marked executable;
- preserve every `SHELL_LOCKED` target and the resolved Design System bindings;
- preserve Product Director intent and UI Architect hierarchy, states, Component Tree, remediation actions and precision provenance;
- if the requested implementation would require a Shell change, return `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED` rather than recreating or overriding the Shell;
- a `CANDIDATO` Shell remains candidate-only and cannot be promoted by the prototype.

The adapter does not authorize Supabase writes. Its canonical references are read inputs supplied/resolved by the orchestrator.

## Not allowed
- Backend services.
- API calls.
- Authentication.
- Database reads or writes.
- Supabase writes.
- Drive writes.
- Payment integrations.
- Analytics/tracking.
- Production deployment.
- Runtime enablement.
- VALIDATED marking.
- Real user data or sensitive data.
- Recreating a canonical LF Shell locally as a new source of truth.
- Modifying `SHELL_LOCKED` targets as a screen-level implementation delta.

## Handoff rule
The prototype must preserve upstream Product Director and UI Architect decisions. If implementation requires changing product scope, visual hierarchy, claim boundaries, CTA intent or a protected LF Shell target, return to the orchestrator instead of inventing a change.