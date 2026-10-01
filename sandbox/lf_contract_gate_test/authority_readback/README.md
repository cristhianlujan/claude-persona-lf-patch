# AUTHORITY_READBACK_V1

## Purpose

`SADM-PP-L2-013` extracts the read-only portion of post-merge authority validation into one bounded transversal capability.

Flow:

`caller -> ORCHESTRATOR_EXECUTION_GUARD_V1 -> AUTHORITY_READBACK -> declared domain adapters -> CURRENTNESS_AUTHORITY when required -> LF_AUTHORITY_READBACK_RECEIPT_V1`

Without `ORCHESTRATOR_ENTRY_ACCEPTED`, the capability fails closed.

`POST_PASE_ROUTER_V1` is a later consumer unit (`SADM-PP-L4-019`), so this candidate defines only the capability-specific scope contract. It does not invent applicability or a global POST_PASE plan.

## Currentness anchors reused

The bounded currentness readback for this unit starts from the persisted Phase 03 handoff and current plan state. No repository-wide rediscovery or historical digest reconstruction is part of this capability.

Reusable authority already present:

- `CURRENTNESS_AUTHORITY@1.0.0` for source/currentness decisions.
- `CAPABILITY_EXECUTION_CONTRACT` for orchestrated request/receipt cross-binding.
- `ORCHESTRATOR_EXECUTION_GUARD_V1` for guarded entry.
- `EDGE_FN_RUN_GITHUB_READBACK_PERFIL_LF` as an observed read-only domain adapter candidate.

## Contamination removed

EKB `POST-PASE-AUTHORITY-READBACK-MUTATION-COUPLING-001` proves that existing profile reconciliation functions combine readback with mutation and/or next-gate routing:

- `public.lf_profile_update_post_merge_reconcile_v1`
- `public.lf_profile_runtime_refresh_reconcile_asset_v1`

They remain untouched as governed mutation operations. They are not used as the generic readback engine.

`AUTHORITY_READBACK_V1` forbids:

- mutation of `lf_activos` or any canonical authority;
- rebind/promotion;
- next-gate selection;
- applicability decisions;
- gate recording;
- deploy/runtime/production effects.

## Adapter model

The engine does **not** hardcode domain adapter codes.

The router/orchestrator declares exact checks in `LF_AUTHORITY_READBACK_SCOPE_V1`. Each domain adapter returns a normalized `LF_AUTHORITY_ADAPTER_OBSERVATION_V1` containing:

- exact `check_id`;
- adapter code;
- subject and authority references;
- observed source revision;
- `AUTHORITY_MATCH` / mismatch decision;
- explicit `read_only=true`;
- explicit `mutation_performed=false`;
- deterministic receipt digest;
- `CURRENTNESS_AUTHORITY` receipt when the declared check requires it.

Undeclared observations and missing observations fail closed.

## Receipt

`LF_AUTHORITY_READBACK_RECEIPT_V1` returns:

- `READBACK_VERIFIED`, `ready=true` only when every declared check matches;
- `READBACK_FAILED`, `ready=false` otherwise;
- typed failures per check;
- deterministic receipt digest;
- explicit `mutation_performed=false`, `promotion_performed=false`, `next_gate_selected=false`.

The receipt is evidence only. It is not authority to mutate, promote, rebind or choose the next gate.

## Test

`python sandbox/lf_contract_gate_test/authority_readback/test_authority_readback_v1.py`

Expected:

`PASS_AUTHORITY_READBACK_V1 checks=16`

The matrix covers guarded entry, exact scope, missing/extra observations, adapter/subject/authority/revision mismatch, read-only enforcement, mutation/routing contamination, stale currentness and digest tampering.

## Materialization state

Source candidate only. The registry projection is included for later governed application/readback but is **not applied by this unit**.

No Supabase apply, owner-runner cutover, runtime activation, deploy, production activation or legacy retirement is authorized here.
