# CONSUMER_BINDINGS_V1

Source-only integration contract for `SADM-PP-L4-021`.

## Objective

All consumers resolve capabilities through the same canonical authority and cannot bypass the binding chain.

```text
consumer
  |
  v
ORCHESTRATOR_EXECUTION_GUARD_V1
  |
  v
public.fn_lf_capability_bind_from_orchestrator_v1
  |
  +-- public.lf_capability_registry
  +-- public.lf_capability_current
  +-- OWNER_RUNNER_CARRIER_AUTHORITY_V1
  |
  v
canonical capability executor
```

No consumer owns or recalculates owner/runner/carrier. No second binding registry is introduced.

## POST-PASE binding set

`POST_PASE_ORCHESTRATOR_V1` is source-bound to the existing transversal capabilities:

- `CURRENTNESS_AUTHORITY`
- `GITHUB_RECONCILIATION`
- `AUTHORITY_READBACK`
- `RUNTIME_DEPLOY_VERIFICATION`
- `EVIDENCE_LEDGER`
- `FINAL_EVIDENCE`
- `CLOSURE_GATE`

The binding contract does not decide applicability. It receives the immutable POST-PASE plan and requires the canonical binding entrypoint for each dispatched capability.

## Reuse validation

- `PASE_ORCHESTRATOR_V1`: current source already fails closed if `binding_materialized=true` appears before its later qualified binding-aware cutover. L4-021 does not alter that carrier path.
- `ASSURANCE_EVALUATOR`: current source already declares `public.fn_lf_capability_bind_from_orchestrator_v1` behind `ORCHESTRATOR_EXECUTION_GUARD_V1`. L4-021 reuses that path; it does not create an Assurance-specific binding engine.

## Boundary

This unit is source-only. It performs no Supabase apply, capability promotion, cutover, runtime activation or production activation. Legacy execution paths remain untouched until `SADM-PP-L5-022` performs isolated, reversible, exact-head cutover work.

## Artifact authority

`PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1` applies. No ZIP is created or accepted as terminal authority. Terminal CI evidence must bind directly to GitHub run, exact head, job/check, concrete output/manifest/blob and digest.

## Test

```bash
PYTHONPATH=. python sandbox/lf_contract_gate_test/consumer_bindings/test_consumer_bindings_v1.py
```
