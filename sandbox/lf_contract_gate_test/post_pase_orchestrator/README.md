# POST_PASE_ORCHESTRATOR_V1

Source-only consumer for `SADM-PP-L4-020`.

## Responsibility

Consumes one already-validated immutable `LF_POST_PASE_PLAN_V1` from `POST_PASE_ROUTER_V1` and dispatches only rows whose disposition is `REQUIRED`, in the exact order already present in the plan.

It does not rediscover applicability, embed control logic, recalculate owner/runner/carrier, create another evidence store, promote assets, deploy, cut over, activate runtime or activate production.

## Flow

```text
LF_POST_PASE_PLAN_V1
        |
        v
POST_PASE_ROUTER_V1.verify_post_pase_plan
        |
        v
for each control in immutable plan order
        |
        +-- NOT_APPLICABLE -> skip; no dispatch
        |
        +-- REQUIRED
              |
              v
   OWNER_RUNNER_CARRIER_AUTHORITY_V1 binding readback
              |
              v
   ORCHESTRATOR_EXECUTION_GUARD_V1 accepted receipt
              |
              v
   CAPABILITY_EXECUTION_CONTRACT_V1 request
              |
              v
   canonical capability executor
              |
              v
   CAPABILITY_EXECUTION_CONTRACT_V1 receipt validation
              |
              v
   canonical receipt sink / EVIDENCE_LEDGER
              |
              +-- failure -> BLOCK immediately
              +-- success -> next plan row
```

## Important boundary

The orchestrator reads `disposition` from the immutable plan. It never recomputes whether a capability applies. `POST_PASE_ROUTER_V1` owns applicability.

The orchestrator also does not derive owner/runner/carrier. It requires a canonical binding readback for every dispatched capability. A binding that is not `RESOLVED_CURRENT_CARRIER` blocks before execution.

## Receipt chaining

Every capability request is cross-bound to:

- `orchestrator_execution_id`;
- `consumer_execution_id`;
- `plan_digest`;
- exact capability and scope from the immutable plan;
- canonical dispatch/entry-guard receipt;
- authority references;
- prior validated receipt digests;
- capability source revision.

Only execution/evidence receipts are handed to the injected canonical receipt sink. No parallel receipt table or ledger is introduced.

## Source reuse

- `POST_PASE_ROUTER_V1`
- `OWNER_RUNNER_CARRIER_AUTHORITY_V1`
- `CAPABILITY_EXECUTION_CONTRACT_V1`
- `ORCHESTRATOR_EXECUTION_GUARD_V1`
- existing `EVIDENCE_LEDGER`

## Artifact authority

Compressed CI artifacts are transport only. Terminal evidence must bind directly to GitHub run, exact head, job/check, concrete output/manifest/blob and digest. This unit neither creates nor requires a ZIP.

## Materialization

Source-only. Registry projection is fail-closed until the declared dependencies are materialized. This unit performs no Supabase apply, promotion, cutover, runtime or production action.

## Test

```bash
PYTHONPATH=. python sandbox/lf_contract_gate_test/post_pase_orchestrator/test_post_pase_orchestrator_v1.py
```

Expected: `PASS_POST_PASE_ORCHESTRATOR_V1 checks=33`.
