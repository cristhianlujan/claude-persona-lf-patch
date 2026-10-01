# AUTHORITY_READBACK_V1

## Purpose

`SADM-PP-L2-013` extracts post-merge authority validation into one bounded transversal **read-only** capability.

Flow:

`caller -> ORCHESTRATOR_EXECUTION_GUARD_V1 -> AUTHORITY_READBACK -> declared domain adapter -> READ-ONLY verification -> LF_AUTHORITY_READBACK_RECEIPT_V1`

Without `ORCHESTRATOR_ENTRY_ACCEPTED`, the capability fails closed. `POST_PASE_ROUTER_V1` remains the later applicability/continuation owner.

## FAST_LOOKUP_MAP preflight

Per events `#19595/#19597`, this correction starts with `inventory.fn_lookup_v2` and only expands when live drift is demonstrated.

The bounded Supabase inventory for L2-013 is:

| Function | Live shape | Classification |
|---|---|---|
| `public.lf_control_system_qualification_readback_v1` | STABLE, JSONB, no DML, no lock, no next-gate | `DIRECT_REUSE` |
| `programacion.fn_assert_worker_direct_readback_v2` | STABLE, no DML, fail-closed, returns void, verifier-specific | `REFERENCE_ONLY_NOT_GENERIC` |
| `public.lf_profile_update_post_merge_reconcile_v1` | VOLATILE + DML + `FOR UPDATE` + next-gate | `EXTRACT_REQUIRED` |
| `public.lf_profile_runtime_refresh_reconcile_asset_v1` | VOLATILE + DML + `FOR UPDATE` + next-gate | `EXTRACT_REQUIRED` |

Fingerprints and exact object refs are recorded in `authority_readback_inventory_v1.json`. They are evidence, not runtime hardcodes.

## Canonical reusable pattern

`public.lf_control_system_qualification_readback_v1` is the direct reusable pattern:
- stable/read-only;
- validates exact identity/cardinality;
- fails closed on drift;
- returns typed JSONB;
- does not mutate or decide the next gate.

The generic engine preserves this separation. It does not duplicate the qualification authority.

## Profile extraction

The legacy Profile functions stay untouched as mutation operations. Their **verification-only** portions are extracted into:

- `PROFILE_UPDATE_AUTHORITY_READBACK`
- `PROFILE_RUNTIME_REFRESH_AUTHORITY_READBACK`

Implementation: `authority_readback_adapters_v1.py`.

The adapters only observe supplied read-only snapshots and emit `LF_AUTHORITY_ADAPTER_OBSERVATION_V1`. They never:
- update `lf_activos`;
- acquire `FOR UPDATE`;
- rebind/promote;
- choose `post_merge_next_gate`;
- deploy or activate runtime.

## Generic engine

`authority_readback_v1.py` remains domain-agnostic. The scope declares:
- check ID;
- adapter code;
- subject;
- authority;
- expected source revision;
- whether currentness is required.

The engine validates normalized adapter observations, currentness receipts when declared, and exact scope cross-binding. Missing/extra/duplicate observations fail closed.

## Receipt

`LF_AUTHORITY_READBACK_RECEIPT_V1` emits `READBACK_VERIFIED` only when all declared checks match. Otherwise it emits `READBACK_FAILED`.

The receipt is evidence only. `POST_PASE_ROUTER/ORCHESTRATOR` owns continuation; explicit governed operations own any mutation.

## Tests

- `python sandbox/lf_contract_gate_test/authority_readback/test_authority_readback_v1.py`
- `python sandbox/lf_contract_gate_test/authority_readback/test_authority_readback_adapters_v1.py`

The correction extends the matrix with 10 adapter checks covering:
- canonical control-system readback normalization;
- control-system identity drift;
- Profile update read-only extraction;
- Profile update mismatch without mutation/next-gate;
- Profile runtime refresh read-only extraction;
- runtime source/release mismatch;
while retaining the original 16 engine checks for guarded entry/scope/currentness/digest failures.

## Materialization state

Source-only candidate. Registry projection remains unapplied.

No Supabase apply, cutover, runtime, deploy, production activation or legacy retirement is performed by this correction.
