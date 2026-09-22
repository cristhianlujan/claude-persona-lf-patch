# LF Work Protocol Manifest V1

Status: CANDIDATE / OPT-IN / NO RUNTIME ACTIVATION

## Purpose

Bind planning, execution, evidence and closure to one frozen protocol without creating a second authority.
The human operating cycle remains `.claude/operational-execution.md`. This contract makes the obligations machine-readable.

## Authority model

The manifest is a frozen projection of existing canonical authority, never a replacement for it:

- `public.lf_operation_registry`
- `public.lf_operation_contracts`
- `public.lf_operation_steps` / `public.lf_operation_step_contracts`
- `public.lf_operation_judges` / `public.lf_operation_step_judge_bindings`
- `public.lf_operation_policy_bindings`
- operation-specific source authority

`public.lf_operation_execution.manifest.work_protocol_manifest` is the carrier.
Execution evidence remains in `public.lf_operation_execution_steps`.

## G00 Owner-first entry gate

Ownership is declared before authority resolution or any material work. The frozen manifest carries a required `work_owner` binding with:

- `owner_id`: accountable owner of this execution/workstream;
- `owner_type`: `HUMAN | AGENT | TEAM`;
- `declaration_ref`: canonical reference to the authorization/request that declared the owner;
- `declaration_sha256`: must equal the exact `request_sha256`;
- `change_mode=SUPERSEDE_NEW_EXECUTION`: ownership cannot be reassigned in place.

Missing, malformed or request-mismatched ownership fails closed before freeze. Because the owner binding is inside the immutable manifest, any mid-execution owner mutation invalidates currentness. A legitimate owner change requires a newly authorized execution/supersession; it cannot be silently inherited or inferred later.

This is execution/workstream ownership, not PostgreSQL object ownership and not the temporary lease owner.

## Lifecycle

```text
DECLARE OWNER
→ RESOLVE AUTHORITY
→ FREEZE MANIFEST
→ CANONICAL OPERATION-SPECIFIC BEGIN / RESERVE
→ EXECUTE REQUIRED OBLIGATIONS
→ ON TIMEOUT: CHECKPOINT → REDUCE WORK UNIT / RESUME → RETRY
→ RECORD OBSERVED EVIDENCE
→ DERIVE PROGRESS
→ INDEPENDENT CLOSE CHECK
→ PASS_WITH_EVIDENCE | RETURN_TO_WORKER | BLOCKED | STALE_AUTHORITY
```

## Hard invariants

**Owner-first precondition:** `work_owner` must be explicit, request-bound and frozen before authority resolution. It may never be inferred later from a branch, PR author, lease holder, blocker owner or previous execution.

1. Freeze before first material effect. A manifest created after an effect cannot certify that execution.
2. `manifest_digest` is SHA-256 over LF canonical JSON with the `manifest_digest` field removed, and is immutable after canonical reservation. Python and Postgres must compute the same digest on the same payload.
3. `request_sha256` binds the frozen protocol to the exact execution request; an adapter must reject a manifest whose request digest or target differs from the canonical begin request.
4. `operation_revision_sha256` must equal the current canonical operation revision before material effect and at closure.
5. The active contract revision, active policy versions/SHAs, required step set, step contracts and step-judge bindings are fingerprinted at freeze time. A revision hash that omits any of those layers is insufficient for closure.
6. Every required obligation maps to an active operation step and declares all evidence keys required by the canonical step contract/judge binding.
7. Progress is derived from verified required obligations. Producer-supplied percentages are non-authoritative and prohibited by contract.
8. Missing evidence never counts as progress. `NO_APLICA_CON_MOTIVO` cannot satisfy an obligation declared `required=true`.
9. A blocking required obligation makes the aggregate execution blocked even if later steps claim PASS.
10. An obligation requiring independent readback/semantic/composite verification must be bound to a distinct persisted verifier execution targeted to the producer execution; a role label alone is not evidence of independence.
11. 100% requires all required obligations verified, zero blockers, current authority, immutable manifest, exact request/target binding, and a verified independent closure step.
12. A currentness mismatch returns `STALE_AUTHORITY`; it must not be reinterpreted as PASS.
13. Scope/effect deviations outside `authorized_scope` are blocking. `authorized_scope` must carry a provenance reference and digest; the generic manifest does not invent authorization.
14. Existing operations do not become governed by this contract implicitly. Adoption is opt-in until a separate governed rollout proves compatibility.
15. A timeout is an execution condition, not a gate verdict. While recovery remains within policy it yields `RECOVERING`/in-progress semantics, never PASS and never FAIL solely because time elapsed.
16. Verified progress already read back MUST survive timeout recovery. Recovery may retry only the unresolved unit; it must not invalidate previously verified obligations unless authority/currentness drift independently invalidates them.
17. Each required obligation declares an execution class: `ATOMIC`, `CHUNKABLE` or `CHECKPOINTABLE`, plus its timeout recovery mode. `CHUNKABLE` recovery must reduce the work unit; `CHECKPOINTABLE` recovery must resume from a durable checkpoint; `ATOMIC` recovery may only retry the same atomic unit.
18. Recovery is bounded. Exhausting the configured recovery attempts yields `BLOCKED_OPERATIONAL_TIMEOUT`; it does not rewrite the gate as a semantic FAIL.

