# PROGRAMMING_SIMPLE_EXECUTOR_V1

## Objective

Provide a small automatic programming executor for atomic plans without inheriting the complexity of `ENGINEERING_PARALLEL_EXECUTOR_V1`.

The executor works on the existing canonical plan/work/checkpoint ledger, but it owns its own admission, validation/resolution registry and run state.

## Core invariants

1. One lane owns one unit until that unit is terminal or yields for a real local blocker.
2. A unit evaluates only its own required checkpoints.
3. A dependency is a state precondition only. A dependent unit never re-executes the dependency's checkpoints.
4. Simple plans accept only explicit `REQUIRES` edges between units in the same plan.
5. The dependency graph must be a DAG before any run starts. Circular or cross-plan dependencies reject the plan.
6. A required checkpoint must bind exactly one admitted validation.
7. Reuse never imports a previous PASS. Existing validators/resolvers may be reused, but the validator must execute again for the current unit/checkpoint/run.
8. A resolver can repair a FAIL but cannot close a checkpoint. The original/post validator must run again and produce PASS.
9. A `BLOCKING_AUTOMATIC` validation is admitted only when both the validator and its active resolver have deterministic handlers and proven positive/negative/post-repair test references.
10. A rule without a deterministic, proven validation is not admitted. It must be replaced with a measurable rule or explicitly modeled as a human decision.
11. A failure blocks only its owning unit. Other dependency-clear units continue.
12. No title inference, inherited IG gates, prior runtime PASS reuse, or automatic production/runtime activation.

## Registry

### `programacion.programming_validation_registry`

Canonical validator contract.

Required for ACTIVE:
- deterministic handler;
- input contract;
- explicit PASS condition;
- explicit FAIL condition;
- fresh qualification proof for positive and negative behavior;
- exact `lf_test_runs.test_run_id` values for those qualification tests;
- each qualification test must identify the exact validation subject and test role in metadata.

Admission never searches prior plan/unit runtime history.

Modes:
- `BLOCKING_AUTOMATIC`: requires an ACTIVE deterministic resolver.
- `HUMAN_DECISION`: deterministic detection, but the decision itself remains human.
- `CHECK_ONLY`: informational/non-blocking and cannot back a required checkpoint.

### `programacion.programming_resolver_registry`

Canonical repair contract.

Every resolver is tied to:
- one validation;
- one failure code;
- deterministic preconditions;
- a deterministic resolver handler;
- a post-validation code;
- resolver test evidence;
- post-repair validation test evidence.

A resolver never grants PASS. For `BLOCKING_AUTOMATIC`, execution of the resolver is itself recorded as a current-run resolution receipt bound to the exact FAIL receipt hash. A PASS after a FAIL is rejected unless that receipt exists.

## Checkpoint binding

`programacion.programming_checkpoint_bindings` binds a required checkpoint to one validation/failure family.

The binding is structural. Runtime receipts remain per run.

## Runtime loop

```text
PLAN ADMISSION
  -> DAG valid
  -> required checkpoints bound
  -> bound rules admitted

READY UNIT
  -> current required checkpoint
  -> execute validator
       PASS -> record receipt -> transition checkpoint DONE
       FAIL -> resolver (automatic) OR human decision
                   -> record current resolution receipt
                   -> re-run validator
                   -> PASS -> transition checkpoint DONE
  -> next checkpoint
  -> unit DONE
  -> release dependent units
  -> refill lane
```

## Reuse policy

```text
REUSE != BYPASS

reuse validator/resolver implementation
        +
execute against current state
        +
new validation/resolution receipts tied to run + unit + checkpoint
        =
current PASS/FAIL
```

Qualification evidence may justify that a procedure is PROVEN/ACTIVE. This is not history-of-use for the target unit: it is the validator/resolver's own positive/negative/repair test proof.

A new rule with no prior runtime history is valid: before ACTIVE it runs its qualification tests once and stores their exact `lf_test_runs.test_run_id` values. Runtime admission resolves those exact IDs by primary key; it does not scan prior plan/unit history. The test row must also carry `programming_subject_type`, `programming_subject_code`, and `programming_test_role` matching the validator/resolver being admitted.

Prior runtime PASS from any other unit/run can never satisfy the current checkpoint.

## Dependency policy

Only explicit same-plan `REQUIRES` edges participate in scheduling.

```text
A -> B means:
B may start only after A is DONE.

It does NOT mean:
B reruns A,
B inherits A's gaps,
or B imports A's validation controls.
```

Any cycle or cross-plan `REQUIRES` edge rejects the plan before execution.

## Parallelism

Default width: 4 lanes, configurable by the caller.

There is no checkpoint-count turn cap. A claimed unit runs through all of its own required checkpoints until DONE or a real local yield. When a lane finishes/yields, the scheduler may refill it with another dependency-clear unit.

## Intended first consumer

The atomized B2B Shell plan (S01-S09 and sub-units) is the first intended consumer. No B2B rule is activated merely by creating this executor; each rule must pass registry admission first.


## Shared checkpoint storage guard

The executor reuses `programacion.engineering_work_checkpoints`, but it does not inherit the IG material-assertion contract merely because storage is shared. The global DONE trigger selects the closure contract explicitly:

- checkpoint with an enabled `programming_checkpoint_bindings` row -> current-run Programming Simple validation receipt contract;
- every other checkpoint -> the pre-existing Engineering/IG material assertion contract unchanged.

This is contract selection, not a bypass: the simple path still requires an admitted rule, exact current run/unit/checkpoint binding, PASS receipt hash integrity, and an active run/lane.
