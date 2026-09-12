# Sandbox Run Input — UI Architect LF

Case ID: home_ruta_claridad_001
Status: SANDBOX_READ_ONLY / NO_VALIDATED / NO_RUNTIME
Profile: `profiles/ui_architect/`
Source handoff: `sandbox_runs/product_director_lf/home_ruta_claridad_001/worker_output.json`

## Operational route
Router → Supabase / public.v_lf_fuente_operativa → ACT-0048/0049/0050 read-only → Product Director sandbox output → UI Architect → Mini Judge → Closure.

## Product decision to preserve
Use the Home section `Tu Ruta de Claridad` as an orientation bridge toward `/simulador`, not as a full simulator, dashboard, offer page or data-capture flow.

## Must preserve
- One primary CTA: `Ver si tengo una oferta`.
- Primary route: `/simulador`.
- Referential claim boundary: any offer or alternative is subject to validation.
- No sensitive data capture in Home.
- Orientation bridge role.

## Must not add
- Guaranteed offer.
- Full simulator.
- Dashboard.
- Multi-step form.
- Checkout flow.
- Pressure language.
- Final legal approval claim.
- Production or Golden Screen status.

## UI task
Create a section-level desktop UI specification for `Tu Ruta de Claridad` that can later feed a render prompt or HTML mockup. The output must define layout, visual hierarchy, components, states, negative constraints and evaluation criteria without inventing product scope.