## Derived progress

```text
progress_percent = floor(100 * verified_required / total_required)
```

`verified_required` counts only obligations whose execution step is clean under the canonical operation judge binding and whose required evidence keys are present. Independent verifier modes additionally require evidence not authored solely by the producer.

## Evidence and independent verification

Every recorded gate that is eligible to count toward progress carries a machine-checkable exact evidence envelope under `evidence_payload.work_protocol_evidence`.

The envelope binds:

- `execution_id`, `step_id`, `gate_contract_sha256` and the execution that produced the evidence;
- a concrete reproduction locator and reproduction specification, never a narrative-only “OK”;
- SHA-256 of the reproduction specification, exact input, result and current source revision;
- result reference, result count and observation timestamp.

The V1 evidence policy is frozen in the manifest and is fail-closed:

- exact envelope required;
- reproduction specification required;
- evidence must be observed after canonical execution start;
- future timestamps beyond the allowed clock skew are rejected;
- evidence older than the frozen freshness window is stale and cannot count toward progress;
- the freshness window may be stricter per execution but cannot exceed 24 hours in V1.

For `INDEPENDENT_READBACK`, `SEMANTIC_JUDGE`, `COMPOSITE` and the closure gate, inline producer evidence is insufficient. A verified receipt from the existing append-only `private.lf_evidence_ledger_v1` is required. The protocol does not create a second evidence ledger.

The ledger receipt must bind the same execution, gate, result digest, source revision and reproduction-spec digest, and its `created_by_execution_id` must be the independent verifier execution. The verifier execution must be distinct from the producer and target the producer execution. `VERIFIED` ledger state must include provider readback and digest recomputation proof.

Evidence history is never rewritten to “fix” a prior result. A new observation or verification creates new evidence/receipt history; the previous receipt remains append-only. Evidence from another execution cannot satisfy the current execution.

## Solution / PR isolation

Any material solution that is materialized in Git MUST own its own dedicated pull request. A pull request is a change-isolation boundary, not a transport bucket.

The frozen manifest carries a required `solution_isolation_policy` with these fail-closed invariants:

- `unit_mode=ONE_SOLUTION_PER_PR`: one independently closable solution unit per PR;
- `mixed_solution_pr_allowed=false`: unrelated fixes, remediations, migrations, refactors or opportunistic cleanup cannot share the same PR;
- `scope_expansion_requires_new_pr=true`: discovering a second solution or materially expanding the original solution requires a new PR/execution boundary instead of widening the current PR;
- `migration_apply_requires_separate_pr=true`: when a solution also requires deployable database migration materialization/apply, that migration is promoted through its own migration-only PR after the candidate solution has been qualified;
- `receipt_must_bind_exact_pr_scope=true`: candidate/closure receipts must bind the exact PR head and exact solution scope; a receipt from another PR or broader/narrower solution scope is invalid.

Tests, documentation and evidence that are necessary to prove the same solution MAY remain in that solution's PR. The prohibition is against multiple independently closable solutions sharing one PR, not against the artifacts required to verify one solution.

If a PR contains more than one independent solution unit, the protocol result is BLOCKED and the work must be split before merge. This rule exists to constrain blast radius, prevent cross-solution CI/currentness contamination, make rollback and ownership unambiguous, and stop one repair from invalidating or masking another.

## Change control, waivers and irreversible actions

V1 treats control changes as a new governed execution, never as an in-place edit of a frozen manifest.

### Scope change / supersession

Any material change to authorized scope after freeze MUST:

