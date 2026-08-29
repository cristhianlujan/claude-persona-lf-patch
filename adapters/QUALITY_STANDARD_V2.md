# LF Adapter Assurance V2

Goal: match or exceed mature UI/Gamification validation discipline without turning adapters into autonomous agents or adding orchestration/model layers.

Canonical runtime shape:
`ACT-0001 Router -> EJECUCION_PERFIL_LF -> enabled canonical binding -> compact adapter capsule -> one specialist model execution -> receipt/readback`.

## Mandatory invariants
- Operational activation is `ROUTER_BOUND_ONLY`; direct naming or profile self-dispatch is not invocation.
- Adapter application never creates a second LLM call.
- Runtime prompt composition uses only `runtime/runtime_capsule.yaml`, never the full authoring package.
- Per-capsule budget is bounded (<=2,000 chars centrally; packages should be tighter when possible) and total adapter context remains centrally bounded.
- Unbound or runtime-disabled adapters contribute zero prompt payload.
- Adapter authority is narrower than its specialist profile and cannot create Product, UI, financial, legal or trust authority.
- Current canonical sources outrank examples and historical artifacts.
- Runtime receipt evidence lives under `lf_adapter_invocations` and stays distinct from the technical model-provider `adapter_id`.
- Each applied invocation binds adapter identity, assurance revision, Router binding ref, profile/target, capsule ref, capsule size and source refs.
- Deterministic validators cover identity, target, cardinality, path/budget and cross-artifact invariants.
- Semantic judges cover material authority preservation and downstream meaning.
- Positive plus adversarial/negative cases are required.
- Fixtures prove the contract only; live behavior requires a canonical runtime receipt.
- `runtime_enabled`, production enablement and `VALIDATED` promotion are separate governed decisions.

## Package baseline
A merge-ready adapter package should contain, at minimum:
- `ADAPTER.md`
- `manifest.yaml`
- `runtime/runtime_capsule.yaml`
- deterministic validator
- invocation schema
- domain binding/output schema when applicable
- adversarial evals
- semantic judge

## Lifecycle
`assurance_revision: v2` does not require changing the canonical business asset version. Existing candidate adapters may remain `version: v0.1` while their assurance contract is upgraded independently.
