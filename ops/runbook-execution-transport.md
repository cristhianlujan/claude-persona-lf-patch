# LF Execution Transport Trace — canonical process

## Purpose
Prevent false diagnosis of `NO_RUN`, `NO_STATUS`, `PENDING`, `NO_EVIDENCE` or missing CI as an evidence-only problem. Before quality or semantic conclusions, prove how a change moved from source to actual execution.

## Core invariant
`NO_RUN != NO_EVIDENCE`.

Evaluate these layers independently:
1. `TRANSPORT`: source/commit/ref reached the expected remote branch and trigger surface.
2. `DISPATCH`: an eligible event or explicit dispatch created a workflow run.
3. `EXECUTION`: run -> job -> runner -> checkout -> test discovery -> test execution occurred.
4. `QUALITY`: deterministic/profile gates passed on the exact executed input/head.
5. `SEMANTIC_UTILITY`: output is behaviorally useful/correct for the intended case.

Never use success at one layer as proof of a later layer.

## Mandatory trace
For any governed code/runtime change expected to execute through GitHub Actions or another dispatcher, trace:

`source change/commit -> branch ref -> remote ref -> workflow trigger eligibility -> event/dispatch -> workflow run creation -> job creation -> runner pickup -> checkout -> checked_out_head -> artifact/input availability -> test discovery -> test execution -> gate result -> published status/check`

For each hop record:
- `hop`
- `expected_input`
- `observed_input`
- `expected_output`
- `observed_output`
- `status = PASS | FAIL | NOT_OBSERVED`
- `latency_if_observable`
- `source_ref`
- `error_literal`
- `next_hop`

## Required derived fields
- `execution_transport_status = PASS | FAIL | PARTIAL`
- `first_failed_or_missing_hop`
- `commit_remote_present`
- `branch_points_to_head`
- `workflow_trigger_matches_branch_event`
- `dispatch_or_event_observed`
- `workflow_run_created`
- `job_created`
- `runner_started`
- `checkout_completed`
- `checked_out_head_matches_expected`
- `artifact_input_available`
- `tests_discovered`
- `tests_executed`
- `gate_result_observed`
- `status_published`

## Decision rules
### HEAD exists, no workflow run
Classify as `EXECUTION_TRANSPORT/CI_DISPATCH` until proven otherwise. Investigate branch/ref mismatch, workflow trigger mismatch, event not emitted, workflow disabled/not active on triggering ref, dispatch missing, concurrency cancellation/suppression, permissions/event restrictions, or equivalent causal conditions.

Do not label this as merely `NO_EVIDENCE`.

### Run exists, job not started
Investigate queue/concurrency, job `if` conditions, permissions, runner availability/labels and cancellation.

### Job starts, checkout absent/wrong
Investigate checkout step, ref selection, detached/stale head, permissions and repository/path mismatch. Exact-head binding is mandatory.

### Checkout succeeds, tests absent
Investigate artifact/input transfer, path filters, generated files, test discovery patterns, working directory, dependencies and conditional steps.

### Tests execute
Only now evaluate gate/quality. `execution_transport_status=PASS` does not imply quality PASS.

### Gate succeeds
Only now evaluate semantic utility when applicable. `quality PASS` does not imply semantic utility PASS.

## Recovery loop
`OBSERVE FIRST FAILED HOP -> EKB FOCAL -> SOURCE/SCHEMA/WORKFLOW INSPECTION -> CAUSE -> MINIMAL REVERSIBLE FIX -> RETEST SAME HOP -> CONTINUE TRACE -> READBACK`.

Do not increase timeout as a substitute for identifying the failed hop.

## EKB classification
When a reusable failure is proven, use one root-cause family according to first failed hop:
- `EXECUTION_TRANSPORT`
- `CI_DISPATCH`
- `RUNNER`
- `CHECKOUT`
- `ARTIFACT_TRANSFER`
- `TEST_DISCOVERY`
- `STATUS_PUBLICATION`

Record source ref, exact HEAD, run/job if present, first failed hop, prevention and validation.

## Closure/reporting
Any run involving a code/runtime change must report transport separately from execution, quality and semantic utility.

Minimum human-readable status:

| Layer | State | Meaning |
|---|---|---|
| Transport | 🟢/🟡/🔴 | Did the exact change reach the execution path? |
| Dispatch | 🟢/🟡/🔴 | Was a run actually created? |
| Execution | 🟢/🟡/🔴 | Did a runner checkout the exact head and execute the intended tests? |
| Quality | 🟢/🟡/🔴 | Did required quality gates pass? |
| Semantic utility | 🟢/🟡/🔴 | Is the result behaviorally useful/correct? |

The first red/yellow hop is the operational blocker; missing downstream evidence is a consequence until proven otherwise.