1. create a new execution id;
2. carry a new request/authorization digest;
3. bind the exact previous execution id and previous manifest digest;
4. prove the previous and new authorized-scope digests;
5. declare `revalidation_mode=FULL_REQUIRED`;
6. carry forward **zero** verified progress.

The previous execution remains immutable and is derived as `SUPERSEDED_SCOPE_CHANGE` once a valid successor exists. V1 deliberately chooses full revalidation rather than guessing which prior gates remain valid.

### Waivers

Waivers are explicit and frozen before execution. They carry the waived requirement id, reason, residual risk, authorizing identity/reference/digest and expiry.

V1 is intentionally conservative:

- required obligations cannot be waived;
- closure, authority/currentness, exact evidence and irreversible-action controls cannot be waived;
- only an optional obligation whose canonical step authority explicitly says `waiver_allowed=true` may carry a waiver;
- waiver lifetime is bounded by the manifest policy and cannot exceed one hour;
- a waiver never rewrites a historical gate verdict and never counts as verified progress;
- adding or changing a waiver after freeze requires supersession and a new authorization.

### Irreversible actions

Canonical step authority declares three control fields:

- `waiver_allowed`;
- `irreversible_effect`;
- `human_approval_required`.

Work Protocol adoption fails closed while these fields are unset for an adopted step.

Every `irreversible_effect=true` step MUST also have `human_approval_required=true` and an exact pre-frozen approval binding. The approval binds the step id, exact action SHA-256, human identity/reference/digest, approval time and expiry. The execution evidence for that step must carry the same `irreversible_action_sha256`; mismatch, expiry, absence or non-human approval binding blocks the step before it can count toward progress.

The Work Protocol does not invent who is authorized to approve. The approval reference/digest must come from the upstream human authorization authority and is frozen as provenance.

## Execution controller

G07 makes step sequencing executable instead of advisory. It reuses the canonical operation execution, step, lease and checkpoint primitives; it does not create a parallel scheduler authority.

Each obligation freezes canonical controller metadata:

- `depends_on_step_ids`: DAG predecessors;
- `closure_unit_id`: material closure slice that owns the step;
- `controller_order`: deterministic tie-break order;
- `execution_effect`: `READ_ONLY | MUTATING | JUDGE | CLOSURE`;
- `parallel_safe`: whether a read-only step may run with another ready read-only step in the same closure unit.

The controller policy is fail-closed:

- dependency graph comes from canonical step authority;
- material WIP limit is exactly one;
- parallel work is allowed only for `READ_ONLY` + `parallel_safe=true` steps in the same closure unit;
- every activation requires the existing execution lease and matching fence;
- activation is persisted through the existing monotonic checkpoint primitive;
- a failed or blocked predecessor blocks dependents;
- restart/resume derives the next frontier from canonical execution rows + frozen manifest + checkpoint, never from chat history.

A step may be recorded only when the controller checkpoint names it as active. The only bootstrap exception is the operation's first initialization step created transactionally by its governed begin RPC.

The controller selects the frontier deterministically:

1. discard already verified steps;
2. reject unknown dependencies or DAG cycles at freeze;
3. mark steps with failed/blocked predecessors as blocked;
4. mark steps with incomplete predecessors as waiting;
5. among dependency-complete steps, choose the earliest closure unit by canonical controller order;
6. allow at most one non-read-only step; read-only parallelism is bounded to the chosen closure unit;
7. persist the exact active step set, closure unit, lease fence and plan digest in the checkpoint before work proceeds.

When a recorded step becomes verified, a subsequent controller activation recomputes from canonical state. If the process stops between those events, a new run can recompute the same next frontier without losing verified progress.

## Closure controller

G08 prevents partial completion from becoming hidden closure debt. It works on the closure units already frozen by G07 and reuses the append-only evidence ledger; it does not create a second execution tracker.

A closure unit may advance to a terminal local state only as:

- `CLOSED_WITH_EVIDENCE`: every obligation in the unit is currently VERIFIED and a closure receipt is anchored to the exact unit-state digest;
- `BLOCKED_WITH_EVIDENCE`: the unit contains a blocked obligation and a blocking receipt is anchored with blocker reference, digest, reason, owner and next action.

Rules:

