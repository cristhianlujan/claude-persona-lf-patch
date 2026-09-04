# Input Governance Router Currentness Reuse — P0 candidate

Status: SOURCE_ONLY / SANDBOX / NO_DDL / NO_PRODUCTION
Base Main: d23d704705289dd12944540732524f67fe6da8da

## Goal
Remove duplicated currentness/worker-spec recomputation inside `programacion.fn_lf_router_input_governance_resolve_v1` without weakening Input Governance semantics, depth, freshness, validator coverage, EKB checkpoints, or fail-closed behavior.

## Existing proof that must be reused, not bypassed
`programacion.fn_input_governance_execute` already performs:
- PRE_EXECUTION EKB checkpoint;
- latest completed run resolution;
- freshness delta;
- ARC-015-compatible cached currentness fallback;
- full family-count and 47/47 Validator authorization checks;
- PRE_CURATOR / PRE_VALIDATOR / PRE_STORY_GATE / PRE_CONTEXT_MANIFEST / CLOSE_EKB checkpoints;
- known-current stage/evaluation/internal-remediation/context-manifest helpers;
- a `worker_spec` bound to the same current run.

The Router currently performs an additional full `fn_input_governance_worker_spec(...)` before `execute`, and performs strong `fn_input_readiness_run_is_current(...)` again after a READY result. Those are the candidate duplicate reads.

## Candidate invariant
Within the same STABLE Router statement snapshot, a READY result from `fn_input_governance_execute` is accepted only if all of the following are true:
1. `status=READY`;
2. `run_id`, `pantalla_id`, `screen_code` match the Router-resolved subject;
3. the returned `worker_spec.current_run_id` equals `run_id` and `worker_spec.required_role=NONE`;
4. the durable run row is still `COMPLETED`, `invalidated_at is null`, and contains non-null source/contract snapshot hashes;
5. the Router receipt binds those exact durable hashes plus `agent_output_sha256`.

No Story/Implementation/QA/Production gate, classifier, Validator, freshness, EKB checkpoint, source authority, or negative requirement is removed. The optimization only reuses proof already produced in the same governed execution.

## Fail-closed cases
- execute result missing/invalid worker_spec;
- worker_spec current_run_id mismatch;
- subject mismatch;
- missing durable source/contract hashes;
- run not COMPLETED or invalidated;
- non-READY execution statuses preserve current governed blocking/runtime-required behavior.

## Acceptance matrix
A candidate may advance only if A/B proves:
- semantic projection equality for READY, BLOCKED, HUMAN_DECISION_REQUIRED and runtime-required paths;
- identical governance decision and continuation_allowed;
- identical run_id, pantalla_id, screen_code and snapshot/contract hashes;
- no reduction in 47-family Validator requirements or EKB checkpoints;
- no new direct LLM call;
- p50 and p95 Router latency materially lower than baseline;
- negative stale/invalidated/mismatched receipt cases fail closed.

No migration, Supabase DDL, merge, VIGENTE, promotion or production authorization is included in this source-only reservation.
