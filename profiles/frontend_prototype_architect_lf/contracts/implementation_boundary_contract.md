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

## Handoff rule
The prototype must preserve upstream Product Director and UI Architect decisions. If implementation requires changing product scope, visual hierarchy, claim boundaries or CTA intent, return `RETURN_TO_ORCHESTRATOR` instead of inventing a change.