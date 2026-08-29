---
name: marketplace-lf-ux
type: ADAPTER
canonical_asset: ADAPTER-MARKETPLACE-LF-UX-20260531
binds_profile: PERFIL_UX_PRODUCT_EXPERIENCE_ARCHITECT_LF
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.2-candidate
quality_standard: ADAPTER_QUALITY_V2
---
# ADAPTER_MARKETPLACE_LF_UX

Purpose: bind the governed UX/Product Experience profile to Marketplace LF context without creating a Marketplace-specific autonomous worker.

Activation: Router/orchestrator only, for Marketplace listing/selection experience, purchase/selection architecture, funnel review or UX-prioritization work. Direct naming is not invocation; unbound work loads zero adapter payload.

Authority: current Marketplace/product/UX sources and explicit upstream objectives outrank examples. Adapter cannot invent product rules, financial claims, eligibility, conversion targets or canonical UI decisions.

Required inputs: Marketplace asset/surface, user objective, expected action and LF restrictions. Optional: metrics, screenshots/prototypes, feedback.

Output: `state`, `marketplace_ux_binding`, `lf_adapter_invocations`. Binding contains source refs, Marketplace context, prioritized frictions, impact/effort improvements, protected constraints, downstream dependencies and blockers.

States: `BOUND`, `BOUND_CANDIDATE_ONLY`, `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`, `BLOCKED_SOURCE_CONFLICT`, `BLOCKED_TARGET_UNRESOLVED`.

Hard fail: material missing authority, source conflict, unsupported product/financial claims, lost constraints, missing/duplicate LF invocation evidence, separate adapter model call, or implied runtime/production readiness.

Efficiency: use compact `runtime_capsule.md` inside the same specialist execution; no full-package prompt load.

Fixtures are contract evidence only. Live PASS requires receipt-bound canonical canaries showing exactly-once applicable invocation and zero payload when unbound.

Lifecycle remains candidate/read-only/runtime-disabled/production-blocked.