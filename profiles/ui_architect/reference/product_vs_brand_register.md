# Reference — Product vs Brand Register

Status: GENERIC_REUSABLE_REFERENCE
Applies to: UI Architect before producing any UI spec.

## Purpose
Prevent the UI worker from confusing product screens with marketing/brand surfaces.

## Required classification
Before producing a UI spec, classify the target as one of:

- `PRODUCT_SCREEN`: app/product interface where design serves a task.
- `BRAND_SCREEN`: identity or campaign surface where design is part of persuasion.
- `MARKETING_SCREEN`: landing, acquisition or conversion-oriented page.
- `DASHBOARD`: monitoring, KPIs, analytics or operational status.
- `GUIDED_FLOW`: onboarding, route, step-by-step task, assisted journey.
- `FORM_FLOW`: data capture, validation, eligibility or application flow.

## Routing rules
- If the user needs to act inside a product, prefer `PRODUCT_SCREEN` or `GUIDED_FLOW`.
- If the screen sells, persuades or announces, classify as `MARKETING_SCREEN`.
- If KPIs, charts or metrics dominate, classify as `DASHBOARD`.
- If the user moves step by step with support, classify as `GUIDED_FLOW`.

## Blocking rule
If the requested output is a product or guided flow, block landing hero patterns, testimonial blocks, hero metrics, multiple CTAs, sales sections and catalog structures unless explicitly requested and approved.

## Required output field
UI Architect must include:

```json
"register_classification": {
  "register": "PRODUCT_SCREEN | BRAND_SCREEN | MARKETING_SCREEN | DASHBOARD | GUIDED_FLOW | FORM_FLOW",
  "reason": "why this classification was selected",
  "blocked_misclassifications": ["..."],
  "downstream_implications": ["..."]
}
```
