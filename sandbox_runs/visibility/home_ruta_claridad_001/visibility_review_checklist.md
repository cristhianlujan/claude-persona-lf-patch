# Visibility Review Checklist — Tu Ruta de Claridad

Status: SANDBOX_VISIBILITY / NO_VALIDATED / NO_RUNTIME

Use this checklist to evaluate any image, mockup or HTML view produced from `render_prompt_v0.1.md`.

## Required PASS checks

| Check | PASS criteria |
|---|---|
| Scope | Shows only the section or a focused Home slice where `Tu Ruta de Claridad` is protagonist. |
| Viewport | Desktop web 16:9 light mode. |
| Product role | Clearly acts as an orientation bridge toward `/simulador`. |
| Main composition | Uses a progressive path/map with 3 to 4 milestone cards. |
| CTA | Has exactly one dominant CTA: `Ver si tengo una oferta`. |
| Tone | Warm, calm, adult, premium fintech. |
| Trust boundary | Includes a subtle note that alternatives/offers are referential and subject to validation. |
| Cognitive load | Breathable, not crowded, no excessive metrics or decisions at same hierarchy. |
| Data boundary | No DNI, income, phone, debt amount or sensitive data fields. |
| Claim boundary | No guaranteed offer, approval, savings or amount. |
| Visual boundary | Not dashboard, not simulator, not checkout, not flat timeline, not childish gamification. |
| Governance boundary | No Golden Screen, production or validated label. |

## Fail states

Return FAIL_VISIBILITY if:
- the section looks like a dashboard;
- the path becomes a flat timeline or checkout;
- there is more than one primary CTA;
- the mockup asks for sensitive data;
- the mockup implies guaranteed benefit;
- visual density creates cognitive overload;
- the section no longer clearly routes toward `/simulador`;
- it is labeled as production, Golden Screen or validated.

## Output expected after review

```text
VISIBILITY_REVIEW_RESULT
case_id: home_ruta_claridad_001
verdict: PASS_VISIBILITY / NEEDS_ADJUSTMENT / FAIL_VISIBILITY
blocking_findings:
observations:
next_action:
```
