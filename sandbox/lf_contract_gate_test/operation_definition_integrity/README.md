# Operation Definition Integrity Core V1

Status: `SHADOW_CANDIDATE`

## Purpose

Provide one deterministic, read-only evaluator for the **structural integrity of an LF operation definition**.

This is not Contract Check. It is a transversal primitive that may be consumed by Contract Check, lifecycle/materialization controls, or other governed consumers that need the same structural invariants.

```text
canonical operation-definition snapshot
        |
        v
OPERATION_DEFINITION_INTEGRITY_CORE_V1
        |
        +-- active contract identity/path/SHA
        +-- active step identity
        +-- required step -> active step-contract cardinality
        +-- step-order coherence
        +-- transition-target coherence
        +-- required step -> active judge-binding cardinality
        +-- active judge-binding -> active judge existence
        +-- mini_judge_code <-> bound judge coherence
        +-- required policy identity/resolution
        |
        v
     PASS / BLOCK
```

## Architectural boundary

The Router only routes a request to its top-level operation (for example `PASE`). It does not decide pass controls or their order.

Inside `PASE`, pass governance decides applicability and the pass planner/orchestrator coordinates the applicable controls. If Contract Check applies, Contract Check may consume this integrity result instead of reimplementing the same invariants.

This core MUST NOT:

- decide whether a request needs a pass;
- decide which pass controls apply;
- construct or execute a pass plan;
- select the contract applicable to a business/request context;
- implement Contract Check semantics;
- call Migration Parity, Validate Packs, Assurance, P0, Runtime, DB Regression, or sibling controls;
- create, mutate, promote, materialize, or deprecate operations/contracts/bindings/policies/assets;
- call GitHub or Supabase;
- own currentness/evidence freshness;
- judge runtime/business output quality.

## Authority surfaces consumed by the caller

The caller may project the snapshot from existing LF authority surfaces. This candidate introduces no parallel authority schema:

- `public.v_lf_operation_contract`
- `public.v_lf_operation_steps`
- `public.v_lf_operation_step_contracts`
- `public.lf_operation_step_judge_bindings`
- `public.lf_operation_judges`
- `public.v_lf_operation_policy_snapshot`

The core receives only the projected snapshot and performs no database access itself.

## Ordering rule corrected from the previous candidate

`public.v_lf_operation_steps.execution_order` is not a required structural invariant. Current canonical data can legitimately expose it as `NULL`, while executable ordering is represented on step-contract materialization.

Therefore V1 does **not**:

- require `steps[].execution_order`;
- require it to be unique;
- require `step_contract.execution_order == step.execution_order`.

The structural cross-surface invariant retained here is `step_order` coherence between the operation step and its step contract / judge binding.

This prevents the validator from forcing canonical data to conform to an invented rule.

## `resolver_ref` boundary

`resolver_ref` is heterogeneous free text across LF. V1 therefore:

- blocks missing/blank `resolver_ref` for a required step contract;
- does **not** claim semantic resolution of the value;
- reports `definition_scope.resolver_ref_semantic_resolution=false`.

Typed resolver normalization is a separate data-model concern.

## Currentness / evidence boundary

`operation_revision_sha256` and other freshness/currentness assertions are outside this structural evaluator. They belong to the caller's evidence/currentness envelope and must not be turned into operation-definition semantics.

The output includes only a deterministic `snapshot_sha256` so callers can bind evidence to the exact evaluated snapshot.

## Rollout

This candidate remains intentionally inactive.

Before any activation it must demonstrate:

- deterministic positive/negative tests;
- compatibility with the live shape of canonical LF operation definitions, including nullable step `execution_order`;
- no duplicate implementation of the same invariant inside Contract Check;
- explicit consumer wiring in a separate approved change.

No workflow activation, merge, deployment, Supabase mutation, runtime change, or production change is part of this candidate.