- the next closure unit cannot activate until every earlier closure unit is terminal as `CLOSED_WITH_EVIDENCE` or `BLOCKED_WITH_EVIDENCE`;
- `BLOCKED_WITH_EVIDENCE` never counts as verified progress and creates explicit closure debt;
- downstream work after a blocked unit remains additionally constrained by the G07 DAG, so a dependent step still cannot bypass a failed predecessor;
- global close requires every closure unit `CLOSED_WITH_EVIDENCE` and zero closure debt;
- closure receipts form a digest chain in canonical unit order;
- a later change in step/evidence state changes the unit-state digest and invalidates the old receipt, yielding `REOPEN_REQUIRED`;
- when an earlier unit is reclosed with a new receipt, downstream receipts whose previous-receipt binding no longer matches also become `REOPEN_REQUIRED`;
- reopening never mutates an old receipt: a new append-only receipt supersedes the stale one through current-state selection.

The controller therefore allows bounded continuation after an explicitly evidenced blocker while making terminal closure impossible until the debt is actually resolved and reclosed.

## Gate contract

Each required obligation is also a gate. The frozen manifest carries a canonical `gate_type` and `gate_contract_sha256` derived from the live operation step contract and active judge binding; the producer cannot invent either value.

Gate types are:

- `ENTRY`: first required gate for the execution;
- `STEP`: intermediate gate;
- `EXIT`: final required non-closure gate;
- `CLOSURE`: the independently verified closure gate.

The canonical gate contract projects, at minimum:

- preconditions from `lf_operation_step_contracts.input_required`;
- deterministic check definition from `execution_sql`, `pass_condition`, `fail_condition` and `block_condition`;
- judge binding and canonical result values from `lf_operation_step_judge_bindings`;
- required evidence keys from step contract plus judge binding;
- `deterministic_before_judge=true`;
- `fail_closed=true`;
- normalized verdict mapping:
  - canonical clean result → `PASS`;
  - canonical return result → `FAIL`;
  - canonical blocked result → `BLOCKED`.

A gate evaluation is valid only when:

1. its `gate_contract_sha256` matches the current frozen contract;
2. required evidence is present;
3. a deterministic result exists when deterministic checks are defined;
4. if deterministic result is not PASS, the judge is not used to override it;
5. if deterministic result is PASS and a judge is required, a judge result exists and is sequenced after the deterministic check;
6. missing check output, missing judge output, mismatched contract hash or invalid sequencing fail closed.

`WAIVED` is not a gate verdict. It is a separate disposition handled by the waiver/change-control layer and never rewrites a historical gate verdict.

## Adaptive execution and timeout recovery

Every frozen manifest carries an execution policy. Each obligation declares:

- `execution_class`: `ATOMIC | CHUNKABLE | CHECKPOINTABLE`;
- `timeout_recovery_mode`: `RETRY_ATOMIC | REDUCE_UNIT | RESUME_CHECKPOINT`;
- `checkpoint_required`;
- `idempotent`.

The controller applies:

```text
TIMEOUT
→ persist/read back checkpoint when required
→ preserve already verified obligations
→ choose recovery permitted by execution_class
→ retry only unresolved work
→ if CHUNKABLE, next_work_unit < previous_work_unit
→ if CHECKPOINTABLE, resume from checkpoint_ref
→ if recovery budget exhausted, BLOCKED_OPERATIONAL_TIMEOUT
```

A timeout event must carry a recovery attempt number and strategy evidence. Missing or contradictory recovery evidence is fail-closed as a protocol error; a valid timeout recovery remains operationally in progress.

Execution condition and gate verdict are separate channels. `lf_operation_execution_steps.status` remains reserved for canonical judge result values and MUST NOT be overloaded with `TIMEOUT_RECOVERING`, `RETRYING_SMALLER` or `RESUMING`. The controller stores the current recovery condition in the execution checkpoint and records recovery history as append-only events; only the eventual gate evaluation writes the canonical step verdict.

## Closure states

- `RECOVERING`: at least one required obligation is in valid timeout recovery and recovery budget remains.
- `IN_PROGRESS`: at least one required obligation remains unverified and there is no blocking condition.
- `RETURN_TO_WORKER`: verification failed but repair remains within authorized scope.
- `BLOCKED`: a blocking obligation failed, required evidence is impossible/currently unavailable, or scope was violated.
- `STALE_AUTHORITY`: frozen operation/contract/policy authority no longer matches current authority.
- `PASS_WITH_EVIDENCE`: only after 100% derived progress and all closure invariants pass.

## Non-goals

- no new business-state authority;
- no duplicate operation registry;
- no replacement for domain contracts;
- no global activation in V1;
- no production/runtime promotion.
