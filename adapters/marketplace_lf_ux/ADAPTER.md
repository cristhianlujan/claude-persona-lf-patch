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

## Purpose
Adapt the governed UX/Product Experience profile to Marketplace LF context without creating a Marketplace-specific autonomous worker or silently converting recommendations into product authority.

## Operational activation
Only the Router/orchestrator may resolve this adapter as applicable. Apply when `PERFIL_UX_PRODUCT_EXPERIENCE_ARCHITECT_LF` is selected for Marketplace LF work involving listing/product selection experience, purchase/selection architecture, funnel review or UX improvement prioritization.

A direct request naming the adapter is not an operational invocation. Non-applicable executions add zero adapter prompt payload.

## Authority
Current Marketplace/product/UX sources and explicit upstream objectives outrank historical examples. The adapter binds Marketplace context; it does not invent product rules, financial claims, eligibility, conversion targets or canonical UI decisions.

## Inputs
Required:
- Marketplace asset/surface;
- user objective;
- expected conversion/action;
- current LF restrictions/guardrails.

Optional: available metrics, screenshots/prototypes and user feedback.

## Output
Emit `state`, `marketplace_ux_binding`, and `lf_adapter_invocations`.

The binding contains source refs, Marketplace context, prioritized frictions, impact/effort improvements, protected constraints, downstream dependencies and blockers.

## States
- `BOUND`
- `BOUND_CANDIDATE_ONLY`
- `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`
- `BLOCKED_SOURCE_CONFLICT`
- `BLOCKED_TARGET_UNRESOLVED`

## Hard fails
Fail closed on material missing authority, conflicting governed sources, unsupported financial/product claims, loss of supplied constraints, missing invocation evidence, or any design requiring an independent adapter model call.

## Efficiency
Apply through `runtime_capsule.md` inside the same specialist execution. Do not load the full authoring package in ordinary runtime context.

## Evidence boundary
Deterministic fixtures prove contract behavior only. Live behavior additionally requires canonical execution receipts with exactly one matching `lf_adapter_invocations` entry and evidence of zero adapter payload when unbound.

## Lifecycle
Remains `CANDIDATE_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION`; no VALIDATED/runtime/production promotion is implied.