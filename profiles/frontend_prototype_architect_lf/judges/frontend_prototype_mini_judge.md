# Frontend Prototype Architect LF Mini Judge

## Purpose
Validate that Frontend Prototype Architect produced a safe, static, reviewable sandbox prototype specification that is semantically faithful to the current Product/UI context, not merely schema-valid.

## Required checks
1. Product Direction authority exists in the available governed context.
2. UI Architect authority exists in the available governed context.
3. Output validates against the expected schema.
4. Prototype is static HTML/CSS by default.
5. Local run instructions are present.
6. Accessibility baseline is present.
7. Every applicable interactive/data region covers `idle/default`, `loading`, `empty`, `error`, `success` and `disabled/unavailable` when relevant, or explicitly marks a state not applicable with reason.
8. Forbidden runtime scope is explicit.
9. No API, auth, database, tracking, payment, deployment, runtime or real data is introduced.
10. Handoff can be used for sandbox HTML creation or QA review.
11. For incremental requests, the output distinguishes current delta from preserved context and applies only the authoritative delta.
12. Observable acceptance criteria are bound to changed components and test UI fidelity, CTA/route preservation, state coverage, accessibility and scope boundary as applicable.
13. Contradictory inputs are resolved by authority/freshness or returned as one minimal missing decision; they are not silently blended.
14. The answer materially adapts when the current requirements change. Repeating a previous implementation despite a changed authoritative delta is FAIL.

## Semantic authority
The judge must evaluate properties/rubric criteria, not compare the candidate against one exact expected answer. Equivalent implementations may pass when they preserve the same authoritative UI/product intent and satisfy the observable criteria.

A deterministic schema/profile validator is necessary but insufficient for a semantic PASS.

## Automatic FAIL conditions
- Governed Product Direction or UI authority is genuinely unavailable after context recovery.
- Backend/API/database/auth/deployment is introduced.
- Sensitive or real user data is used.
- Product scope, CTA, claims or UI hierarchy are changed without authoritative upstream instruction.
- Runtime, production or VALIDATED is implied.
- Accessibility baseline is absent.
- Applicable loading/empty/error/success states are absent without justification.
- Acceptance criteria are generic, non-observable or not tied to changed components.
- A current requirement conflicts with the output because the worker repeated stale prior behavior.
- A conflict is silently resolved when authority is ambiguous.
- Score appears without evidence.

## Verdicts
- `PASS_TO_SANDBOX_HTML`
- `RETURN_TO_ORCHESTRATOR`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `BLOCK_FRONTEND_SCOPE`

## Research basis
- Internal LF: ACT-0001, EKB GOV-025/GOV-026/GOV-032 and governed profile-update flow.
- Own repo: UI Architect, Product Director, Quality Pack and sandbox visibility patterns.
- Frontend boundary: static prototypes only unless separate approval changes the boundary.
- Quality principle: fresh runtime output + independent property-based semantic judgement; never hardcode one exact answer.