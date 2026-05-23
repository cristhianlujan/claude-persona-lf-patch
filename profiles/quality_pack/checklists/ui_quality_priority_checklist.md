# Checklist — UI Quality Priority

Status: GENERIC_REUSABLE_CHECKLIST
Applies to: Quality Pack before Composer, prompt, render or impact.

## Purpose
Give Quality Pack an ordered review path so it does not evaluate UI only by taste.

## Priority order

### P0 — LF safety and scope
- No financial pressure, shame, urgency manipulation or guaranteed outcomes.
- No red danger cues for debt contexts.
- No internal metadata leakage: workers, PASS, scores, GitHub, Supabase, logs, sandbox.
- Register matches artifact: product screen is not judged as landing; guided flow is not dashboard.

### P1 — Accessibility basics
- Text contrast is readable.
- Interactive elements have visible states.
- Labels are understandable without relying only on color.
- Focus/keyboard path is plausible for interactive UI.
- Touch/click target size is reasonable when applicable.

### P2 — Task clarity
- One primary next action is clear.
- User can understand what to do in under 5 seconds.
- Copy does not repeat headings unnecessarily.
- No more decisions than the screen objective requires.

### P3 — Component completeness
- Component tree exists.
- Tokens, typography, spacing, states and blocked variants are mapped by component.
- Layout grid, visual hierarchy and density rules are explicit.

### P4 — Responsive and interaction assumptions
- Desktop/mobile assumption is declared.
- Overflow, empty, loading, disabled or error states are considered when relevant.
- Hover-only behavior is not required for core understanding.

### P5 — Visual craft
- Spacing has rhythm.
- Cards are not used as lazy defaults.
- Hierarchy is created by scale, spacing and weight.
- Motion, if present, clarifies rather than decorates.

### P6 — Handoff readiness
- Composer can proceed without inventing structure.
- Prompt/render constraints are explicit.
- Remaining risks are named and routed.

## Verdict guidance
- If P0 fails: BLOCK_PIPELINE.
- If P1 or P2 fails: RETURN_TO_WORKER_FOR_SELF_REPAIR.
- If P3 fails: RETURN_TO_WORKER_FOR_SELF_REPAIR.
- If only P5 has minor issues: PASS_WITH_RESTRICTIONS.
