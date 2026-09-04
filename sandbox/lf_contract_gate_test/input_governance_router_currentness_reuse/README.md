# Input Governance Router Currentness Reuse — P0 candidate

Status: SOURCE_ONLY / SANDBOX / NO_DDL / NO_PRODUCTION
Base Main: d23d704705289dd12944540732524f67fe6da8da

## Goal
Remove duplicated currentness/worker-spec recomputation inside `programacion.fn_lf_router_input_governance_resolve_v1` without weakening Input Governance semantics, depth, freshness, validator coverage, EKB checkpoints, fail-closed behavior, or end-to-end profile execution quality.

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

## End-to-end acceptance is mandatory
Micro-benchmarks are diagnostic only. No candidate may be called improved, accepted, or ready based on a faster SQL function, Router subcall, cache helper, or profile substage in isolation.

The acceptance unit is the complete governed journey from user/profile request to final profile result and durable evidence:

`request -> ACT-0001 Router -> adapter resolution -> Input Governance -> artifact/input binding -> profile runtime request -> model inference -> output validation -> attestation/verifier -> result persistence/readback`

For every A/B case, measure both baseline and candidate over the SAME complete journey and SAME governed inputs. Report at minimum:
- end-to-end wall-clock latency p50/p95;
- Router latency;
- Input Governance latency;
- runtime preparation/queue/model-load latency where applicable;
- profile inference latency;
- validation/attestation/readback latency;
- total input context size / prompt chars or tokens when observable;
- output size;
- final semantic verdict and blocking code;
- exact artifact/input SHA bindings;
- governance run/snapshot/contract hashes;
- adapter invocation count and receipts;
- final durable execution/result state.

A local gain is rejected if it causes any downstream regression large enough that end-to-end performance does not materially improve, or if it increases model context, retries, duplicate work, queueing, inference time, output inflation, or verification cost without evidence-backed benefit.

## Required E2E scenario matrix
The candidate must be exercised across structurally different paths, not one screen or one profile only:
1. canonical screen + current governance + UI Architect;
2. canonical screen + current governance + Product Director LF;
3. canonical screen + current governance + Quality Pack;
4. non-canonical artifact / ADVISORY_READ_ONLY profile execution;
5. current run with no relevant change / receipt reuse path;
6. stale source path requiring governed re-evaluation;
7. invalidated or mismatched receipt negative;
8. ambiguous/unresolved subject negative;
9. BLOCKED or HUMAN_DECISION_REQUIRED governance path;
10. at least one batch/multi-profile execution to detect shifted latency, queue, cache, or context costs.

Where a path cannot be safely manufactured without mutating product truth, use an existing live case or a transactionally rolled-back/sandbox fixture and record that limitation explicitly. Do not create artificial product drift merely to make a benchmark pass.

## Quality and depth equivalence gate
A candidate fails even if faster when any of the following changes without governed justification:
- Story/Implementation/QA/Production gate result;
- 47-family Validator coverage or semantic validation requirement;
- EKB checkpoint set or fail-closed semantics;
- freshness/currentness result;
- source authority or negative requirements;
- artifact/revision binding;
- profile/adapters selected by Router;
- output schema validity;
- semantic judge/score/rubric outcome where applicable;
- material requirements preserved in the profile output;
- blocker/human-decision behavior.

For profile outputs, compare semantic obligations and decision quality, not only JSON equality. Exact equality is preferred for deterministic governance projections; profile generation must satisfy the same rubric/judge/required-obligation thresholds.

## Acceptance matrix
A candidate may advance only if A/B proves:
- end-to-end p50 and p95 latency materially lower than baseline;
- no material latency transfer from Router/Input Governance into runtime/inference/verification;
- semantic projection equality for READY, BLOCKED, HUMAN_DECISION_REQUIRED and runtime-required governance paths;
- identical governance decision and `continuation_allowed`;
- identical run_id, pantalla_id, screen_code and snapshot/contract hashes for equivalent current cases;
- no reduction in 47-family Validator requirements or EKB checkpoints;
- no new direct LLM call;
- no increase in model context or output size unless independently justified by quality gain;
- same or better profile rubric/judge outcome on the E2E profile cases;
- negative stale/invalidated/mismatched receipt cases fail closed;
- final durable execution/result/readback remains complete and traceable.

A candidate that improves one component but worsens the complete journey is rejected.

No migration, Supabase DDL, merge, VIGENTE, promotion or production authorization is included in this source-only reservation.
