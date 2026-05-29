# Sandbox Run Input — Frontend Prototype Architect LF

Case ID: home_ruta_claridad_001
Status: SANDBOX_READ_ONLY / NO_RUNTIME / NO_VALIDATED
Profile: `profiles/frontend_prototype_architect_lf/`

## Operational route
Router → Supabase / public.v_lf_fuente_operativa → ACT-0051 SECURITY_HOLD rerun → Product Director output → UI Architect output → Frontend Prototype Architect → Mini Judge → Closure.

## Sources
- Product Director: `sandbox_runs/product_director_lf/home_ruta_claridad_001/worker_output.json`
- UI Architect: `sandbox_runs/ui_architect/home_ruta_claridad_001/worker_output.json`
- Visibility pack: `sandbox_runs/visibility/home_ruta_claridad_001/render_prompt_v0.1.md`

## Task
Produce an `HTML_SANDBOX_SPEC` for a static local browser prototype of the `Tu Ruta de Claridad` section.

## Must preserve
- One primary CTA: `Ver si tengo una oferta`.
- Route intent: `/simulador`.
- Section role: orientation bridge, not simulator/dashboard/offer page/data capture.
- Warm premium fintech tone.
- Desktop web 16:9 light mode.
- No runtime, no production, no VALIDATED.

## Must not include
- Backend/API/database/auth/deployment.
- Real or sensitive user data.
- Payment or tracking integrations.
- Full app behavior.
- Production or Golden Screen status.
