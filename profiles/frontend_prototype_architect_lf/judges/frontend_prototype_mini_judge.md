# Frontend Prototype Architect LF Mini Judge

## Purpose
Validate that Frontend Prototype Architect produced a safe, static, reviewable sandbox prototype specification without crossing into production or backend scope.

## Required checks
1. Product Director source exists.
2. UI Architect source exists.
3. Output validates against the expected schema.
4. Prototype is static HTML/CSS by default.
5. Local run instructions are present.
6. Accessibility baseline is present.
7. Interaction states are basic and safe.
8. Forbidden runtime scope is explicit.
9. No API, auth, database, tracking, payment, deployment, runtime or real data is introduced.
10. Handoff can be used for sandbox HTML creation or QA review.

## Automatic FAIL conditions
- Missing Product Director or UI Architect source.
- Backend/API/database/auth/deployment is introduced.
- Sensitive or real user data is used.
- Product scope, CTA, claims or UI hierarchy are changed.
- Runtime, production or VALIDATED is implied.
- Accessibility baseline is absent.
- Score appears without evidence.

## Verdicts
- `PASS_TO_SANDBOX_HTML`
- `RETURN_TO_ORCHESTRATOR`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `BLOCK_FRONTEND_SCOPE`

## Research basis
- Internal LF: ACT-0001, ACT-0045 and corrected CREACION_PERFIL_LF flow.
- Own repo: UI Architect, Product Director, Quality Pack and sandbox visibility patterns.
- Frontend boundary: static prototypes only unless separate approval changes the boundary.