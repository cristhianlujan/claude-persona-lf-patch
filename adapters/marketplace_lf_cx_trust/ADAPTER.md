---
name: marketplace-lf-cx-trust
type: ADAPTER
canonical_asset: ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531
binds_profile: PERFIL_CX_TRUST_EXPERIENCE_ARCHITECT_LF
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.2-candidate
quality_standard: ADAPTER_QUALITY_V2
---
# ADAPTER_MARKETPLACE_LF_CX_TRUST

Purpose: bind the governed CX/Trust Experience profile to Marketplace LF context without creating an autonomous Marketplace worker or manufacturing trust claims.

Activation: Router/orchestrator only, for Marketplace trust review, clarity of promises, perceived-risk objections, support continuity or transparency work. Direct naming is not invocation; unbound work loads zero adapter payload.

Authority: current Marketplace facts, governed promises/support policies and supplied evidence outrank historical examples. Adapter cannot manufacture guarantees, debt/payment status, settlement outcomes, legal certainty or service commitments.

Inputs: Marketplace asset, user-facing promise, trust/risk friction and LF restrictions; optional feedback, reputational evidence and support incidents.

Output: `state`, `marketplace_cx_trust_binding`, `lf_adapter_invocations`. Binding contains source refs, promise boundary, prioritized trust risks, transparency improvements, protected claims/guardrails, downstream dependencies and blockers.

States: `BOUND`, `BOUND_CANDIDATE_ONLY`, `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`, `BLOCKED_UNSUPPORTED_TRUST_CLAIM`, `BLOCKED_SOURCE_CONFLICT`.

Hard fail: unsupported guarantee/claim, material missing authority, source conflict, lost trust guardrails, missing/duplicate LF invocation evidence, separate adapter model call, or implied runtime/production readiness.

Efficiency: compact runtime capsule in the same specialist execution; full package stays outside ordinary model context.

Fixtures are contract evidence only. Live PASS requires receipt-bound canonical canaries showing exactly-once applicable invocation and zero payload when unbound.

Lifecycle remains candidate/read-only/runtime-disabled/production-blocked.