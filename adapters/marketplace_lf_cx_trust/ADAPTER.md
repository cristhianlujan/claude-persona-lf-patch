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

## Purpose
Adapt the governed CX/Trust Experience profile to Marketplace LF context without creating a Marketplace-specific autonomous worker or manufacturing trust claims.

## Operational activation
Only Router/orchestrator resolves applicability. Apply when the CX/Trust profile is selected for Marketplace LF work concerning trust review, clarity of promises, perceived-risk objections, support continuity or experience transparency.

A direct request naming this adapter is not an operational invocation. Non-applicable executions add zero adapter payload.

## Authority
Current Marketplace facts, governed promises, support policies and supplied evidence outrank historical examples. The adapter cannot manufacture guarantees, debt/payment status, settlement outcomes, legal certainty or service commitments.

## Inputs
Required: Marketplace asset, promise shown to the user, trust/risk friction, and LF restrictions. Optional: customer feedback, reputational evidence and support incidents.

## Output
Emit `state`, `marketplace_cx_trust_binding`, and `lf_adapter_invocations`. The binding contains source refs, promise boundary, prioritized trust risks, transparency improvements, protected claims/guardrails, downstream dependencies and blockers.

## States
- `BOUND`
- `BOUND_CANDIDATE_ONLY`
- `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`
- `BLOCKED_UNSUPPORTED_TRUST_CLAIM`
- `BLOCKED_SOURCE_CONFLICT`

## Hard fails
Fail closed on unsupported guarantees/claims, material missing authority, source conflict, loss of required trust guardrails, missing exactly-once LF invocation evidence or any design requiring an independent adapter model call.

## Efficiency
Use `runtime_capsule.md` in the same specialist execution. Do not load the full package during ordinary runtime.

## Evidence boundary
Fixtures prove contract behavior only. Live behavior requires canonical receipt-bound raw execution plus exactly-once invocation and zero-payload evidence when unbound.

## Lifecycle
Remains `CANDIDATE_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION`; no runtime/VALIDATED/production promotion is implied.