# FULL_REGRESSION

Canonical identity: `FULL_REGRESSION` / `TRANSVERSAL_FULL_REGRESSION`.

## Estado y owner

- Owner: `LF_GOVERNANCE`.
- Tipo: transversal CI plan consumer/verifier.
- Estado operativo en Supabase: `READ_ONLY`; runtime `NO_HABILITADO`.
- F04: source qualification only. No cutover, runtime activation or production activation is authorized here.

## Propósito

Verify a governed CI applicability plan and compatible carrier receipts without deciding applicability, expanding the plan, or executing controls owned elsewhere.

Required invariants:

- `local_applicability_decisions = 0`
- `parallel_applicability_engine = 0`
- `run_everything = false`
- `full_regression_semantics = CONSUME_GOVERNED_PLAN_ONLY`
- `planned_controls = executed_controls`
- zero unplanned, duplicate and retired-control execution.

## Authority

Applicability is resolved upstream by `CHANGESET_GOVERNANCE_LF_V1 + LF_CI_EXECUTION_PLAN_V2`.
`FULL_REGRESSION` consumes that decision. It must not replace the router, registry, currentness authority or carrier owners.

Operational identity and structural relationships live in Supabase (`public.lf_activos`, `public.lf_activo_relaciones`). GitHub is source authority for this contract and implementation.

## Inputs

- governed `lf-ci-execution-plan/v2`;
- one compatible `lf-ci-carrier-receipt/v1` per carrier actually present in `carrier_controls`;
- optional exact source revision and retired-control set.

## Outputs

`lf-full-regression-receipt/v1` bound to the plan SHA, planned/executed controls and consumed receipt digests.

`required_controls=[]` means `NOT_APPLICABLE` with zero carrier receipts and zero execution.

## Fail closed

Block on missing/invalid plan, unresolved applicability, stale source authority, unresolved carrier, missing/extra/duplicate/wrong-SHA receipt, planned/executed mismatch, duplicate execution or retired-control execution.

Invalid or unresolved evidence must never fall back to “run everything”.

## Physical source

- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py`
- `sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_currentness_bridge_v1.py`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json`
- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_shared_ci_control_ownership_registry_v1.json`

## Carrier compatibility boundary

The impact registry still contains historical logical carrier IDs (`LF_CONTRACT_CHECK`, `VALIDATE_LF_PACKS`, `LF_DB_REGRESSION`). F04 does not reactivate removed historical workflows and does not remap carrier execution ownership. `FULL_REGRESSION` only verifies the carrier partition supplied by the governed plan. Any physical carrier cutover/remap belongs to its governed activation phase, not this source-qualification lot.

## Lifecycle

`CREATE → REGISTER_CANDIDATE → REVIEW → SANDBOX_TEST → READY_FOR_PROMOTION → MERGE_AUTHORIZED → MAIN_READBACK → ACTIVATE_AUTHORIZED → VERIFY → DEPRECATE_OR_ROLLBACK`.

This lot may prepare and qualify source. Merge and activation remain separate decisions.

## No duplicación

Do not create another FULL_REGRESSION, router, applicability engine, registry, carrier path or currentness engine.
