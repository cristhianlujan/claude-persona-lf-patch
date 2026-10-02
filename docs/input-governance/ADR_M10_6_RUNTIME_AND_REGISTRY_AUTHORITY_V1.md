# ADR — M10.6 runtime and registry authority v1

Status: `DECIDED / NON-PRODUCTION`  
Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Unit: `M10.6 / PAULO-010`

## Context

M10.6 must make documentation match the registered Input Governance state without creating a second authority or promoting runtime candidates.

Observed canonical state:

- Input Governance domain/runtime inventory is represented in `public.lf_activos` and `public.lf_activo_relaciones`.
- `public.lf_capability_registry` is a transversal-capability registry, not a duplicate inventory for Input Governance domain assets.
- The three core Input Governance Edge functions and the direct Profiles governance caller have concrete Supabase Edge Function bindings.
- `programacion.fn_input_governance_worker_spec(...)` resolves those role-specific runtime bindings and can report `BOUND_RUNTIME`.
- `INPUT_GOVERNANCE_EXECUTION_CONTRACT` revision `1.5` retains fail-closed semantic-runtime requirements for new or changed scope.

## Decision

1. **No duplicate capability registry.** Input Governance domain/runtime assets remain governed by `public.lf_activos` + `public.lf_activo_relaciones`. Only transversal reusable capabilities belong in `public.lf_capability_registry` / `public.lf_capability_current`.
2. **Materialize runtime binding as inventory metadata.** The four governed runtime assets record `metadata.runtime_binding_status = BOUND_RUNTIME`, their provider and exact Edge Function reference.
3. **Do not promote runtime state.** `runtime_estado` remains `CANDIDATE_READ_ONLY`; the binding metadata does not authorize deploy, production, promotion or cutover.
4. **Preserve contract semantics.** `BOUND_RUNTIME` at worker/inventory scope does not erase the execution contract's semantic-runtime fail-closed requirements. These are different scopes and must not be conflated.
5. **Keep one contract authority.** `programacion.contratos` remains canonical for live contract specifications. Git JSON files are frozen versioned snapshots and `lf_activos` registrations provide traceability, not a competing contract store.
6. **Final verification stays in L9.** M10.6 pre-L9 work may prepare and read back the documentation/registry/runtime state, but L9 final verification remains a separate authorized checkpoint.

## Consequences

- Consumers can resolve a concrete governed runtime without assuming production activation.
- Runtime binding status is visible in the canonical asset inventory and can be read back deterministically.
- Transversal capability governance remains reusable and non-duplicated.
- Contract/runtime discrepancies must be interpreted by scope before being classified as drift.
- Any future change to canonical contract semantics still requires its own governed contract revision/change path; this ADR does not mutate contract `1.5`.

## Evidence anchors

- `INPUT_READINESS_CONTRACT`: `programacion.contratos` id `37`, revision `5.13`.
- `INPUT_FRESHNESS_DELTA_CONTRACT`: id `39`, revision `1.0`.
- `INPUT_GOVERNANCE_EXECUTION_CONTRACT`: id `42`, revision `1.5`.
- Runtime binding migration: `supabase/migrations/20261002230000_input_governance_m10_6_runtime_binding_status_v1.sql`.
- Exact migration Git blob: `1a13a82b77aecf3708b7310360bbef527d2109e5`.
- M10.6 readback evidence: `lf_eventos#19988`, `#19989`, `#19990`, `#19992`.
