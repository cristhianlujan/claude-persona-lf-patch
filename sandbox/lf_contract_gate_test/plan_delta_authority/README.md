# LF_PLAN_DELTA_AUTHORITY_READBACK_V1 producer

## Purpose

SADM-PP-L6-025 closes the missing independent producer required by `PLAN_AUTHORITY_DRIFT_GUARD` without creating a new plan engine, store, capability registry or runtime path.

Flow:

`explicit LF_GOVERNANCE authorization event -> fn_lf_plan_delta_authority_readback_v1 -> LF_PLAN_DELTA_AUTHORITY_READBACK_V1 -> PLAN_AUTHORITY_DRIFT_GUARD`

The producer is a read-only authority adapter over the existing append-only `public.lf_eventos` evidence surface.

## Authority boundary

The function accepts an exact event id plus the expected `plan_id`, `previous_plan_digest` and `next_plan_digest`. It returns an authorization receipt only when the event is an LF_GOVERNANCE plan-delta authorization and every requested identity exactly matches the event payload.

Required event semantics:

- `evento_tipo = DECISION_ESTRATEGICA`;
- `entidad_tipo = PROGRAM_PLAN`;
- payload `authority = LF_GOVERNANCE`;
- payload `decision = AUTHORIZED_PLAN_DELTA`;
- payload `authorization_scope = PLAN_DELTA_AUTHORITY`;
- payload `plan_id`, `previous_plan_digest` and `next_plan_digest` equal the requested values;
- the event id is the delta authority event id consumed by the drift guard.

The function never creates or edits an authorization event. Therefore a delta cannot authorize itself by calling the producer. The independent authority decision must already exist in the append-only evidence stream.

## Receipt

Successful output:

- `schema_version = LF_PLAN_DELTA_AUTHORITY_READBACK_V1`;
- `authority = PLAN_AUTHORITY`;
- `decision = AUTHORIZED_PLAN_DELTA`;
- exact `event_id`, `plan_id`, `previous_plan_digest`, `next_plan_digest`;
- deterministic `receipt_digest` compatible with `PLAN_AUTHORITY_DRIFT_GUARD_V1` canonical SHA-256.

Any missing event, scope mismatch, authority mismatch, decision mismatch, plan mismatch or digest mismatch returns a fail-closed receipt with `decision = PLAN_DELTA_NOT_AUTHORIZED` and no successful proof fields.

## Reuse / non-goals

Reuses:

- `LF_GOVERNANCE` as administrative authorization authority;
- `public.lf_eventos` as existing append-only evidence surface;
- immutable plan anchor and existing `PLAN_AUTHORITY_DRIFT_GUARD`;
- existing `pgcrypto` SHA-256 support.

Does not:

- create a table or ledger;
- create a new capability/current pointer;
- execute runtime or deploy;
- activate production;
- modify plan anchors;
- generate authorization from local shape;
- authorize a delta merely because its hashes are well formed.

## Files

- `plan_delta_authority_v1.py`: deterministic reference implementation.
- `plan_delta_authority_contract_v1.json`: authority contract.
- `test_plan_delta_authority_v1.py`: focused deterministic regression.
- `supabase/migrations/20261001174500_lf_plan_delta_authority_readback_producer_v1.sql`: governed materialization.
- `PLAN_DELTA_AUTHORITY_READBACK_rollback_v1.sql`: exact rollback script, not executed by this unit.

## Expected test

`python sandbox/lf_contract_gate_test/plan_delta_authority/test_plan_delta_authority_v1.py`

Expected terminal marker: `PASS_PLAN_DELTA_AUTHORITY_V1 checks=12`.
