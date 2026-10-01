# POST_PASE_ROUTER_V1

Source-only consumer for `SADM-PP-L4-019`.

## Responsibility

`POST_PASE_ROUTER_V1` owns **applicability only**. It consumes the canonical target set anchored by `lf_eventos #19549`, validates source currentness, converts already-declared effects/scopes into one immutable `LF_POST_PASE_PLAN_V1`, and stops.

It does not execute controls, inspect control internals, collect evidence, choose owner/runner/carrier, promote assets, mutate lifecycle, deploy, cut over or activate production.

## Input

- valid `ORCHESTRATOR_EXECUTION_GUARD_V1` entry from the source PASE orchestrator;
- exact merge SHA + repository/branch identity;
- current `CURRENTNESS_AUTHORITY` receipt;
- exact changed/anchor paths for GitHub reconciliation;
- optional authority readback scopes already declared by upstream governance;
- optional runtime/deploy verification scope already declared by the effect owner.

The router never discovers these scopes by repository-wide or database-wide scanning.

## Applicability

Canonical target set from `#19549`:

1. `GITHUB_RECONCILIATION` — always REQUIRED for the merged changeset and exact declared paths.
2. `AUTHORITY_READBACK` — REQUIRED only when `authority_scopes` is non-empty, otherwise NOT_APPLICABLE.
3. `RUNTIME_DEPLOY_VERIFICATION` — REQUIRED only when a runtime/deploy effect scope is declared, otherwise NOT_APPLICABLE.
4. `FINAL_EVIDENCE` — always REQUIRED.
5. `CLOSURE_GATE` — always REQUIRED.

These rules select capabilities and scopes only. Downstream capability semantics remain in their own contracts.

## Immutable plan

`LF_POST_PASE_PLAN_V1` contains exact capability codes, disposition, bounded scope, per-scope digest, controls digest, merge/currentness anchors and one canonical `plan_digest`. The digest uses `$SELF` normalization for its own plan-digest cross-binds; verifier recomputes the same preimage.

No owner/runner/carrier fields are emitted.

## Source reuse

- `TARGET_CAPABILITY_SET_EVENT#19549`
- `CURRENTNESS_AUTHORITY@1.0.0`
- `GITHUB_RECONCILIATION_V1`
- `AUTHORITY_READBACK_V1`
- `RUNTIME_DEPLOY_VERIFICATION_V1`
- `FINAL_EVIDENCE`
- `CLOSURE_GATE`

## Materialization

Source-only. Registry projection is fail-closed until the declared source-only dependencies are materialized. This unit performs no Supabase apply, promotion, cutover, runtime or production action.

## Test

`PYTHONPATH=. python sandbox/lf_contract_gate_test/post_pase_router/test_post_pase_router_v1.py`
