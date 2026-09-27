# Contract Reference Integrity Core V1

Status: `SHADOW_CANDIDATE`

## Purpose

Validate an LF operation contract and its **formal references** without taking ownership of pass orchestration, applicability, sibling controls, runtime execution, or downstream control results.

```text
operation contract snapshot
        |
        v
CONTRACT_REFERENCE_INTEGRITY_CORE_V1
        |
        +-- active contract identity/path/SHA
        +-- active step identity/order
        +-- required step -> active step-contract cardinality
        +-- step transition target coherence
        +-- required step -> active judge binding cardinality
        +-- active judge binding -> active judge existence
        +-- mini_judge_code <-> bound judge coherence
        +-- required policy -> resolved policy SHA
        |
        v
     PASS / BLOCK
```

## Explicit non-responsibilities

This core MUST NOT:

- determine which controls apply to a changeset;
- call Migration Parity, Validate Packs, Assurance, P0, Runtime, DB Regression, or any sibling control;
- evaluate whether a sibling control already passed or failed;
- create or mutate contracts, bindings, policies, operations, assets, or lifecycle state;
- call GitHub or Supabase;
- resolve user intent or select an operation through Router;
- judge runtime/business output quality.

Applicability remains owned by Router / Changeset Governance. Control execution remains owned by the pass orchestrator / `LF_GATE_GROUP_ORCHESTRATOR_V1`.

## Authority surfaces reused

The caller snapshot is projected from existing LF authority; no parallel contract schema is introduced:

- `public.v_lf_operation_contract`
- `public.v_lf_operation_steps`
- `public.v_lf_operation_step_contracts`
- `public.lf_operation_step_judge_bindings`
- `public.lf_operation_judges`
- `public.v_lf_operation_policy_snapshot`
- `public.lf_operation_revision_sha256_v1(operation_code)`

The existing `fn_lf_operation_registry_materialization_guard_v1` independently demonstrates the required-step/contract/judge-binding invariant at materialization time. This core exposes equivalent integrity checks as a read-only deterministic evaluation over a supplied snapshot.

## `resolver_ref` boundary

`resolver_ref` is currently heterogeneous free text across LF (PostgreSQL objects, runtime tokens, asset identifiers, GitHub readers/writers, compound expressions, and other symbolic executors). There is no single typed resolver registry that can truthfully prove semantic existence for every value.

V1 therefore:

- blocks a missing/blank `resolver_ref` for required steps;
- does **not** claim semantic resolution of the string;
- reports `formal_reference_scope.resolver_ref_semantic_resolution=false`.

Normalizing resolver references is a separate data-model concern and must not be hidden inside Contract Check.

## Rollout

This candidate is intentionally inactive. Initial validation target is the current `GITHUB_CONTRACT_GATE_LF` authority because its active contract, required step-contract coverage, judge bindings, judges, and required policy refs are currently complete. It must not be globally enforced while unrelated operational records still have known legacy contract/binding debt.

## Findings driving the split

- `PASE-CONTRACT-CHECK-ORCHESTRATOR-IDENTITY-CONFLATION-001`
- `PASE-CONTRACT-CHECK-UNTYPED-RESOLVER-REF-001`

No Supabase mutation, workflow activation, deployment, or production change is part of this candidate.
