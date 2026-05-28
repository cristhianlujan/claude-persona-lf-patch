# Sandbox Run Input — Product Director LF

Case ID: home_ruta_claridad_001
Status: SANDBOX_READ_ONLY / NO_VALIDATED / NO_RUNTIME
Profile: `profiles/product_director_lf/`

## Operational route
Router → Supabase / public.v_lf_fuente_operativa → Active assets → Product Director LF → Mini Judge → Closure.

## Read-only sources
- ACT-0048 — DOC_PRODUCTO_HOME_RUTA_CLARIDAD_EXPERIENCIA_SIMULADOR_PAGOS_v0.2_CANDIDATO
- ACT-0049 — DOC_WIREFRAMES_HOME_RUTA_CLARIDAD_SANDBOX_v0.1_CANDIDATO
- ACT-0050 — REGISTRO_DECISIONES_HOME_PRODUCCION_CONTROLADA

## Source constraints
- Candidate/read-only sources only.
- No Drive write.
- No Supabase write.
- No runtime enablement.
- No VALIDATED marking.
- No production general enablement.

## Product question
Define the Product Direction Spec for the Home section that introduces `Tu Ruta de Claridad` and prepares users to continue toward `/simulador`, while keeping the Home block focused, safe, non-pressure, and usable by UX/UI, Copy, Legal/Data and QA.

## Known product facts from sources
- The Home block belongs to MarketPlace Libertad Financiera and is candidate/no-validated/production-blocked.
- The experience connects Ruta de Claridad with Simulador de Pagos.
- The main CTA is `Ver si tengo una oferta`.
- The main route is `/simulador`.
- Informational blocks must not request sensitive data.
- Offers must be communicated as referential and subject to validation.
- Wireframes are sandbox visual evidence, not Golden Screen and not production.

## Decision needed
Decide current MVP scope, excluded scope, acceptance criteria and handoff for Product Director LF without inventing UX layout, final copy, legal approval, technical implementation or validated production status.