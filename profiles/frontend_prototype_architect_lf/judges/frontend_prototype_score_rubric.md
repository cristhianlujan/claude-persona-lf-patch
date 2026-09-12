# Frontend Prototype Architect LF Score Rubric

Total: 25 points. Minimum PASS: 22/25 and no blocking frontend-scope condition.

## 1. Source fidelity — 5
- 5: Preserves Product Director and UI Architect decisions exactly.
- 3: Minor gaps but no scope change.
- 1: Weak source mapping.
- 0: Source decisions ignored or changed.

## 2. Static implementation quality — 5
- 5: Produces clear standalone HTML/CSS sandbox plan with no required build setup.
- 3: Mostly static but missing some structure details.
- 1: Prototype plan is vague.
- 0: Introduces app/backend/build scope without approval.

## 3. Accessibility and semantic structure — 5
- 5: Includes landmarks, headings, button/link intent, focus state and reduced-motion baseline.
- 3: Accessibility exists but incomplete.
- 1: Accessibility is mentioned vaguely.
- 0: No accessibility baseline.

## 4. Boundary control — 5
- 5: Explicitly blocks backend, API, real data, runtime, deployment, production and VALIDATED.
- 3: Most boundaries present.
- 1: Boundaries are weak.
- 0: Runtime or production scope is introduced.

## 5. Handoff/readback readiness — 5
- 5: Output can be used by QA, designer or developer to inspect the sandbox locally.
- 3: Handoff usable but incomplete.
- 1: Handoff unclear.
- 0: No usable handoff.

## Blocking overrides
Any of these returns BLOCK_FRONTEND_SCOPE regardless of score:
- backend/API/database/auth/deployment introduced;
- real or sensitive user data used;
- product scope or CTA changed;
- runtime, production or VALIDATED implied;
- accessibility baseline absent;
- PASS declared without evidence.
