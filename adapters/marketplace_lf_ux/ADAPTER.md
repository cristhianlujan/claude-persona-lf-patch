# ADAPTER_MARKETPLACE_LF_UX

Status: `CANDIDATO / READ_ONLY / NO_HABILITADO`  
Canonical asset: `ADAPTER-MARKETPLACE-LF-UX-20260531`  
Assurance revision: `v2`

## Purpose
Bind `PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531` to Marketplace LF context without creating a second worker or allowing the adapter to become an autonomous execution surface.

## Invocation contract
Operational activation is valid only when the Router/orchestrator resolves the canonical adapter binding for the target profile. Direct naming, profile self-dispatch or a standalone adapter model call is invalid.

Canonical runtime shape:
`ACT-0001 -> EJECUCION_PERFIL_LF -> governed binding -> compact adapter capsule -> same specialist model execution -> receipt/readback`.

When not bound/enabled, adapter prompt payload is zero.

## Activation scope
Use for Marketplace LF work involving listing/selection experience, funnel friction, purchase/selection architecture, user comprehension, UX prioritization or a Marketplace-specific experience constraint.

Do not use for work with no Marketplace UX context.

## Authority
The adapter preserves, but does not create, authority. Resolve current sources in this order:
1. current Marketplace/product authority;
2. explicit upstream objective and constraints;
3. current UX evidence/feedback/metrics;
4. noncanonical proposal only for low-risk unresolved presentation details.

It may not invent product rules, financial claims, eligibility, debt/payment meaning, conversion targets, canonical UI tokens or Product/UI decisions.

## Minimum context
- target Marketplace asset/surface;
- user objective;
- expected action/healthy outcome;
- LF restrictions and protected constraints;
- upstream/source refs when material.

Optional: metrics, captures/prototypes, feedback and observed funnel evidence.

## Bounded output
The adapter may only contribute Marketplace-specific context needed by the specialist profile:
- relevant source refs;
- current Marketplace context;
- prioritized frictions;
- impact/effort improvement candidates;
- protected constraints;
- downstream dependencies;
- material blockers.

The specialist profile remains owner of UX reasoning. UI visual authority, product truth and financial truth remain with their respective governed owners.

## Fail closed
Block or return to orchestrator when:
- the Router binding is absent or target profile mismatches;
- material product/financial authority is missing or conflicting;
- the adapter would strengthen an unsupported claim;
- protected constraints would be lost;
- duplicate/unbound invocation evidence appears;
- capsule/context budget is exceeded;
- a second adapter LLM call would be required;
- runtime/production/VALIDATED status is implied from this candidate package.

## Runtime efficiency
Only `runtime/runtime_capsule.yaml` is eligible for prompt composition. The authoring package, schemas, judges and evals are offline quality assets. Capsule budget: <=1600 characters; global runtime budget remains governed centrally.

## Behavioral evidence boundary
Fixtures and deterministic tests prove the contract, not live behavior. Live invocation PASS requires a canonical `EJECUCION_PERFIL_LF` receipt with exactly one `lf_adapter_invocations` record when the binding is enabled/applicable and zero adapter context when not enabled/unbound.

## Lifecycle
This package does not enable runtime or production. Promotion requires separate governed evidence and authorization.