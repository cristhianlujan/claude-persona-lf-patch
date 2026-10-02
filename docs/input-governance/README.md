# Input Governance — canonical authority map

Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Unit: `M10.6 / PAULO-010`  
Scope: documentation/readback only. This document does not authorize promotion, deploy or production activation.

## Canonical contracts

The database remains the authority for the live contract specifications. Git contains frozen, versioned snapshots for governed consumption and traceability.

| Contract | Canonical DB authority | Revision | Frozen Git snapshot |
|---|---|---:|---|
| `INPUT_READINESS_CONTRACT` | `programacion.contratos` id `37`, `version_id=19` | `5.13` | `docs/input-governance/contracts/input_readiness_contract_v5_13.json` |
| `INPUT_FRESHNESS_DELTA_CONTRACT` | `programacion.contratos` id `39`, `version_id=19` | `1.0` | `docs/input-governance/contracts/input_freshness_delta_contract_v1_0.json` |
| `INPUT_GOVERNANCE_EXECUTION_CONTRACT` | `programacion.contratos` id `42`, `version_id=19` | `1.5` | `docs/input-governance/contracts/input_governance_execution_contract_v1_5.json` |

The three frozen snapshots are also registered as governed `CONTRACT` assets in `public.lf_activos` and linked from `EDGE_FN_INPUT_GOVERNANCE_AGENT_V1` with material `FUENTE_RECTORA` relations. The registration does not replace `programacion.contratos` as canonical authority.

## Runtime bindings

The governed execution surfaces are:

- `SUPABASE_EDGE_FUNCTION:input-governance-agent-v1`
- `SUPABASE_EDGE_FUNCTION:input-governance-curator-v1`
- `SUPABASE_EDGE_FUNCTION:input-governance-validator-v1`
- `SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1`

M10.6 materializes their inventory/transport binding as `metadata.runtime_binding_status = BOUND_RUNTIME` in `public.lf_activos`. This is a binding/readback fact only: the four assets remain `runtime_estado = CANDIDATE_READ_ONLY`; no promotion or production activation is implied.

The worker-spec field and the execution-contract semantic-runtime field have different scopes. `programacion.fn_input_governance_worker_spec(...)` may resolve a concrete Edge runtime and report `BOUND_RUNTIME`; `INPUT_GOVERNANCE_EXECUTION_CONTRACT` revision `1.5` still retains its fail-closed semantic-runtime requirements for new or changed scope. M10.6 does not relax or overwrite those requirements.

## Registry boundaries

- Domain/runtime assets and their material dependencies: `public.lf_activos` + `public.lf_activo_relaciones`.
- Transversal reusable capabilities: `public.lf_capability_registry` + `public.lf_capability_current`.
- M10.6 does not duplicate Input Governance domain assets into the transversal capability registry.

## Currentness and verification

- Readiness run currentness is determined only by `programacion.fn_input_readiness_run_is_current*`; `status=COMPLETED` plus `invalidated_at IS NULL` is not sufficient.
- Persistent DB changes follow R16 Git-first governance and exact source/ledger readback.
- Final L9 verification is a separate checkpoint and is not performed or authorized by this document.

## Supporting documents

- `docs/input-governance/ADR_M10_6_RUNTIME_AND_REGISTRY_AUTHORITY_V1.md`
- `docs/input-governance/r16_git_first_database_governance.md`
- `docs/input-governance/curator_contract_v1.md`
- `docs/input-governance/typed_uncertainty_contract_v1.md`
- `gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md`
- `docs/ig-cv-refactor/L0_M0.12.md`
- `docs/ig-cv-refactor/L0_M4.1.md`
